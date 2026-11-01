import org.gradle.api.file.Directory

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

subprojects {
    afterEvaluate {
        if (project.hasProperty("android")) {
            val androidExt = project.extensions.findByName("android")
            if (androidExt != null) {
                try {
                    val compileSdkVersion = androidExt.javaClass.getMethod("getCompileSdkVersion").invoke(androidExt)
                    if (compileSdkVersion != "android-36" && compileSdkVersion != 36) {
                        androidExt.javaClass.getMethod("compileSdkVersion", Int::class.javaPrimitiveType).invoke(androidExt, 36)
                    }
                } catch (e: Exception) {
                    try {
                        val setCompileSdk = androidExt.javaClass.getMethod("setCompileSdk", java.lang.Integer::class.java)
                        setCompileSdk.invoke(androidExt, 36)
                    } catch (_: Exception) {}
                }
            }
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
