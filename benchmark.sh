#!/usr/bin/env bash
# ==============================================================================
# benchmark.sh — Docker image benchmark for Java Dockerfile comparison
#
# Usage:
#   ./benchmark.sh                     # default: 1 run per phase, Markdown table
#   RUNS=3 ./benchmark.sh              # average over 3 runs per phase
#   OUTPUT_CSV=1 ./benchmark.sh        # also write benchmark.csv
#   DEBUG=1 ./benchmark.sh             # verbose logging to stderr
#   TIMEOUT_BUILD=900 ./benchmark.sh   # per-build timeout (seconds, default 600)
#
# Output columns:
#   tag        — Dockerfile suffix (e.g. "fat" from Dockerfile.fat)
#   cold (ms)  — build from scratch, no cache (--no-cache)
#   warm (ms)  — rebuild with no source changes, all layers cached
#   incr (ms)  — rebuild after adding one new .java file (partial cache miss)
#   layers     — number of image layers
#   size (MiB) — uncompressed image size
#   ram (MiB)  — peak RSS during a short container run
#   score      — composite: lower is better
#               formula: (cold/1000)*0.3 + (incr/1000)*0.3 + size_mib*0.3 + ram_mib*0.1
#               rationale: cold & incremental build time matter equally to size;
#                          RAM is less critical for batch/lecture workloads.
#
# Requirements: bash ≥ 3.2 (macOS), one of: docker / podman / nerdctl,
#               awk (any POSIX awk), python3 or perl (macOS timing fallback)
# Override runtime:  CONTAINER_CLI=podman ./benchmark.sh
# ==============================================================================

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
DEBUG="${DEBUG:-0}"
OUTPUT_CSV="${OUTPUT_CSV:-0}"
TIMEOUT_BUILD="${TIMEOUT_BUILD:-600}"
RUNS="${RUNS:-1}"          # number of measurements per phase (results are averaged)

BASE_NAME="javahello"
PACKAGE_PATH="src/main/java/fr/univtln/bruno/demos/docker"
SPI_DIR="src/main/resources/META-INF/services"
SPI_FILE="$SPI_DIR/fr.univtln.bruno.demos.docker.Marker"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

# ── Logging ───────────────────────────────────────────────────────────────────
log()  { [[ "$DEBUG" -eq 1 ]] && printf '[DEBUG] %s\n' "$*" >&2; }
info() { printf '[INFO]  %s\n' "$*" >&2; }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

# ── Runtime detection ─────────────────────────────────────────────────────────
# Honour explicit override, then try docker → podman → nerdctl in order.
if [[ -n "${CONTAINER_CLI:-}" ]]; then
    CLI="$CONTAINER_CLI"
elif command -v docker &>/dev/null; then
    CLI="docker"
elif command -v podman &>/dev/null; then
    CLI="podman"
elif command -v nerdctl &>/dev/null; then
    CLI="nerdctl"
else
    die "No container CLI found. Install docker, podman, or nerdctl, or set CONTAINER_CLI."
fi

# Verify the CLI is actually reachable (daemon running, socket accessible, …)
if ! "$CLI" info &>/dev/null; then
    die "'$CLI info' failed — is the daemon/socket running? (try: systemctl start docker  or  podman system service)"
fi

log "Using container CLI: $CLI"

# Detect whether we are on macOS so we can work around BSD userland differences.
IS_MACOS=0
[[ "$(uname -s)" == "Darwin" ]] && IS_MACOS=1

# ── macOS / BSD portability shims ─────────────────────────────────────────────

# timeout: GNU coreutils on Linux; brew install coreutils → gtimeout on macOS.
# We wrap it so callers can always write: run_timeout N cmd…
run_timeout() {
    local secs="$1"; shift
    if command -v timeout &>/dev/null; then
        timeout "$secs" "$@"
    elif command -v gtimeout &>/dev/null; then
        gtimeout "$secs" "$@"
    else
        # No timeout binary at all — run without a time limit and warn once.
        [[ "${_TIMEOUT_WARNED:-0}" -eq 0 ]] && {
            info "WARNING: 'timeout' not found — builds will not be killed on hang."
            _TIMEOUT_WARNED=1
        }
        "$@"
    fi
}

