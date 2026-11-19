allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Keep plugin build scripts on the same toolchain as settings.gradle.kts.
// Several plugins otherwise resolve old, redundant compiler distributions.
subprojects {
    buildscript.configurations.configureEach {
        if (name == "classpath") {
            resolutionStrategy.force(
                "com.android.tools.build:gradle:8.11.1",
                "org.jetbrains.kotlin:kotlin-gradle-plugin:2.2.20",
            )
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
