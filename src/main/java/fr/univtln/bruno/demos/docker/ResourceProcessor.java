package fr.univtln.bruno.demos.docker;

import java.util.List;
import java.util.UUID;
import java.util.stream.IntStream;

/**
 * Handles the resource-intensive tasks of the application.
 */
class ResourceProcessor {

    /**
     * Allocates memory by generating a list of UUID strings.
     * * @param count Number of elements to generate.
     * 
     * @return A list of UUID strings.
     */
    public List<String> generateData(int count) {
        return IntStream.range(0, count)
                .mapToObj(i -> UUID.randomUUID().toString())
                .toList();
    }

    /**
     * Simulates CPU activity by filtering a list.
     * * @param data The list of strings to process.
     * 
     * @return The count of elements containing the character 'a'.
     */
    public long processData(List<String> data) {
        if (data == null)
            return 0;
        return data.parallelStream()
                .filter(s -> s.contains("a"))
                .count();
    }
}