# date +%s%N: GNU date supports %N (nanoseconds); BSD date does not.
# Fall back to python3 / perl if needed (both present on any macOS with Xcode CLT).
_time_ns() {
    if [[ "$IS_MACOS" -eq 0 ]]; then
        date +%s%N
    elif command -v python3 &>/dev/null; then
        python3 -c 'import time; print(int(time.time_ns()))'
    elif command -v perl &>/dev/null; then
        perl -MTime::HiRes=time -e 'printf "%d\n", time()*1e9'
    else
        # Last resort: second-level precision only
        printf '%d000000000' "$(date +%s)"
    fi
}

# find -printf: GNU find only. On macOS use a plain find + basename pipeline.
_find_dockerfiles() {
    if [[ "$IS_MACOS" -eq 0 ]]; then
        find . -maxdepth 1 -type f -name "Dockerfile.*" -printf "%f\n"
    else
        find . -maxdepth 1 -type f -name "Dockerfile.*" | xargs -I{} basename {}
    fi
}

# sort -V (version sort): GNU coreutils only. On macOS fall back to plain sort.
# Dockerfile names are usually well-ordered anyway (01-, 02- or fat/slim/…).
_sort_v() {
    if sort --version 2>/dev/null | grep -q GNU; then
        sort -V
    else
        sort
    fi
}

# ── Discover Dockerfiles ──────────────────────────────────────────────────────
# mapfile requires bash ≥ 4.3. macOS ships bash 3.2 — use a while-read loop
# as a universal fallback (works on bash 3.2+).
DOCKERFILES=()
while IFS= read -r f; do
    [[ -n "$f" ]] && DOCKERFILES+=("$f")
done < <(_find_dockerfiles | _sort_v)

