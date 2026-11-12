# rustls-platform-verifier: called only from the Rust core over JNI, invisible to R8.
-keep, includedescriptorclasses class org.rustls.platformverifier.** { *; }
