#!/bin/bash

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------
BASE_NAME="javahello"
PACKAGE_PATH="src/main/java/fr/univtln/bruno/demos/docker"
N_RUNS=3  # nombre de répétitions pour moyenne/écart-type

declare -A BUILDS=(
    ["01.mavenimage"]="mavenimage"
    ["02.mavenimagestage"]="mavenimagestage"
    ["03.dockercache"]="dockercache"
    ["05.manual"]="manual"
    ["06.jlink"]="jlink"
    ["06b.jlink-alpine"]="jlink-alpine"
    ["07.graalVM"]="graalvm"
)

ORDER=(
    "01.mavenimage"
    "02.mavenimagestage"
    "03.dockercache"
    "05.manual"
    "06.jlink"
    "06b.jlink-alpine"
    "07.graalVM"
)

echo "Benchmark scientifique : moyenne + écart-type sur $N_RUNS runs"
echo -e "\n| Image Tag | Cold Build | Warm Build | Incr Build | Size | Peak RAM |"
echo "|:----------|:-----------|:-----------|:------------|:-----|:---------|"

# Fonction pour calculer moyenne et écart-type
calc_stats() {
    local values=("$@")
    local sum=0
    local sumsq=0
    local n=${#values[@]}

    for v in "${values[@]}"; do
        sum=$(echo "$sum + $v" | bc -l)
        sumsq=$(echo "$sumsq + ($v)^2" | bc -l)
    done
    local mean=$(echo "$sum / $n" | bc -l)
    local stddev=$(echo "sqrt(($sumsq / $n) - ($mean)^2)" | bc -l)
    echo "$mean $stddev"
}

# Fonction pour récupérer peak RAM
get_peak_ram() {
    local CID=$1
    local PEAK_MEM_RAW=0

    # 1️⃣ Recherche du scope du conteneur (Podman ou Docker)
    CGROUP_PATH=$(find /sys/fs/cgroup -type d -name "*$CID*" 2>/dev/null | head -n1)

    if [ -n "$CGROUP_PATH" ]; then
        # cgroup v2 : lire memory.peak
        if [ -f "$CGROUP_PATH/memory.peak" ]; then
            PEAK_MEM_RAW=$(cat "$CGROUP_PATH/memory.peak")
        else
            PEAK_MEM_RAW=0
        fi
    else
        # fallback : docker/podman stats
        M_STR=$(docker stats --no-stream --format "{{.MemUsage}}" "$CID" 2>/dev/null || podman stats --no-stream --format "{{.MemUsage}}" "$CID" 2>/dev/null)
        VAL=$(echo "$M_STR" | sed 's/[^0-9.]//g')
        UNIT=$(echo "$M_STR" | sed 's/[0-9.]//g')
        case "$UNIT" in
            GiB) VAL=$(echo "$VAL*1024" | bc -l) ;;
            KiB) VAL=$(echo "$VAL/1024" | bc -l) ;;
        esac
        PEAK_MEM_RAW=$VAL
    fi

    # Convertir en MB
    echo "$(echo "$PEAK_MEM_RAW/1024/1024" | bc -l)"
}


# ------------------------------------------------------------
# Boucle sur les builds
# ------------------------------------------------------------
for KEY in "${ORDER[@]}"; do
    TAG=${BUILDS[$KEY]}
    DOCKERFILE="Dockerfile.$KEY"
    FULL_TAG="$BASE_NAME:$TAG"

    [ ! -f "$DOCKERFILE" ] && continue

    cold_times=()
    warm_times=()
    incr_times=()
    peak_rams=()

    SIZE_STR=$(docker image inspect "$FULL_TAG" --format '{{.Size}}' 2>/dev/null | awk '{printf "%.1fMB", $1/1024/1024}')

    for ((run=1; run<=N_RUNS; run++)); do
        # -------------------- Cold Build --------------------
        B_START=$(date +%s)
        docker build --no-cache -t "$FULL_TAG" -f "$DOCKERFILE" . > /dev/null 2>&1
        cold_times+=($(( $(date +%s) - B_START )))

        # -------------------- Warm Build --------------------
        B_START=$(date +%s)
        docker build -t "$FULL_TAG" -f "$DOCKERFILE" . > /dev/null 2>&1
        warm_times+=($(( $(date +%s) - B_START )))

        # -------------------- Incremental Build --------------------
        FAKE_CLASS="Fake$(date +%s%N)"
        FAKE_JAVA="$PACKAGE_PATH/$FAKE_CLASS.java"
        SPI_DIR="src/main/resources/META-INF/services"
        SPI_FILE="$SPI_DIR/fr.univtln.bruno.demos.docker.Marker"
        mkdir -p "$SPI_DIR"

        cat > "$FAKE_JAVA" <<EOF
package fr.univtln.bruno.demos.docker;

public class $FAKE_CLASS implements Marker {
    @Override
    public void touch() {}
}
EOF
        echo "fr.univtln.bruno.demos.docker.$FAKE_CLASS" > "$SPI_FILE"

        B_START=$(date +%s)
        docker build -t "$FULL_TAG" -f "$DOCKERFILE" . > /dev/null 2>&1
        incr_times+=($(( $(date +%s) - B_START )))

        rm -f "$FAKE_JAVA" "$SPI_FILE"

        # -------------------- Peak RAM --------------------
        CID=$(docker run -d "$FULL_TAG")
        docker wait "$CID" >/dev/null 2>&1
        ram=$(get_peak_ram "$CID")
        peak_rams+=($ram)
        docker rm -f "$CID" >/dev/null 2>&1
    done

    # Moyenne + écart-type
    read cold_mean cold_std <<< $(calc_stats "${cold_times[@]}")
    read warm_mean warm_std <<< $(calc_stats "${warm_times[@]}")
    read incr_mean incr_std <<< $(calc_stats "${incr_times[@]}")
    read ram_mean ram_std <<< $(calc_stats "${peak_rams[@]}")

    printf "| %-15s | %4.1fs ±%4.1f | %4.1fs ±%4.1f | %4.1fs ±%4.1f | %8s | %6.1f ±%4.1f MB |\n" \
        "$TAG" "$cold_mean" "$cold_std" "$warm_mean" "$warm_std" "$incr_mean" "$incr_std" "$SIZE_STR" "$ram_mean" "$ram_std"
done

echo -e "\n*Footprint Index = (RAM × 3) + (Size / 10). Moyenne sur $N_RUNS runs.*"
