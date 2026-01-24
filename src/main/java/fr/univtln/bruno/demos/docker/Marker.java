package fr.univtln.bruno.demos.docker;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Marker SPI interface for ServiceLoader / GraalVM demonstrations.
 *
 * <p>
 * Implementations of this interface can be discovered at runtime using
 * {@link java.util.ServiceLoader}. Each discovered service may be invoked
 * to demonstrate dynamic reachability under GraalVM native-image.
 * </p>
 *
 * <p>
 * This interface is intentionally minimal and side-effect free.
 * </p>
 *
 * @author Emmanuel Bruno
 * @version 0.1.0
 */
public interface Marker {

    Logger LOGGER = LoggerFactory.getLogger(Marker.class);

    /**
     * Invoked when the service is loaded.
     * Default implementation logs the concrete service class.
     */
    default void touch() {
        LOGGER.info("Marker service invoked: {}", getClass().getName());
    }
}
