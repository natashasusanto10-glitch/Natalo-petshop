plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Google Services — reads google-services.json di module ini, generate
    // values_resources untuk firebase_core auto-init. Wajib untuk
    // firebase_messaging/firebase_crashlytics/firebase_analytics jalan.
    id("com.google.gms.google-services")
    // Firebase Crashlytics — auto-upload mapping file saat release build
    // supaya stack trace di console kebaca readable (deobfuscated).
    id("com.google.firebase.crashlytics")
}

android {
    namespace = "com.natalo.petshop"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Base applicationId = com.natalo.petshop (match Capacitor production).
        // Release build pakai ID ini → di Play Store akan REPLACE Capacitor app
        // listing. Debug build pakai suffix `.flutter` (lihat buildTypes.debug)
        // supaya bisa install side-by-side Capacitor production saat dev local.
        applicationId = "com.natalo.petshop"
        manifestPlaceholders["appLabel"] = "Natalo Petshop"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 35
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
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
