plugins {
 id("com.android.application")
 id("org.jetbrains.kotlin.android")
}

android {
 namespace = "com.ali.mikrotikscanner"
 compileSdk = 35

 defaultConfig {
 applicationId = "com.ali.mikrotikscanner"
 minSdk = 24
 targetSdk = 35
 versionCode = 1
 versionName = "1.0"
 }

 buildTypes {
 release {
 isMinifyEnabled = false
 proguardFiles(
 getDefaultProguardFile("proguard-android-optimize.txt"),
 "proguard-rules.pro"
 )
 }
 }
 
 compileOptions {
 sourceCompatibility = JavaVersion.VERSION_1_8
 targetCompatibility = JavaVersion.VERSION_1_8
 }
 
 kotlinOptions {
 jvmTarget = "1.8"
 }
}

dependencies {
 implementation("androidx.core:core-ktx:1.15.0")
 implementation("androidx.appcompat:appcompat:1.7.0")
 implementation("com.google.android.material:material:1.12.0")
 implementation("androidx.constraintlayout:constraintlayout:2.2.0")
 
 // Network Utilities
 implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
 implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
}
