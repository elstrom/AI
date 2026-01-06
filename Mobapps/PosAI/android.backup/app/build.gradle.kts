plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

dependencies {
    // Core Library Desugaring for Java 8+ features in plugins
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

android {
    namespace = "com.banwibu.posai"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.banwibu.posai"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // Add GPU compatibility flags for buffer allocation issues
        manifestPlaceholders["flutter.enableImpeller"] = "false"
        
        // Add hardware rendering configuration
        resValue("bool", "flutter_enable_vulkan", "false")
        resValue("bool", "flutter_enable_opengl", "true")
        
        // Add arguments for Flutter engine to handle buffer allocation
        addManifestPlaceholders(
            mapOf(
                "flutter.enableHardwareAcceleration" to "true",
                "flutter.enableImpeller" to "false"
            )
        )
    }

    buildTypes {
        release {
            // Signing with the debug keys for now
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

flutter {
    source = "../.."
}
