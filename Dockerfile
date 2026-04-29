# InvenTree APK Builder
# Builds the InvenTree Android app from source using the latest stable Flutter SDK.
# Based on ghcr.io/cirruslabs/flutter:stable which tracks the latest Flutter/Dart stable release.

FROM ghcr.io/cirruslabs/flutter:stable

USER root

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    python3 \
    python3-pip \
    python3-venv \
    unzip \
    wget \
    ninja-build \
    openjdk-17-jdk \
    && rm -rf /var/lib/apt/lists/*

# Set JAVA_HOME
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV PATH="${JAVA_HOME}/bin:${PATH}"

WORKDIR /app

# Create Python venv and install invoke
RUN python3 -m venv /env \
    && /env/bin/pip install --upgrade pip --quiet \
    && /env/bin/pip install invoke --quiet

# Create python symlink required by invoke tasks
RUN ln -s /usr/bin/python3 /usr/bin/python

# Clone InvenTree app source
RUN echo "--- Cloning InvenTree app source ---" \
    && git clone https://github.com/inventree/inventree-app.git /app

# Accept Android SDK licenses
RUN echo "--- Accepting Android SDK licenses ---" \
    && yes | flutter doctor --android-licenses > /dev/null 2>&1 || true

# Run flutter doctor to pre-cache SDK components
RUN echo "--- Running flutter doctor ---" \
    && flutter doctor 2>&1 | grep -v "^$" || true

# Generate localization files
RUN echo "--- Generating localization files ---" \
    && cd /app && /env/bin/invoke translate 2>&1 | grep -v "untranslated"

# Install Flutter dependencies
RUN echo "--- Installing Flutter dependencies ---" \
    && cd /app && flutter pub get 2>&1 | tail -5

# Generate keystore for APK signing
RUN echo "--- Generating signing keystore ---" \
    && printf 'storePassword=Secret123\nkeyPassword=Secret123\nkeyAlias=key\nstoreFile=/tmp/keys.jks' > /app/android/key.properties \
    && keytool -genkeypair -v \
        -keystore /tmp/keys.jks \
        -keyalg RSA \
        -keysize 2048 \
        -validity 10000 \
        -alias key \
        -storepass Secret123 \
        -keypass Secret123 \
        -dname "CN=Dummy, OU=Dummy, O=Dummy, L=Dummy, ST=Dummy, C=US" \
        > /dev/null 2>&1

# Accept SDK license
RUN mkdir -p /root/Android/Sdk/licenses \
    && echo "24333f8a63b6825ea9c5514f83c2829b004d1fee" > /root/Android/Sdk/licenses/android-sdk-license

RUN mkdir -p /output
VOLUME ["/output"]

CMD echo "--- Starting InvenTree APK build ---" \
    && cd /app \
    && flutter build apk --release 2>&1 | grep -E "(error|warning|Built|Running|Gradle|FAILED|Exception)" \
    && cp build/app/outputs/flutter-apk/app-release.apk /output/app.apk \
    && echo "--- Build complete. APK saved to /output/app.apk ---"
