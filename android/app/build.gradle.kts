import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningProperties = Properties()
val releaseSigningPropertiesFile = rootProject.file("key.properties")

if (releaseSigningPropertiesFile.isFile) {
    releaseSigningPropertiesFile.inputStream().use(releaseSigningProperties::load)
}

fun releaseSigningValue(propertyName: String, environmentName: String): String? =
    releaseSigningProperties.getProperty(propertyName)?.takeIf(String::isNotEmpty)
        ?: System.getenv(environmentName)?.takeIf(String::isNotEmpty)

val releaseStoreFilePath = releaseSigningValue(
    "storeFile",
    "TECHPIE_ANDROID_KEYSTORE_PATH",
)
val releaseStorePassword = releaseSigningValue(
    "storePassword",
    "TECHPIE_ANDROID_KEYSTORE_PASSWORD",
)
val releaseKeyAlias = releaseSigningValue(
    "keyAlias",
    "TECHPIE_ANDROID_KEY_ALIAS",
)
val releaseKeyPassword = releaseSigningValue(
    "keyPassword",
    "TECHPIE_ANDROID_KEY_PASSWORD",
)
val releaseStoreType = releaseSigningValue(
    "storeType",
    "TECHPIE_ANDROID_KEYSTORE_TYPE",
) ?: "PKCS12"
val releaseStoreFile = releaseStoreFilePath?.let { rootProject.file(it) }
val releaseTaskRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}

if (releaseTaskRequested) {
    val missingValues = buildList {
        if (releaseStoreFilePath == null) add("storeFile / TECHPIE_ANDROID_KEYSTORE_PATH")
        if (releaseStorePassword == null) {
            add("storePassword / TECHPIE_ANDROID_KEYSTORE_PASSWORD")
        }
        if (releaseKeyAlias == null) add("keyAlias / TECHPIE_ANDROID_KEY_ALIAS")
        if (releaseKeyPassword == null) {
            add("keyPassword / TECHPIE_ANDROID_KEY_PASSWORD")
        }
    }

    require(missingValues.isEmpty()) {
        "Release signing is not configured. Missing: ${missingValues.joinToString()}. " +
            "Copy android/key.properties.example to android/key.properties or set the " +
            "TECHPIE_ANDROID_* environment variables."
    }
    require(releaseStoreFile?.isFile == true) {
        "Release keystore does not exist: ${releaseStoreFile?.absolutePath}"
    }
}

android {
    namespace = "club.geekpie.techpie"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    signingConfigs {
        create("release") {
            storeFile = releaseStoreFile
            storePassword = releaseStorePassword
            keyAlias = releaseKeyAlias
            keyPassword = releaseKeyPassword
            storeType = releaseStoreType

            // Direct-distribution APKs must remain installable on old devices
            // while also getting whole-APK integrity and signing-key rotation.
            enableV1Signing = true
            enableV2Signing = true
            enableV3Signing = true
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "club.geekpie.techpie"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}
