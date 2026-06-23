# Java Hello World — Docker Samples

A pedagogical repository demonstrating advanced strategies to containerize Java applications, evolving from legacy JVM builds to hyper-optimized native binaries. This project is designed for Master's-level students to explore the intersection of Java, containerization, and modern security practices.

## The Benchmark Application (`App.java`)

The included Java application simulates a microservice workload to allow for comparative performance analysis:

1. **Memory Allocation**: Generates a synthetic dataset of strings based on `APP_ITERATIONS`.
2. **CPU Processing**: Executes a filter operation to measure processing latency.
3. **Resilience**: Pauses for `APP_SLEEP_MS` to allow resource monitoring (e.g., `docker stats`) before termination.
4. **Observability**: Logs JVM vendor, version, and execution metrics to compare runtime environments.

## Dockerfile Progression

The repository follows a clear architectural evolution:

| Dockerfile | Strategy | Purpose |
| --- | --- | --- |
| `10.maven` | Baseline | Single-stage Maven build for development/debugging. |
| `20.stage` | Multi-stage | Separates build dependencies from runtime to reduce image size. |
| `30.cache` | BuildKit | Uses persistent BuildKit cache mounts to accelerate CI/CD cycles. |
| `40.manual` | Manual Toolchain | Provisioning environments using SDKMAN for strict control. |
| `50.jlink` | JLink Modulith | Slices a custom, minimal JRE to remove unnecessary JDK modules. |
| `51.jlink-alpine` | Alpine Modulith | Deploys the JLink slice on an `alpine:3.20` base for minimal footprint. |
| `60.graalvm` | Dynamic Native | AOT-compiled native binary running on `Distroless`. |
| `61.graalvm-static` | Static Native | Fully static `musl` binary on `Distroless Static` (zero OS dependencies). |

## Build & Run

To build and execute the entire series sequentially, use the provided helper script:

```bash
./build_and_run_all.sh

```

## Maven Profiles

The project uses custom profiles to adapt the build lifecycle for each strategy:

* `-Pjvm`: Configures `maven-jar-plugin` for thin JARs and `maven-dependency-plugin` for runtime libraries.
* `-Pjlink`: Triggers `maven-jlink-plugin` to generate a custom modular runtime image.
* `-Pnative`: Configures `native-maven-plugin` for GraalVM AOT compilation.
* `-Pnative-static`: Forces `musl` libc compilation for fully static native binaries.

---

*Maintained by Emmanuel Bruno, University of Toulon.*