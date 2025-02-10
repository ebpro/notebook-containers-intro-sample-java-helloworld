module fr.univtln.bruno.demos.docker {
    // Required modules
    requires java.base;
    requires org.slf4j;
    requires ch.qos.logback.classic;
    requires ch.qos.logback.core;
    requires java.logging;
    
    // Exports
    exports fr.univtln.bruno.demos.docker;
    
    // Opens for logging configuration
    opens fr.univtln.bruno.demos.docker to ch.qos.logback.classic, ch.qos.logback.core;
}