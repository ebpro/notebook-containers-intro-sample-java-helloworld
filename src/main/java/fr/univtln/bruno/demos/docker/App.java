package fr.univtln.bruno.demos.docker;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.ServiceLoader;

/**
 * Sample Java application to demonstrate resource usage in a containerized
 * environment.
 * Refactored for observability, resilience, and testability.
 *
 * @author Emmanuel Bruno
 * @version 0.2.0
 */
public class App {
    private static final Logger logger = LoggerFactory.getLogger(App.class);

    /**
     * Main entry point. Orchestrates resource simulation and monitoring.
     */
    public static void main(String[] args) {
        // Log environment context for better container debugging
        logger.info("Java Vendor: {} | Version: {}",
                System.getProperty("java.vendor"),
                System.getProperty("java.version"));

        // Demonstrate service loading (if any implementations are provided)
        // Enable to add reachable services via SPI
        ServiceLoader.load(Marker.class ).forEach(Marker::touch);

        // 0. Configuration with safe parsing
        int iterations = getEnvInt("APP_ITERATIONS", 10000);
        long sleepMs = getEnvLong("APP_SLEEP_MS", 1500L);

        ResourceProcessor processor = new ResourceProcessor();

        Instant start = Instant.now();
        logger.info("Démarrage de l'application (Iterations: {})...", iterations);

        // 1. Memory allocation
        List<String> data = processor.generateData(iterations);

        // 2. CPU activity
        long count = processor.processData(data);

        Duration duration = Duration.between(start, Instant.now());
        logger.info("Traitement terminé. Éléments filtrés : {} | Temps : {} ms",
                count, duration.toMillis());

        // 3. Pause to allow resource monitoring (e.g., docker stats)
        performGracefulSleep(sleepMs);

        // 4. Final output (prevents JIT from optimizing away the 'count' variable)
        System.out.printf("Fin du programme. (Éléments traités: %d)%n", count);
    }

    private static void performGracefulSleep(long ms) {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException e) {
            logger.warn("Pause interrupted.");
            Thread.currentThread().interrupt();
        }
    }

    private static int getEnvInt(String key, int def) {
        String val = System.getenv(key);
        return (val != null && val.matches("\\d+")) ? Integer.parseInt(val) : def;
    }

    private static long getEnvLong(String key, long def) {
        String val = System.getenv(key);
        return (val != null && val.matches("\\d+")) ? Long.parseLong(val) : def;
    }
}
