import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("signing.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

dependencies {
    // Google Play Services
    implementation("com.google.android.gms:play-services-base:18.5.0")
    implementation("com.google.android.gms:play-services-tasks:18.2.0")
    implementation("com.google.android.gms:play-services-basement:18.5.0")
    
    // CameraX core library using the camera2 implementation
    val cameraxVersion = "1.4.1"
    implementation("androidx.camera:camera-core:$cameraxVersion")
    implementation("androidx.camera:camera-camera2:$cameraxVersion")
    // If you want to additionally use the CameraX Lifecycle library
    implementation("androidx.camera:camera-lifecycle:$cameraxVersion")
    // If you want to additionally use the CameraX View class
    implementation("androidx.camera:camera-view:$cameraxVersion")

    // Core Library Desugaring for Java 8+ features in plugins
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

android {
    signingConfigs {
        create("release") {
            val p = keystoreProperties
            if (p.isNotEmpty()) {
                keyAlias = p.getProperty("keyAlias")
                keyPassword = p.getProperty("keyPassword")
                storeFile = file(p.getProperty("storeFile"))
                storePassword = p.getProperty("storePassword")
                println("Signing config loaded for alias: $keyAlias")
            } else {
                println("WARNING: keystoreProperties is empty!")
            }
        }
    }

    namespace = "com.banwibu.scanai"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.banwibu.scanai"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
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
            signingConfig = signingConfigs.getByName("release")
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
