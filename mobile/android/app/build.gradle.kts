plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "uz.movexgo.app"
    compileSdk = flutter.compileSdkVersion
    // ndkVersion ataylab ko'rsatilmagan.
    //
    // Uni yozib qo'yish AGP'ni NDK'ni (2.5 GB) yuklab olishga majbur qiladi,
    // holbuki loyihadagi 10 ta android-plaginning birortasida ham native
    // C/C++ kodi yo'q — hammasi tayyor .so yoki faqat Kotlin/Java.
    //
    // Agar kelajakda native kodli plagin qo'shilsa, yig'ilish "NDK not
    // configured" deb aniq aytadi — o'shanda qatorni qaytaring:
    //     ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "uz.movexgo.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
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
    implementation("com.yandex.android:maps.mobile:4.2.2-full")
}