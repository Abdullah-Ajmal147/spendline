#!/usr/bin/env bash
# Generates the android/ and ios/ folders and applies the settings the
# on-device AI package needs. Safe to run more than once.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter create . --project-name spendline --org com.spendline --platforms android,ios
flutter pub get

# ---- Android: minSdk 30 (LiteRT-LM), INTERNET in release builds, app name
GRADLE=android/app/build.gradle.kts
[ -f "$GRADLE" ] || GRADLE=android/app/build.gradle
perl -pi -e 's/flutter\.minSdkVersion/30/' "$GRADLE"

MANIFEST=android/app/src/main/AndroidManifest.xml
grep -q 'android.permission.INTERNET' "$MANIFEST" || \
  perl -0pi -e 's|(<manifest[^>]*>)|$1\n    <uses-permission android:name="android.permission.INTERNET"/>|' "$MANIFEST"
perl -pi -e 's/android:label="spendline"/android:label="Spendline"/' "$MANIFEST"

# ---- iOS: deployment target 15.0, static frameworks
perl -pi -e "s/IPHONEOS_DEPLOYMENT_TARGET = \d+\.\d+;/IPHONEOS_DEPLOYMENT_TARGET = 15.0;/g" ios/Runner.xcodeproj/project.pbxproj
if [ -f ios/Podfile ]; then
  perl -pi -e "s/^#?\s*platform :ios, '[\d.]+'/platform :ios, '15.0'/" ios/Podfile
  grep -q "use_frameworks! :linkage => :static" ios/Podfile || \
    perl -pi -e "s/^\s*use_frameworks!\s*\$/  use_frameworks! :linkage => :static/" ios/Podfile
fi

echo
echo "Platforms ready. Next: flutter test && flutter run"
