module fr.univtln.bruno.demos.docker {

    // Required modules (used directly in the code)
    requires org.slf4j;

    // Declare SPI usage so ServiceLoader works when running on the module path
    uses fr.univtln.bruno.demos.docker.Marker;

    // Public API of the module
    exports fr.univtln.bruno.demos.docker;
}
