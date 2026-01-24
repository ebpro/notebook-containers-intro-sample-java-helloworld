package fr.univtln.bruno.demos.docker;

import org.junit.jupiter.api.Test;
import java.util.List;
import static org.junit.jupiter.api.Assertions.assertEquals;

/**
 * Unit tests for ResourceProcessor to ensure logic remains correct
 * across refactors.
 */
class ResourceProcessorTest {
    private final ResourceProcessor processor = new ResourceProcessor();

    @Test
    void testProcessData() {
        List<String> mockData = List.of("apple", "berry", "cherry");
        // "apple" and "berry" contain 'a' (in some locales/logic) or just 'apple' here
        // Based on the code s.contains("a"): apple=yes, berry=no, cherry=no
        long result = processor.processData(mockData);
        assertEquals(1, result, "Should find exactly 1 string containing 'a'");
    }

    @Test
    void testGenerateDataSize() {
        assertEquals(10, processor.generateData(10).size());
    }
}
