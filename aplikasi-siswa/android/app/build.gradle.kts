plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.sarana_pengaduan_sekolah"

    // Android API yang digunakan untuk compile
    compileSdk = 36

    // NDK
    ndkVersion = "27.0.12077973"

    compileOptions {
        // Aktifkan core library desugaring
        isCoreLibraryDesugaringEnabled = true

        // Gunakan Java 17
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        // Gunakan JVM 17
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.sarana_pengaduan_sekolah"

        // Minimum Android
        minSdk = 24

        // Target Android API 36
        targetSdk = 36

        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Signing debug untuk sementara
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // Core library desugaring
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3")
}

flutter {
    source = "../.."
}