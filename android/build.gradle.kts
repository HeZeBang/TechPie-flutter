allprojects {
    configurations.configureEach {
        resolutionStrategy.eachDependency {
            // The OHOS mobile_scanner fork still requests CameraX 1.3.4,
            // whose image-processing JNI library has 4 KB ELF LOAD alignment.
            if (requested.group == "androidx.camera" && requested.version == "1.3.4") {
                useVersion("1.4.2")
                because("CameraX 1.4.2 ships 16 KB aligned JNI libraries")
            }
        }
    }
    repositories {
        maven(url = "https://maven.aliyun.com/repository/google")
        maven(url = "https://maven.aliyun.com/repository/central")
        maven(url = "https://maven.aliyun.com/repository/public")
        // google()
        // mavenCentral()
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
