allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Force 16 KB-aligned CameraX native libs (libimage_processing_util_jni.so).
subprojects {
    configurations.configureEach {
        resolutionStrategy {
            val cameraX = "1.4.2"
            force(
                "androidx.camera:camera-core:$cameraX",
                "androidx.camera:camera-camera2:$cameraX",
                "androidx.camera:camera-lifecycle:$cameraX",
                "androidx.camera:camera-video:$cameraX",
            )
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
