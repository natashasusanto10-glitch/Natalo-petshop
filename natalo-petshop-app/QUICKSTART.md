# ⚡ Quick Start Cheatsheet

Sudah baca README.md? Ini ringkasan command yang sering dipakai.

## First time setup (sekali saja)
```bash
npm install
npx cap add android
# Copy file dari android-customizations/ ke android/ (lihat README step 4)
npx @capacitor/assets generate --android
npx cap sync android
```

## Daily workflow
```bash
# Update config / native code:
npx cap sync android

# Buka di Android Studio:
npx cap open android

# Run di device/emulator:
npx cap run android

# Build APK debug:
cd android && ./gradlew assembleDebug

# Build APK release (signed):
cd android && ./gradlew assembleRelease

# Build AAB untuk Play Store:
cd android && ./gradlew bundleRelease
```

## Lokasi output
- Debug APK: `android/app/build/outputs/apk/debug/app-debug.apk`
- Release APK: `android/app/build/outputs/apk/release/app-release.apk`
- Release AAB: `android/app/build/outputs/bundle/release/app-release.aab`

## Cek device terhubung
```bash
adb devices
```

## Bersihin build kalau error
```bash
cd android
./gradlew clean
cd ..
npx cap sync android
```

## Update website? TIDAK perlu rebuild APK
Hybrid Mode otomatis load natalopetshop.com terbaru.
Rebuild APK hanya kalau ganti icon/splash/plugin/SDK.
