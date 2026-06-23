# Java Hello World — Docker Samples

Lightweight repository demonstrating multiple strategies to package a Java application as a container image (single-stage Maven, multi-stage, cache-optimized, jlink and GraalVM native).

## Contents

- Dockerfiles: `Dockerfile.01.mavenimage`, `Dockerfile.02.mavenimagestage`, `Dockerfile.03.dockercache`, `Dockerfile.05.manual`, `Dockerfile.06.jlink`, `Dockerfile.06b.jlink-alpine`, `Dockerfile.07.graalVM`
- Helper scripts: `entrypoint.sh`, `build_and_run_all.sh`, `benchmark.sh`
- Maven project with profiles: `prod`, `jlink`, `native`

## Prerequisites

- Docker or Podman available on PATH (rootless or rootful)
- Java / Maven (only needed for local builds outside Docker)

## Quick start

Build and run all images sequentially (script uses `docker`):

```bash
./build_and_run_all.sh
```

Build a single image manually:

```bash
# build and run JVM multi-stage image
docker build -t javahello:mavenimagestage -f Dockerfile.02.stage .
docker run --rm javahello:mavenimagestage

# build jlink image
docker build -t javahello:jlink -f Dockerfile.06.jlink .
docker run --rm javahello:jlink
```

If you use Podman, replace `docker` by `podman` in the commands above.

## Benchmark

Run the included benchmark that measures build/runtime characteristics:

```bash
./benchmark.sh
```

## License
MIT
