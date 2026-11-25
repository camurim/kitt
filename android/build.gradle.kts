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

// Alinha o compileSdk de plugins antigos (como flutter_pcm_sound em API 33)
// com o mesmo compileSdk usado pelo módulo :app.
subprojects {
    if (project.name != "app") {
        afterEvaluate {
            val appAndroid = rootProject.project(":app").extensions.findByName("android")
                as? com.android.build.gradle.BaseExtension
            val libAndroid = project.extensions.findByName("android")
                as? com.android.build.gradle.BaseExtension
            val appCompileSdk = appAndroid?.compileSdkVersion
            if (libAndroid != null && appCompileSdk != null) {
                libAndroid.compileSdkVersion(appCompileSdk)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
