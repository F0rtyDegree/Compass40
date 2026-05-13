plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "by.fortydegree.compass40"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "by.fortydegree.compass40"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Определяем наш релизный signingConfig
    signingConfigs {
        create("release") {
            storeFile = file("upload-keystore.jks")
            storePassword = "Compass40"
            keyAlias = "upload"
            keyPassword = "Compass40"
        }
    }

    buildTypes {
        release {
            // Вот она — главная правка: используем наш конфиг, а не debug
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}