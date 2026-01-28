#!/bin/sh
set -e

# 1. Priorité : JAR Standard (Profil -Pprod)
if [ -f /app/app.jar ]; then
    exec java ${JAVA_OPTS:-} -jar /app/app.jar "$@"
fi

# 2. Priorité : JLink (Profil -Pjlink)
# On cherche spécifiquement le launcher 'hello' défini dans le POM
if [ -x /jre/bin/hello ]; then
    exec /jre/bin/hello "$@"
fi

# 3. Priorité : GraalVM Native (Profil -Pnative)
# On utilise le nom défini dans <imageName> du POM
if [ -x /app/app ]; then
    exec /app/app "$@"
fi

# 4. Fallback (Sécurité pour Dockerfile.01)
jar=$(ls /app/*.jar /app/target/*.jar 2>/dev/null | head -n 1)
if [ -n "$jar" ]; then
    exec java ${JAVA_OPTS:-} -jar "$jar" "$@"
fi

echo "❌ Erreur : Aucun artefact exécutable (JAR, jlink 'hello' ou natif) trouvé." >&2
exit 1
