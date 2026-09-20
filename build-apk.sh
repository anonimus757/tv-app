#!/bin/bash
set -e

echo "🔧 1/6 Forzando Java 17..."
sudo update-alternatives --set java /usr/lib/jvm/java-17-openjdk-amd64/bin/java 2>/dev/null || true
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export PATH=$JAVA_HOME/bin:$PATH
echo "Java activo:"
java -version 2>&1 | head -n 1

echo ""
echo "🔧 2/6 Verificando Java 17 disponible..."
ls /usr/lib/jvm/ | grep 17 || sudo apt-get install -y openjdk-17-jdk

echo ""
echo "🔧 3/6 Creando local.properties..."
echo "sdk.dir=$HOME/android-sdk" > local.properties

echo ""
echo "🔧 4/6 Descargando Gradle 8.7..."
cd /tmp
if [ ! -f gradle-8.7-bin.zip ]; then
    wget -q https://services.gradle.org/distributions/gradle-8.7-bin.zip
fi
if [ ! -d gradle-8.7 ]; then
    unzip -q gradle-8.7-bin.zip
fi
export PATH=/tmp/gradle-8.7/bin:$PATH
gradle -v 2>&1 | grep "Gradle " | head -n 1

echo ""
echo "🔧 5/6 Generando Gradle Wrapper..."
cd /workspaces/tv-app
gradle wrapper --gradle-version 8.7

echo ""
echo "🔧 6/6 Compilando APK (primera vez: 5-10 min)..."
./gradlew assembleDebug --no-daemon

echo ""
echo "✅✅✅ APK generado:"
find . -name "*.apk" -type f