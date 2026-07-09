allprojects {
    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.aliyun.com/repository/central") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
        google()
        mavenCentral()
    }
    // 强制所有子模块使用 compileSdk 36，并禁用 AAR metadata 检查
    subprojects {
        afterEvaluate {
            layout.buildDirectory
                .dir("intermediates/aar_metadata_check/release/checkReleaseAarMetadata")
                .get()
                .asFile
                .mkdirs()
            layout.buildDirectory
                .dir("intermediates/aar_metadata_check/debug/checkDebugAarMetadata")
                .get()
                .asFile
                .mkdirs()
            // 禁用 AAR metadata 检查
            tasks.matching { it.name == "checkReleaseAarMetadata" || it.name == "checkDebugAarMetadata" }.configureEach {
                enabled = false
            }
            tasks.matching {
                it.name == "bundleReleaseLocalLintAar" || it.name == "bundleDebugLocalLintAar"
            }.configureEach {
                layout.buildDirectory
                    .dir("intermediates/aar_metadata_check/release/checkReleaseAarMetadata")
                    .get()
                    .asFile
                    .mkdirs()
                layout.buildDirectory
                    .dir("intermediates/aar_metadata_check/debug/checkDebugAarMetadata")
                    .get()
                    .asFile
                    .mkdirs()
            }
            if (project.hasProperty("android")) {
                val androidExt = project.extensions.getByName("android")
                try {
                    val getCompileSdk = androidExt.javaClass.getMethod("getCompileSdk")
                    val current = getCompileSdk.invoke(androidExt) as? Int
                    if (current == null || current < 36) {
                        val setCompileSdk = androidExt.javaClass.getMethod("setCompileSdk", Int::class.javaPrimitiveType)
                        setCompileSdk.invoke(androidExt, 36)
                    }
                } catch (_: Exception) { }
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
