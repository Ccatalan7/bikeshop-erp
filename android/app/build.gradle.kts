import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val androidSigningProperties = Properties()
val androidSigningPropertiesFile = rootProject.file("key.properties")
if (androidSigningPropertiesFile.exists()) {
    androidSigningPropertiesFile.inputStream().use(androidSigningProperties::load)
}

fun signingValue(environmentName: String, propertyName: String): String? =
    System.getenv(environmentName)?.takeIf { it.isNotBlank() }
        ?: androidSigningProperties.getProperty(propertyName)?.takeIf { it.isNotBlank() }

val androidReleaseKeystorePath =
    signingValue("VINABIKE_ANDROID_KEYSTORE_PATH", "storeFile")
val androidReleaseStorePassword =
    signingValue("VINABIKE_ANDROID_STORE_PASSWORD", "storePassword")
val androidReleaseKeyAlias =
    signingValue("VINABIKE_ANDROID_KEY_ALIAS", "keyAlias")
val androidReleaseKeyPassword =
    signingValue("VINABIKE_ANDROID_KEY_PASSWORD", "keyPassword")
val isAndroidReleaseBuild = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}

if (isAndroidReleaseBuild) {
    require(!androidReleaseKeystorePath.isNullOrBlank()) {
        "VINABIKE_ANDROID_KEYSTORE_PATH (or android/key.properties storeFile) is required for release builds."
    }
    require(!androidReleaseStorePassword.isNullOrBlank()) {
        "VINABIKE_ANDROID_STORE_PASSWORD (or android/key.properties storePassword) is required for release builds."
    }
    require(!androidReleaseKeyAlias.isNullOrBlank()) {
        "VINABIKE_ANDROID_KEY_ALIAS (or android/key.properties keyAlias) is required for release builds."
    }
    require(!androidReleaseKeyPassword.isNullOrBlank()) {
        "VINABIKE_ANDROID_KEY_PASSWORD (or android/key.properties keyPassword) is required for release builds."
    }
}

android {
    namespace = "com.vinabike.erp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.vinabike.erp"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        if (!androidReleaseKeystorePath.isNullOrBlank()) {
            create("release") {
                storeFile = file(androidReleaseKeystorePath)
                storePassword = androidReleaseStorePassword
                keyAlias = androidReleaseKeyAlias
                keyPassword = androidReleaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
