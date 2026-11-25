import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Imzolash kalitlari android/key.properties dan o'qiladi.
//
// Fayl git ga TUSHMAYDI (.gitignore), chunki ichida parol bor. Shuning
// uchun u yo'q bo'lishi ham mumkin — masalan boshqa mashinada yoki toza
// klonda. Bunday holda reliz eski yo'l bilan, debug kaliti bilan
// imzolanadi: `flutter build apk --release` ishlashda davom etadi, faqat
// Google Play bunday buildni qabul qilmaydi.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) {
        file.inputStream().use { load(it) }
    }
}
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null

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
        // flutter_local_notifications (push на открытом приложении) требует
        // java.time на старых Android — desugaring.
        isCoreLibraryDesugaringEnabled = true
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
        // Android 8.0 (API 26). Yandex xaritalarining 4.19 versiyasi 26 dan
        // pastini qo'llab-quvvatlamaydi, u esa 16 KB sahifalar uchun kerak —
        // Google Play 4 KB li kutubxona bilan relizni qabul qilmaydi.
        //
        // Narxi: Android 7.x dagi telefonlar ilovani ko'rmaydi. Bu 2017 yilgi
        // versiya, ulushi juda kichik.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Два приложения из одного кода (21.11.2026): клиент и водитель/владелец
    // техники. В магазинах это разные приложения — свой applicationId и
    // название. Код, вход, сеть и переводы общие; ветвление — appFlavor
    // в lib/core/app_flavor.dart. Без --flavor собирается client
    // (default-flavor в pubspec.yaml).
    flavorDimensions += "app"
    productFlavors {
        create("client") {
            dimension = "app"
            applicationId = "uz.movexgo.app"
            resValue("string", "app_name", "MoveXgo")
        }
        create("driver") {
            dimension = "app"
            applicationId = "uz.movexgo.driver"
            resValue("string", "app_name", "MoveX GO Driver")
        }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Ilgari bu yerda debug kaliti turardi va yonida "TODO: o'z
            // kalitingizni qo'ying" degan izoh. Debug kaliti bilan
            // imzolangan buildni Google Play QABUL QILMAYDI, ya'ni ilovani
            // chiqarib bo'lmasdi.
            //
            // Kalit bo'lmasa — eski yo'l saqlanadi, aks holda toza klonda
            // yig'ilish umuman ishlamay qolardi.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
dependencies {
    implementation("com.yandex.android:maps.mobile:4.2.2-full")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}