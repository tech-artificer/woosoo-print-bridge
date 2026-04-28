allprojects {
    repositories {
        google()
        mavenCentral()
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

subprojects {
    if (name == "blue_thermal_printer") {
        pluginManager.withPlugin("com.android.library") {
            val androidExt = extensions.findByName("android")

            if (androidExt != null) {
                runCatching {
                    val currentNamespace = androidExt.javaClass
                        .methods
                        .firstOrNull { it.name == "getNamespace" && it.parameterCount == 0 }
                        ?.invoke(androidExt) as? String

                    if (currentNamespace.isNullOrBlank()) {
                        androidExt.javaClass
                            .getMethod("setNamespace", String::class.java)
                            .invoke(androidExt, "id.kakzaki.blue_thermal_printer")
                    }
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
