#!/bin/bash
set -euo pipefail

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------
BASE_NAME="javahello"
PACKAGE_PATH="src/main/java/fr/univtln/bruno/demos/docker"

echo -e "\n🚀 Benchmark: Build vs Runtime Efficiency\n"

echo "| Image | Cold | Warm | Incremental | Size | Peak RAM | Score |"
echo "|------|------|------|-------------|------|----------|-------|"

# ------------------------------------------------------------
# Helper: SAME naming logic as build/run scripts
# ------------------------------------------------------------
get_tag() {
  local file="$1"
  local suffix="${file#Dockerfile.}"
  suffix="${suffix//./-}"
  echo "${BASE_NAME}:${suffix}"
}

# ------------------------------------------------------------
# Discover Dockerfiles automatically
# ------------------------------------------------------------
mapfile -t DOCKERFILES < <(ls Dockerfile.* 2>/dev/null | sort -V)

for file in "${DOCKERFILES[@]}"; do

    TAG=$(get_tag "$file")

    echo "▶ Benchmarking $TAG"

    # ========================================================
    # 1. COLD BUILD
    # ========================================================
    COLD_START=$(date +%s)
    docker build --no-cache -t "$TAG" -f "$file" . > /dev/null
    COLD_TIME=$(( $(date +%s) - COLD_START ))

    # ========================================================
    # 2. WARM BUILD
    # ========================================================
    WARM_START=$(date +%s)
    docker build -t "$TAG" -f "$file" . > /dev/null
    WARM_TIME=$(( $(date +%s) - WARM_START ))

    # ========================================================
    # 3. INCREMENTAL BUILD (isolated workspace)
    # ========================================================
    TMP_DIR=$(mktemp -d)
    FAKE_CLASS="Fake$(date +%s%N)"

    mkdir -p "$TMP_DIR/src/main/java/fr/univtln/bruno/demos/docker"
    mkdir -p "$TMP_DIR/src/main/resources/META-INF/services"

    cat > "$TMP_DIR/src/main/java/fr/univtln/bruno/demos/docker/$FAKE_CLASS.java" <<EOF
package fr.univtln.bruno.demos.docker;

public class $FAKE_CLASS implements Marker {
    public void touch() {}
}
EOF

    echo "fr.univtln.bruno.demos.docker.$FAKE_CLASS" \
        > "$TMP_DIR/src/main/resources/META-INF/services/fr.univtln.bruno.demos.docker.Marker"

    INCR_START=$(date +%s)

    docker build \
      --no-cache \
      -t "$TAG" \
      -f "$file" \
      "$TMP_DIR" > /dev/null

    INCR_TIME=$(( $(date +%s) - INCR_START ))

    rm -rf "$TMP_DIR"

    # ========================================================
    # 4. RUNTIME METRICS
    # ========================================================
    SIZE_STR=$(docker images --format "{{.Size}}" "$TAG")

    CID=$(docker run -d "$TAG" >/dev/null)

    PEAK=0

    while docker ps -q -f id="$CID" | grep -q .; do
        MEM=$(docker stats --no-stream --format "{{.MemUsage}}" "$CID" | awk '{print $1}')
        NUM=$(echo "$MEM" | sed 's/[^0-9.]//g')

        if [[ -n "$NUM" ]]; then
            PEAK=$(echo "$PEAK $NUM" | awk '{if ($2>$1) print $2; else print $1}')
        fi

        sleep 0.05
    done

    docker rm -f "$CID" > /dev/null 2>&1 || true

    SIZE_NUM=$(echo "$SIZE_STR" | sed 's/[^0-9.]//g')

    SCORE=$(echo "$PEAK * 3 + $SIZE_NUM / 10" | bc -l)

    # ========================================================
    # 5. OUTPUT
    # ========================================================
    printf "| %-25s | %4ss | %4ss | %11ss | %6s | %7.2f MiB | %6.1f |\n" \
        "$TAG" "$COLD_TIME" "$WARM_TIME" "$INCR_TIME" \
        "$SIZE_STR" "$PEAK" "$SCORE"

done

echo -e "\n✔ Done. Lower score = better efficiency."