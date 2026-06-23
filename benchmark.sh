#!/bin/bash

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------
BASE_NAME="javahello"
PACKAGE_PATH="src/main/java/fr/univtln/bruno/demos/docker"

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

echo -e "\n🚀 Benchmark : Analyse de l'Efficience (Build vs Runtime)\n"
echo "| Image Tag | Build Cold | Build Warm | Build Incr. | Size | Peak RAM | Footprint Index |"
echo "|:----------|:-----------|:-----------|:------------|:-----|:---------|:----------------|"

for KEY in "${ORDER[@]}"; do
    TAG=${BUILDS[$KEY]}
    DOCKERFILE="Dockerfile.$KEY"
    FULL_TAG="$BASE_NAME:$TAG"

    [ ! -f "$DOCKERFILE" ] && continue

    # --------------------------------------------------------
    # 1. COLD BUILD (no cache)
    # --------------------------------------------------------
    B_START=$(date +%s)
    docker build --no-cache -t "$FULL_TAG" -f "$DOCKERFILE" . > /dev/null 2>&1
    COLD_TIME="$(( $(date +%s) - B_START ))s"

    # --------------------------------------------------------
    # 2. WARM BUILD (full cache)
    # --------------------------------------------------------
    B_START=$(date +%s)
    docker build -t "$FULL_TAG" -f "$DOCKERFILE" . > /dev/null 2>&1
    WARM_TIME="$(( $(date +%s) - B_START ))s"

    # --------------------------------------------------------
    # 3. INCREMENTAL BUILD (ServiceLoader – GraalVM aware)
    # --------------------------------------------------------
    FAKE_CLASS="Fake$(date +%s)"
    FAKE_JAVA="$PACKAGE_PATH/$FAKE_CLASS.java"

    SPI_DIR="src/main/resources/META-INF/services"
    SPI_FILE="$SPI_DIR/fr.univtln.bruno.demos.docker.Marker"

    mkdir -p "$SPI_DIR"

    # Fake provider implémentant Marker
    cat > "$FAKE_JAVA" <<EOF
package fr.univtln.bruno.demos.docker;

public class $FAKE_CLASS implements Marker {
    @Override
    public void touch() {
        // noop
    }
}
EOF

    # Enregistrement SPI (force l'atteignabilité GraalVM)
    echo "fr.univtln.bruno.demos.docker.$FAKE_CLASS" > "$SPI_FILE"

    B_START=$(date +%s)
    docker build -t "$FULL_TAG" -f "$DOCKERFILE" . > /dev/null 2>&1
    INCR_TIME="$(( $(date +%s) - B_START ))s"

    # Nettoyage (aucune trace persistante)
    rm -f "$FAKE_JAVA" "$SPI_FILE"
    rmdir "$SPI_DIR" 2>/dev/null
    rmdir "src/main/resources/META-INF" 2>/dev/null
    rmdir "src/main/resources" 2>/dev/null

    # --------------------------------------------------------
    # 4. RUNTIME STATS (Peak RAM)
    # --------------------------------------------------------
    SIZE_STR=$(docker images --format "{{.Size}}" "$FULL_TAG")
    CID=$(docker run -d "$FULL_TAG")
    PEAK_MEM_RAW=0

    while [ "$(docker ps -q -f id=$CID)" ]; do
        M_STR=$(docker stats --no-stream --format "{{.MemUsage}}" "$CID" | awk '{print $1}')
        VAL=$(echo "$M_STR" | sed 's/[A-Za-z]//g')

        if [[ -n "$VAL" ]] && (( $(echo "$VAL > $PEAK_MEM_RAW" | bc -l 2>/dev/null || echo 0) )); then
            PEAK_MEM_RAW=$VAL
        fi
        sleep 0.05
    done

    docker rm -f "$CID" > /dev/null 2>&1

    # --------------------------------------------------------
    # 5. FOOTPRINT INDEX
    # --------------------------------------------------------
    SIZE_NUM=$(echo "$SIZE_STR" | sed 's/[A-Za-z]//g')
    SCORE=$(echo "($PEAK_MEM_RAW * 3) + ($SIZE_NUM / 10)" | bc -l)

    printf "| %-15s | %10s | %10s | %11s | %8s | %8.2f MiB | %15.1f |\n" \
        "$TAG" "$COLD_TIME" "$WARM_TIME" "$INCR_TIME" \
        "$SIZE_STR" "$PEAK_MEM_RAW" "$SCORE"
done

echo -e "\n*Note : Footprint Index = (RAM × 3) + (Size / 10). Plus l'indice est faible, plus l'image est efficiente.*"
