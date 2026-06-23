# Java Hello World — Docker Samples

Lightweight repository demonstrating multiple strategies to package a Java application as a container image (single-stage Maven, multi-stage, cache-optimized, jlink and GraalVM native).

## Contents

- **Dockerfiles**: `Dockerfile.10.maven`, `Dockerfile.30.cache`, `Dockerfile.40.manual`, `Dockerfile.50.jlink`, `Dockerfile.51.jlink-alpine`, `Dockerfile.60.graalvm`, `Dockerfile.61.graalvm-static`
- **Helper scripts**: `entrypoint.sh`, `build_and_run_all.sh`, `benchmark.sh`, `benchmark-full.sh`
- **Maven project with profiles**: `prod`, `jlink`, `native`, `native-static`

## Prerequisites

- Docker or Podman available on PATH (rootless or rootful)
- Java / Maven (only needed for local builds outside Docker)

## Quick start

Build and run all images sequentially (script uses `docker`):

```bash
./build_and_run_all.sh