package fr.univtln.bruno.demos.docker;

import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.assertNotNull;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;

/**
 * Unit test for simple App.
 */
class AppTest {
    
    @Test
    @DisplayName("Application can be instantiated")
    void shouldCreateAppInstance() {
        App app = new App();
        assertNotNull(app, "App instance should not be null");
    }

    @Test
    @DisplayName("Main method should run without errors")
    void shouldRunMainWithoutErrors() {
        App.main(new String[]{});
        assertTrue(true, "Main method executed successfully");
    }
}