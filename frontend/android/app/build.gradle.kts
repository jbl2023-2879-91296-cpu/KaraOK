import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingProperties = Properties()
val signingPropertiesFile = rootProject.file("key.properties")
if (signingPropertiesFile.isFile) {
    signingPropertiesFile.inputStream().use(signingProperties::load)
}

fun signingValue(environmentName: String, propertyName: String): String? =
    System.getenv(environmentName)?.takeIf { it.isNotBlank() }
        ?: signingProperties.getProperty(propertyName)?.takeIf { it.isNotBlank() }

val releaseStoreFilePath = signingValue("KARAOK_KEYSTORE_PATH", "storeFile")
val releaseStorePassword = signingValue("KARAOK_STORE_PASSWORD", "storePassword")
val releaseKeyAlias = signingValue("KARAOK_KEY_ALIAS", "keyAlias")
val releaseKeyPassword = signingValue("KARAOK_KEY_PASSWORD", "keyPassword")
val releaseSigningConfigured =
    releaseStoreFilePath != null &&
        releaseStorePassword != null &&
        releaseKeyAlias != null &&
        releaseKeyPassword != null &&
        file(releaseStoreFilePath).isFile
val releaseTaskRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}

if (releaseTaskRequested && !releaseSigningConfigured) {
    throw GradleException(
        "KaraOK release signing is not configured. " +
            "Run tools/build_karaok.ps1 -SetupSigning or provide the KARAOK signing environment variables.",
    )
}

android {
    namespace = "com.jrpbone.karaok"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.jrpbone.karaok"
        System.getenv("KARAOK_APPLICATION_ID")?.takeIf { it.isNotBlank() }?.let {
            applicationId = it
        }
        manifestPlaceholders["karaokApplicationLabel"] =
            System.getenv("KARAOK_APPLICATION_NAME")?.takeIf { it.isNotBlank() } ?: "KaraOK"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // image_picker 1.2.x supports Android API 24 and newer.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningConfigured) {
            create("release") {
                storeFile = file(releaseStoreFilePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            if (releaseSigningConfigured) {
                signingConfig = signingConfigs.getByName("release")
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
