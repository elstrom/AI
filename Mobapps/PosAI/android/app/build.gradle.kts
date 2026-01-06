plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

dependencies {
    // Core Library Desugaring for Java 8+ features in plugins
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

android {
    namespace = "com.banwibu.posai"
    // ============ ANDROID 15+ COMPATIBILITY (16KB Page Size) ============
    // Google requires compileSdk 36+ and NDK 28+ for 16KB page alignment
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.banwibu.posai"
        minSdk = flutter.minSdkVersion
        // Target SDK 36 for Android 15+ support
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // ============ 16KB PAGE SIZE FIX ============
    // Required for Android 15+ devices with 16KB page size kernels
    // This ensures native libraries are extracted and properly aligned
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

flutter {
    source = "../.."
}
