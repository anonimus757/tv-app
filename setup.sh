set -e

echo "🔧 1/5 Java 17 y herramientas base..."
sudo apt-get update -qq
sudo apt-get install -y -qq openjdk-17-jdk unzip wget

echo "🔧 2/5 Descargando Android command-line tools..."
mkdir -p $HOME/android-sdk/cmdline-tools
cd $HOME/android-sdk/cmdline-tools
wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O cmdline-tools.zip
unzip -q cmdline-tools.zip
mv cmdline-tools latest
rm cmdline-tools.zip

echo "🔧 3/5 Configurando variables..."
echo 'export ANDROID_HOME=$HOME/android-sdk' >> ~/.bashrc
echo 'export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools' >> ~/.bashrc
export ANDROID_HOME=$HOME/android-sdk
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools

echo "🔧 4/5 Aceptando licencias..."
yes | sdkmanager --licenses > /dev/null 2>&1 || true

echo "🔧 5/5 Instalando Android 34 + build-tools..."
sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"

echo ""
echo "✅✅✅ ¡LISTO!"
java -version
ls $ANDROID_HOME