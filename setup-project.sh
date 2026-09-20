#!/bin/bash
set -e

echo "📁 Creando archivos base..."

# ---- build.gradle.kts (raíz) ----
cat > build.gradle.kts << 'GRADLEEOF'
plugins {
    id("com.android.application") version "8.5.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
}
GRADLEEOF

# ---- settings.gradle.kts ----
cat > settings.gradle.kts << 'GRADLEEOF'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "tv-app"
include(":app")
GRADLEEOF

# ---- gradle.properties ----
cat > gradle.properties << 'GRADLEEOF'
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
kotlin.code.style=official
android.nonTransitiveRClass=true
GRADLEEOF

# ---- app/build.gradle.kts ----
mkdir -p app
cat > app/build.gradle.kts << 'GRADLEEOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.anonimus757.tvapp"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.anonimus757.tvapp"
        minSdk = 21
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        compose = true
    }
    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.14"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.4")
    implementation("androidx.activity:activity-compose:1.9.1")

    implementation(platform("androidx.compose:compose-bom:2024.08.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.tv:tv-material:1.0.0")

    implementation("io.coil-kt:coil-compose:2.7.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")

    debugImplementation("androidx.compose.ui:ui-tooling")
}
GRADLEEOF

# ---- AndroidManifest.xml ----
mkdir -p app/src/main
cat > app/src/main/AndroidManifest.xml << 'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

    <uses-feature
        android:name="android.software.leanback"
        android:required="false" />
    <uses-feature
        android:name="android.hardware.touchscreen"
        android:required="false" />

    <application
        android:allowBackup="true"
        android:label="@string/app_name"
        android:banner="@drawable/app_banner"
        android:supportsRtl="true"
        android:theme="@style/Theme.TVApp">

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:screenOrientation="landscape"
            android:theme="@style/Theme.TVApp">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
                <category android:name="android.intent.category.LEANBACK_LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
XMLEOF

# ---- strings.xml ----
mkdir -p app/src/main/res/values
cat > app/src/main/res/values/strings.xml << 'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">TV App</string>
</resources>
XMLEOF

# ---- themes.xml ----
cat > app/src/main/res/values/themes.xml << 'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="Theme.TVApp" parent="android:Theme.Material.NoActionBar">
        <item name="android:windowBackground">@android:color/black</item>
    </style>
</resources>
XMLEOF

# ---- app_banner.xml (drawable) ----
mkdir -p app/src/main/res/drawable
cat > app/src/main/res/drawable/app_banner.xml << 'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <solid android:color="#0F172A" />
</shape>
XMLEOF

# ---- MainActivity.kt ----
mkdir -p app/src/main/java/com/anonimus757/tvapp
cat > app/src/main/java/com/anonimus757/tvapp/MainActivity.kt << 'KTEOF'
package com.anonimus757.tvapp

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            HomeScreen()
        }
    }
}

@Composable
fun HomeScreen() {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF0F172A)),
        contentAlignment = Alignment.Center
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                text = "🎛️ TV App",
                color = Color(0xFF38BDF8),
                fontSize = 42.sp,
                fontWeight = FontWeight.Bold
            )
            Spacer(Modifier.height(12.dp))
            Text(
                text = "¡Funcionando!",
                color = Color(0xFF94A3B8),
                fontSize = 20.sp
            )
        }
    }
}
KTEOF

echo ""
echo "✅✅✅ Proyecto creado"
echo ""
echo "📂 Archivos:"
ls -la
echo ""
echo "📂 Dentro de app/:"
find app -type f