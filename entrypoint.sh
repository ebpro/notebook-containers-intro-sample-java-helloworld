#!/bin/sh
set -e
# Generic entrypoint: detect and run the appropriate artifact
# Priority: /app/app.jar -> any executable in /jre/bin -> /app/app (native) -> first jar in /app or /app/target
# Usage: entrypoint.sh [app-args]

if [ -f /app/app.jar ]; then
	exec java ${JAVA_OPTS} -jar /app/app.jar "$@"
fi

# If jlink produced a custom runtime, the launcher name varies.
# Look for the first executable file under /jre/bin and run it.
if [ -d /jre/bin ]; then
	for f in /jre/bin/*; do
		if [ -x "$f" ] && [ ! -d "$f" ]; then
			exec "$f" "$@"
		fi
	done
fi

if [ -x /app/app ]; then
	exec /app/app "$@"
fi

jar=$(ls /app/*.jar 2>/dev/null | head -n 1)
if [ -z "$jar" ]; then
	jar=$(ls /app/target/*.jar 2>/dev/null | head -n 1)
fi
if [ -n "$jar" ]; then
	exec java ${JAVA_OPTS} -jar "$jar" "$@"
fi

echo "No runnable artifact found in /app or /jre" >&2
exit 1
