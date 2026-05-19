import java.util.Properties
import java.io.FileInputStream

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

// Release signing credentials — di-load dari android/key.properties yang
// di-gitignore. Kalau file tidak ada (mis. CI fresh clone tanpa secret),
// release build akan fail dengan pesan jelas, bukan diam-diam pakai debug.
val keystoreProperties = Properties().apply {
    val keystorePropertiesFile = rootProject.file("key.properties")
    if (keystorePropertiesFile.exists()) {
        load(FileInputStream(keystorePropertiesFile))
    }
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
        // applicationId = com.natalo.petshop → SEPARATE listing dari Capacitor
        // yang pakai com.natalopetshop.app. Keystore Capacitor asli hilang,
        // jadi kita publish app native Flutter ini sebagai listing baru di
        // Play Console. Capacitor closed beta lama dibiarkan deprecated.
        // Lihat: PLAY_STORE_NOTES.md (history & rationale).
        applicationId = "com.natalo.petshop"
        manifestPlaceholders["appLabel"] = "Natalo Petshop"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            // Sign dengan keystore production (natalo-petshop-release.jks).
            // Kredensial di-load dari android/key.properties di top of file.
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
