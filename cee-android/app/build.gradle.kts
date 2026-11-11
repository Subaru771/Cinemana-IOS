plugins { id("com.android.application") }
android {
    namespace = "app.cinemana.cee.tv"
    compileSdk = 35
    defaultConfig {
        applicationId = "app.cinemana.cee.tv"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "0.1.0"
    }
    buildTypes { getByName("release") { isMinifyEnabled = false } }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
}
