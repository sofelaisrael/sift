import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.screensort.screensort_lam"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.screensort.screensort_lam"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // No ABI filter: it applied to every build type, so pinning arm64-v8a
        // took x86_64 emulator and 32-bit device support away from the whole
        // app, including screenshot capture, ML Kit OCR and cloud chat, none of
        // which involve LiteRT. The build does not need it: the plugin's hook
        // emits no native asset for android_x86_64 and still succeeds, and
        // armeabi-v7a is the same skip case — it has no registered checksum
        // either, the hook lists only litertlm-android_arm64.tar.gz for Android.
        // Elsewhere the app runs normally; Settings says the model is absent.
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                // android/key.properties missing (e.g. first CI run): fall back to the
                // debug key so builds still complete. Debug-signed APKs trigger
                // antivirus "virus detected" false positives on sideloaded installs,
                // so add a real keystore (Codemagic code signing -> "Generate
                // keystore" writes android/key.properties automatically).
                println("WARNING: android/key.properties not found - release build will be DEBUG-signed")
                signingConfig = signingConfigs.getByName("debug")
            }
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
