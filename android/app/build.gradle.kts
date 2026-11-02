import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Credenciales locales privadas. android/key.properties siempre se excluye de Git.
val uploadProperties = Properties()
val uploadPropertiesPath = rootProject.file("key.properties")
if (uploadPropertiesPath.isFile) {
    FileInputStream(uploadPropertiesPath).use { uploadProperties.load(it) }
}
val uploadSigningReady = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    .all { !uploadProperties.getProperty(it).isNullOrBlank() }
val releaseBuildRequested = gradle.startParameter.taskNames.any {
    it.contains("Release", ignoreCase = true) || it.contains("bundle", ignoreCase = true)
}
if (releaseBuildRequested && !uploadSigningReady) {
    throw GradleException("TUKTUK Cliente: falta android/key.properties para firmar el build release. Nunca usar firma debug.")
}

android {
    namespace = "com.vrixora.tuktukcliente"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Identidad definitiva TUKTUK Cliente. No cambiar tras registrar en Google Play.
        applicationId = "com.vrixora.tuktukcliente"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (uploadSigningReady) {
                keyAlias = uploadProperties.getProperty("keyAlias")
                keyPassword = uploadProperties.getProperty("keyPassword")
                storeFile = file(uploadProperties.getProperty("storeFile"))
                storePassword = uploadProperties.getProperty("storePassword")
            }
        }
    }
    buildTypes {
        release {
            // Sin fallback: Play exige firma de carga privada, NUNCA debug.
            signingConfig = signingConfigs.getByName("release")
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