[[ ${#DOCKERFILES[@]} -eq 0 ]] && die "No Dockerfile.* found in $ROOT_DIR"
log "Found ${#DOCKERFILES[@]} Dockerfile(s): ${DOCKERFILES[*]}"

# Collect failures to report at the end instead of aborting the whole run
declare -a FAILED_BUILDS=()

# ── Helpers ───────────────────────────────────────────────────────────────────

# Derive image tag from filename: Dockerfile.foo.bar → javahello:foo-bar
get_tag() {
    local suffix="${1#Dockerfile.}"
    echo "${BASE_NAME}:${suffix//./-}"
}

# Return elapsed milliseconds; never mixes stdout with the measured command's output.
# Usage:  ms=$(time_ms cmd arg…)
# Uses _time_ns for macOS/BSD portability (date +%s%N is GNU-only).
time_ms() {
    local start end
    start=$(_time_ns)
    "$@"
    end=$(_time_ns)
    printf '%d' $(( (end - start) / 1000000 ))
}

# Convert Docker size strings (KiB / MiB / GiB / TiB, or bare bytes) → MiB (float)
# Works with POSIX awk (mawk, gawk, nawk).
to_mib() {
    printf '%s\n' "$1" | awk '
    {
        val = $1; unit = $2
        if (unit == "kB" || unit == "KB" || unit == "KiB") { printf "%.3f", val/1024 }
        else if (unit == "MB" || unit == "MiB")             { printf "%.3f", val       }
        else if (unit == "GB" || unit == "GiB")             { printf "%.3f", val*1024  }
        else if (unit == "TB" || unit == "TiB")             { printf "%.3f", val*1048576 }
        else                                                 { printf "%.3f", val/1048576 }
    }'
}

# Split "1.23GB" → "1.23 GB" so to_mib gets two fields
normalise_size() {
    printf '%s\n' "$1" | sed 's/\([0-9.]*\)\([A-Za-z]*\)/\1 \2/'
}

# Run a single build; return duration in ms, or "" on timeout/error.
# Stdout/stderr go to /dev/null (or fd 2 in DEBUG mode).
_one_build() {
    local flags="$1" tag="$2" file="$3"
    local ms
    if [[ "$DEBUG" -eq 1 ]]; then
        # shellcheck disable=SC2086
        ms=$(time_ms run_timeout "$TIMEOUT_BUILD" "$CLI" build $flags -t "$tag" -f "$file" . 2>&1) || {
            log "Build failed: $file $flags"
            echo ""; return
        }
    else
        # shellcheck disable=SC2086
        ms=$(time_ms run_timeout "$TIMEOUT_BUILD" "$CLI" build $flags -t "$tag" -f "$file" . \
            >/dev/null 2>&1) || {
            log "Build failed: $file $flags"
            echo ""; return
        }
    fi
    printf '%s' "$ms"
}

# Run $RUNS builds with given flags, return rounded integer average (ms).
# Returns 0 and records a failure if any individual build fails.
run_builds() {
    local flags="$1" tag="$2" file="$3"
    local total=0 count=0 ms
    for (( i=0; i<RUNS; i++ )); do
        ms=$(_one_build "$flags" "$tag" "$file")
        if [[ -z "$ms" ]]; then
            FAILED_BUILDS+=("${tag} [${flags:-warm}]")
            printf '0'; return
        fi
        (( total += ms, count++ )) || true
    done
    printf '%d' $(( count > 0 ? total / count : 0 ))
}

# Peak RSS (MiB) during a quick container run.
# Polls stats every 100 ms until the container exits.
#
# Podman note: `podman stats` uses the same --format template as Docker for
# MemUsage, but may emit "X.XX GiB / Y.YY GiB" (already space-separated with
# IEC units). normalise_size + to_mib handle both forms.
#
# If stats are unsupported (some rootless Podman / cgroup v1 setups, nerdctl),
# we fall back gracefully and report 0 with a warning.
get_ram_peak() {
    local cid="$1"
    local peak=0 val val_mib

    # Quick check: does this runtime support stats at all?
    if ! "$CLI" stats --no-stream --format "{{.MemUsage}}" "$cid" &>/dev/null; then
        info "WARNING: '$CLI stats' not available for this container — RAM will read 0."
        printf '0.00'; return
    fi

    while "$CLI" ps -q --filter "id=$cid" 2>/dev/null | grep -q .; do
        # MemUsage format: "123.4MiB / 7.77GiB"  (Docker)
        #                  "123.4 MiB / 7.77 GiB" (Podman)
        # We only want the first field (current usage, before the slash).
        val=$("$CLI" stats --no-stream --format "{{.MemUsage}}" "$cid" 2>/dev/null \
              | awk '{print $1}') || break
        [[ -z "$val" ]] && break

        val=$(normalise_size "$val")
        val_mib=$(to_mib "$val")
        peak=$(awk "BEGIN { print ($val_mib > $peak) ? $val_mib : $peak }")
        sleep 0.1
    done

    printf '%.2f' "$peak"
}

# Number of layers in an image.
# Both Docker and Podman expose RootFS.Layers via inspect.
# nerdctl uses the same template. Falls back to 0 on error.
get_layer_count() {
    "$CLI" inspect --format '{{len .RootFS.Layers}}' "$1" 2>/dev/null || echo 0
}

# ── Incremental-build helper: inject a new .java file & SPI entry ─────────────
FAKE_JAVA=""   # global so cleanup trap can find it

cleanup_fake() {
    [[ -n "$FAKE_JAVA" ]] && rm -f "$FAKE_JAVA"
    [[ -f "$SPI_FILE" ]] && rm -f "$SPI_FILE"
    rmdir "$SPI_DIR" 2>/dev/null || true
    FAKE_JAVA=""
}
trap cleanup_fake EXIT

inject_fake_class() {
    local fake_class="Fake$(date +%s%N)"
    FAKE_JAVA="$PACKAGE_PATH/$fake_class.java"
    mkdir -p "$SPI_DIR"
    cat > "$FAKE_JAVA" <<JAVA
package fr.univtln.bruno.demos.docker;
public class $fake_class implements Marker { public void touch() {} }
JAVA
    echo "fr.univtln.bruno.demos.docker.$fake_class" > "$SPI_FILE"
}

# ── Header ────────────────────────────────────────────────────────────────────
fmt_header='| %-24s | %9s | %9s | %9s | %7s | %9s | %9s | %10s |'
fmt_row='| %-24s | %9d | %9d | %9d | %7d | %9.1f | %9.2f | %10.2f |'
sep='|:------------------------|----------:|----------:|----------:|-------:|----------:|----------:|-----------:|'

echo
echo "## Container image benchmark — \`${BASE_NAME}\`  (\`${CLI}\`)"
[[ "$RUNS" -gt 1 ]] && echo "> Each timing is the average of ${RUNS} runs."
echo

# shellcheck disable=SC2059
printf "${fmt_header}\n" \
    "Tag" "Cold(ms)" "Warm(ms)" "Incr(ms)" "Layers" "Size(MiB)" "RAM(MiB)" "Score"
echo "$sep"

if [[ "$OUTPUT_CSV" -eq 1 ]]; then
    printf 'tag,cold_ms,warm_ms,incr_ms,layers,size_mib,ram_mib,score\n' > benchmark.csv
fi

# ── Main loop ─────────────────────────────────────────────────────────────────
for file in "${DOCKERFILES[@]}"; do
    tag=$(get_tag "$file")
    label="${tag#${BASE_NAME}:}"
    info "Processing $file → $tag"

    # ── Cold build (no cache) ────────────────────────────────────────────────
    info "  cold build…"
    "$CLI" rmi "$tag" >/dev/null 2>&1 || true
    cold_ms=$(run_builds "--no-cache" "$tag" "$file")

    # ── Warm build (full cache hit) ──────────────────────────────────────────
    info "  warm build…"
    warm_ms=$(run_builds "" "$tag" "$file")

    # ── Incremental build (partial cache miss: one new .java file) ───────────
    info "  incremental build…"
    inject_fake_class
    incr_ms=$(run_builds "" "$tag" "$file")
    cleanup_fake

    # ── Image metadata ───────────────────────────────────────────────────────
    layers=$(get_layer_count "$tag")

    # docker images --format: Docker emits "1.23GB" (no space); Podman emits
    # "1.23 GiB" (with space + IEC suffix). normalise_size handles both.
    size_raw=$("$CLI" images --format "{{.Size}}" "$tag" 2>/dev/null || echo "0 B")
    size_mib=$(to_mib "$(normalise_size "$size_raw")")

    # ── Runtime RAM peak ─────────────────────────────────────────────────────
    info "  runtime RAM…"
    cid=$("$CLI" run -d "$tag" 2>/dev/null) || cid=""
    if [[ -n "$cid" ]]; then
        ram_mib=$(get_ram_peak "$cid")
        "$CLI" rm -f "$cid" >/dev/null 2>&1 || true
    else
        ram_mib="0.00"
        FAILED_BUILDS+=("${tag} [run]")
    fi

    # ── Composite score (lower = better) ─────────────────────────────────────
    # Weights: build responsiveness 30% cold + 30% incr, image size 30%, RAM 10%
    score=$(awk "BEGIN {
        printf \"%.2f\",
            ($cold_ms / 1000) * 0.3 +
            ($incr_ms / 1000) * 0.3 +
            $size_mib         * 0.3 +
            $ram_mib          * 0.1
    }")

    # ── Print row ────────────────────────────────────────────────────────────
    # shellcheck disable=SC2059
    printf "${fmt_row}\n" \
        "$label" "$cold_ms" "$warm_ms" "$incr_ms" \
        "$layers" "$size_mib" "$ram_mib" "$score"

    if [[ "$OUTPUT_CSV" -eq 1 ]]; then
        printf '%s,%d,%d,%d,%d,%.1f,%.2f,%.2f\n' \
            "$label" "$cold_ms" "$warm_ms" "$incr_ms" \
            "$layers" "$size_mib" "$ram_mib" "$score" \
            >> benchmark.csv
    fi
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo
if [[ ${#FAILED_BUILDS[@]} -gt 0 ]]; then
    echo "> **Warning:** the following builds/runs failed and were recorded as 0:"
    for entry in "${FAILED_BUILDS[@]}"; do
        echo ">  - \`$entry\`"
    done
    echo
fi

if [[ "$OUTPUT_CSV" -eq 1 ]]; then
    echo "> CSV written to \`benchmark.csv\`."
fi

echo "> Score formula: \`(cold_ms/1000)×0.3 + (incr_ms/1000)×0.3 + size_MiB×0.3 + ram_MiB×0.1\` — lower is better."
echo
echo "✔ Benchmark complete."