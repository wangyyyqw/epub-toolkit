import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.epubgadget.epub_gadget"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    val keystoreProperties = Properties()
    val keystorePropertiesFile = rootProject.file("key.properties")
    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(FileInputStream(keystorePropertiesFile))
    }

    fun signingValue(propertyName: String, envName: String): String? {
        return (keystoreProperties[propertyName] as String?)
            ?: System.getenv(envName)
    }

    val releaseStoreFile = signingValue("storeFile", "ANDROID_KEYSTORE_FILE")
    val releaseStorePassword = signingValue("storePassword", "ANDROID_KEYSTORE_PASSWORD")
    val releaseKeyAlias = signingValue("keyAlias", "ANDROID_KEY_ALIAS")
    val releaseKeyPassword = signingValue("keyPassword", "ANDROID_KEY_PASSWORD")
    val hasReleaseSigning = listOf(
        releaseStoreFile,
        releaseStorePassword,
        releaseKeyAlias,
        releaseKeyPassword,
    ).all { !it.isNullOrBlank() }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
                storeFile = rootProject.file(releaseStoreFile!!)
                storePassword = releaseStorePassword
            }
        }
    }

    defaultConfig {
        applicationId = "com.epubgadget.epub_gadget"
        minSdk = 24
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// 强制所有依赖的 Android 子模块使用 compileSdk 36
subprojects {
    afterEvaluate {
        if (project.hasProperty("android")) {
            val androidExt = project.extensions.getByName("android")
            try {
                val setField = androidExt.javaClass.getMethod("setCompileSdkVersion", Int::class.javaPrimitiveType)
                setField.invoke(androidExt, 36)
            } catch (e: Exception) {
                try {
                    val setProperty = androidExt.javaClass.getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                    setProperty.invoke(androidExt, 36)
                } catch (_: Exception) { }
            }
        }
    }
}
