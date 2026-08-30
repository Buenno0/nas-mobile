plugins {
  id("com.android.application")
  id("org.jetbrains.kotlin.android")
  id("org.jetbrains.kotlin.plugin.compose")
  id("org.jetbrains.kotlin.plugin.serialization")
}

android {
  namespace = "com.buenno.ozymandias.firetv"
  compileSdk = 36

  defaultConfig {
    applicationId = "com.buenno.ozymandias.firetv"
    minSdk = 25
    targetSdk = 36
    versionCode = 1
    versionName = "0.1.0"
    testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
  }

  buildFeatures { compose = true }

  buildTypes {
    release {
      // O primeiro marco é distribuído apenas por sideload. Mantemos uma
      // assinatura estável local; a Appstore terá um keystore próprio.
      signingConfig = signingConfigs.getByName("debug")
      isMinifyEnabled = false
    }
  }

  compileOptions {
    isCoreLibraryDesugaringEnabled = true
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
  }
  kotlinOptions { jvmTarget = "17" }

  packaging { resources.excludes += "/META-INF/{AL2.0,LGPL2.1}" }
}

dependencies {
  // Compose 1.9.x remains compatible with compileSdk 36 and Fire OS 6+.
  val composeBom = platform("androidx.compose:compose-bom:2025.08.01")
  implementation(composeBom)
  androidTestImplementation(composeBom)

  implementation("androidx.activity:activity-compose:1.13.0")
  implementation("androidx.lifecycle:lifecycle-runtime-compose:2.10.0")
  implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.10.0")
  implementation("androidx.compose.ui:ui")
  implementation("androidx.compose.ui:ui-tooling-preview")
  implementation("androidx.compose.foundation:foundation")
  implementation("androidx.compose.material3:material3")
  implementation("androidx.tv:tv-material:1.1.0")

  implementation("androidx.media3:media3-exoplayer:1.10.1")
  implementation("androidx.media3:media3-ui:1.10.1")
  implementation("androidx.media3:media3-session:1.10.1")
  implementation("androidx.media3:media3-extractor:1.10.1")

  implementation("androidx.datastore:datastore-preferences:1.2.1")
  implementation("com.squareup.okhttp3:okhttp:4.12.0")
  implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0")
  implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
  implementation("io.coil-kt:coil-compose:2.7.0")
  implementation("com.google.zxing:core:3.5.3")
  coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")

  testImplementation("junit:junit:4.13.2")
  testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.10.2")
  androidTestImplementation("androidx.test.ext:junit:1.3.0")
  androidTestImplementation("androidx.test.espresso:espresso-core:3.7.0")
  androidTestImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
  androidTestImplementation("androidx.compose.ui:ui-test-junit4")
  debugImplementation("androidx.compose.ui:ui-tooling")
  debugImplementation("androidx.compose.ui:ui-test-manifest")
}
