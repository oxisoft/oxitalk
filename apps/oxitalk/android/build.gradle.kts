allprojects {
    repositories {
        google()
        mavenCentral()
        // The Kotlin half of rustls-platform-verifier (the core's TLS uses Android's trust
        // manager through it); published only there, versioned with its Rust crate.
        maven {
            url = uri(
                "https://raw.githubusercontent.com/rustls/rustls-platform-verifier/maven-archive/android-release-support/maven/",
            )
            content { includeGroup("org.rustls") }
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
