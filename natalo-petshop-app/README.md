# 🐾 Natalo Petshop — Native Android App (Hybrid Mode)

Konversi natalopetshop.com ke native Android app dengan Capacitor.
Mode: **Hybrid** — APK me-load website live + akses native API.

---

## ✅ Yang akan Anda dapat

- APK Android native (terinstall di HP, ada icon di home screen)
- Splash screen branded `#468284` (warna theme website)
- Status bar warna match dengan website
- WhatsApp link otomatis buka WhatsApp app (bukan webview)
- Instagram link buka Instagram app
- Halaman `tel:` & `mailto:` buka dialer/email
- Offline detection dengan UI fallback
- Network status awareness
- Siap untuk Play Store (lolos review karena ada native plugins)
- Auto-update: setiap update di natalopetshop.com langsung tampil di app

---

## 📋 Prasyarat (di komputer Anda)

| Tool | Versi minimum | Cek dengan |
|------|---------------|------------|
| Node.js | 20.x | `node -v` |
| npm | 10.x | `npm -v` |
| JDK | 17 atau 21 | `java -version` |
| Android Studio | Hedgehog (2023.1) atau lebih baru | — |
| Android SDK | API 34+ | Via Android Studio |
| Gradle | 8.x | Otomatis via wrapper |

### Install kalau belum ada:
- **Node.js**: https://nodejs.org/ (pilih LTS)
- **JDK 17**: https://adoptium.net/ (pilih JDK 17 LTS)
- **Android Studio**: https://developer.android.com/studio
- Setelah Android Studio terinstall, buka SDK Manager → install:
  - Android SDK Platform 34
  - Android SDK Build-Tools 34.0.0
  - Android SDK Platform-Tools

### Set environment variables (Windows):
```
ANDROID_HOME = C:\Users\<USERNAME>\AppData\Local\Android\Sdk
JAVA_HOME    = C:\Program Files\Eclipse Adoptium\jdk-17.x.x
PATH += %ANDROID_HOME%\platform-tools
```

### Set environment variables (macOS/Linux):
```bash
# Tambahkan ke ~/.zshrc atau ~/.bashrc
export ANDROID_HOME=$HOME/Library/Android/sdk    # macOS
# export ANDROID_HOME=$HOME/Android/Sdk          # Linux
export JAVA_HOME=$(/usr/libexec/java_home -v 17) # macOS
export PATH=$PATH:$ANDROID_HOME/platform-tools
```

---

## 🚀 Setup Step-by-Step

### Step 1: Install dependencies

```bash
cd natalo-petshop-app
npm install
```

### Step 2: Siapkan icon & splash

Lihat `scripts/icon-setup.md` untuk detail. Singkatnya:
1. Buat `resources/icon.png` (1024×1024)
2. Buat `resources/splash.png` (2732×2732)

Anda bisa pakai logo dari https://www.natalopetshop.com/icons/icon-512x512.png lalu upscale.

### Step 3: Tambah platform Android

```bash
npx cap add android
```

Ini akan generate folder `android/` dengan project Android Studio lengkap.

### Step 4: Customize Android files

**4a. Replace MainActivity.java**

Copy `android-customizations/MainActivity.java` ke:
```
android/app/src/main/java/com/natalopetshop/app/MainActivity.java
```
(Ganti file yang sudah ada)

**4b. Edit AndroidManifest.xml**

Buka: `android/app/src/main/AndroidManifest.xml`

Tambahkan permissions & queries dari `android-customizations/AndroidManifest-additions.xml`.

Contoh hasil akhir struktur:
```xml
<manifest ...>
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

    <queries>
        <package android:name="com.whatsapp" />
        <package android:name="com.whatsapp.w4b" />
        <package android:name="com.instagram.android" />
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="https" />
        </intent>
        <!-- ... lainnya ... -->
    </queries>

    <application
        android:name="..."
        android:networkSecurityConfig="@xml/network_security_config"
        ...>
        <!-- ... activity ... -->
    </application>
</manifest>
```

**4c. Buat network security config**

Buat folder & file:
```
android/app/src/main/res/xml/network_security_config.xml
```
Copy isi dari `android-customizations/network_security_config.xml`.

**4d. Update strings.xml**

Edit `android/app/src/main/res/values/strings.xml`, copy isi dari `android-customizations/strings.xml`.

### Step 5: Generate icon & splash

```bash
npx @capacitor/assets generate --android
```

### Step 6: Sync Capacitor

```bash
npx cap sync android
```

### Step 7: Test di emulator/device

**Pakai emulator Android Studio:**
```bash
npx cap open android
# Di Android Studio: klik tombol Run (▶)
```

**Pakai HP Android (USB Debugging):**
1. HP: Settings → About Phone → tap "Build Number" 7x → developer mode aktif
2. Settings → Developer Options → enable "USB Debugging"
3. Colok HP ke laptop, allow USB debugging
4. Verifikasi: `adb devices` (harus muncul HP Anda)
5. Jalankan:
```bash
npx cap run android
```

### Step 8: Build APK Debug

Untuk testing/share ke teman:
```bash
cd android
./gradlew assembleDebug
```

APK output: `android/app/build/outputs/apk/debug/app-debug.apk`

Ukuran biasanya 5-10 MB. Bisa langsung di-install di HP Android (allow "install from unknown sources").

---

## 📦 Build APK Release (untuk Play Store)

Untuk release, harus signed dengan keystore. Step lengkap:

### A. Generate keystore (sekali saja, simpan baik-baik!)

```bash
keytool -genkey -v -keystore natalo-release.keystore \
  -alias natalo -keyalg RSA -keysize 2048 -validity 10000
```

Isi:
- Password keystore: (catat!)
- Nama: Natalo Petshop & Aquarium
- Kota: Medan
- Provinsi: Sumatera Utara
- Kode negara: ID

⚠️ **PENTING**: Simpan file `natalo-release.keystore` + password di tempat aman. Kalau hilang, Anda **TIDAK BISA** update app di Play Store (harus publish ulang sebagai app baru).

### B. Letakkan keystore

Pindahkan ke: `android/app/natalo-release.keystore`

### C. Buat `android/keystore.properties`

```properties
storeFile=natalo-release.keystore
storePassword=PASSWORD_KEYSTORE_ANDA
keyAlias=natalo
keyPassword=PASSWORD_KEY_ANDA
```

⚠️ **JANGAN commit file ini ke git!** (sudah di-ignore otomatis)

### D. Edit `android/app/build.gradle`

Tambahkan **sebelum** `android { ... }`:
```gradle
def keystorePropertiesFile = rootProject.file("keystore.properties")
def keystoreProperties = new Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}
```

Di dalam `android { ... }`, tambahkan:
```gradle
signingConfigs {
    release {
        if (keystorePropertiesFile.exists()) {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile file(keystoreProperties['storeFile'])
            storePassword keystoreProperties['storePassword']
        }
    }
}

buildTypes {
    release {
        signingConfig signingConfigs.release
        minifyEnabled true
        shrinkResources true
        proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
    }
}
```

### E. Build release APK

```bash
cd android
./gradlew assembleRelease
```

Output: `android/app/build/outputs/apk/release/app-release.apk`

### F. Build AAB (untuk Play Store)

Play Store sekarang wajib upload format `.aab` (Android App Bundle):
```bash
cd android
./gradlew bundleRelease
```

Output: `android/app/build/outputs/bundle/release/app-release.aab`

---

## 🎯 Update kode website? Tidak perlu rebuild APK!

Karena pakai Hybrid Mode, semua perubahan di natalopetshop.com **otomatis langsung tampil di app**. APK hanya perlu di-rebuild jika:

- Ganti app icon / splash
- Tambah/ubah native plugin
- Update versi Android SDK
- Ganti domain server di `capacitor.config.ts`

---

## 🐛 Troubleshooting

### Error: `JAVA_HOME is not set`
→ Set environment variable JAVA_HOME ke folder JDK 17.

### Error: `Failed to resolve: androidx.xxx`
→ Buka Android Studio → File → Sync Project with Gradle Files.

### Error: `SDK location not found`
→ Buat file `android/local.properties` isinya:
```
sdk.dir=/path/to/Android/Sdk
```

### App buka tapi blank putih
→ Cek `capacitor.config.ts` field `server.url` benar `https://www.natalopetshop.com` (dengan `www`).
→ Cek koneksi internet device.
→ Run dengan logging: `npx cap run android --target=<device-id>` lalu cek logcat di Android Studio.

### WhatsApp link tidak buka WhatsApp app
→ Pastikan MainActivity.java sudah diganti dengan versi custom.
→ Pastikan `<queries>` block ada di AndroidManifest.xml.

### Icon Android tetap default robot hijau
→ Run: `npx @capacitor/assets generate --android` lagi.
→ Bersihkan: `cd android && ./gradlew clean && cd ..`
→ Sync: `npx cap sync android`

### Build sangat lambat di komputer pertama kali
→ Normal. Gradle download dependencies pertama kali bisa 10-30 menit. Berikutnya cepat.

---

## 📚 Next Steps (Opsional)

Setelah app dasar jalan, Anda bisa tambah fitur native:

1. **Push Notification untuk promo** — pakai Firebase Cloud Messaging + `@capacitor/push-notifications`. Setup ~2 jam.
2. **Share produk ke WhatsApp/IG** — pakai `@capacitor/share` (sudah terinstall). Tinggal panggil dari JS di website.
3. **Deep link** — buka link `natalopetshop.com/products/xxx` langsung ke app jika terinstall.
4. **App Shortcuts** — long-press icon app → quick action ke kategori favorit.
5. **Biometric login** — login pakai sidik jari/face unlock.

---

## 📂 Struktur File Project

```
natalo-petshop-app/
├── package.json                           # NPM dependencies
├── capacitor.config.ts                    # Konfigurasi Capacitor (HYBRID MODE)
├── tsconfig.json
├── .gitignore
├── README.md                              # File ini
├── www/
│   └── index.html                         # Loading page + offline fallback
├── resources/                             # Source icon & splash
│   ├── icon.png                           # 1024x1024 (Anda buat)
│   └── splash.png                         # 2732x2732 (Anda buat)
├── android-customizations/                # File yang di-copy ke android/ setelah `cap add android`
│   ├── MainActivity.java
│   ├── AndroidManifest-additions.xml
│   ├── network_security_config.xml
│   └── strings.xml
├── scripts/
│   └── icon-setup.md                      # Panduan icon
└── android/                               # (di-generate oleh `cap add android`)
```

---

## 💬 Butuh bantuan?

Kalau stuck di langkah tertentu, balik ke chat ini dan kasih tau:
- Step ke berapa
- Error message lengkap
- Screenshot kalau perlu

Saya bantu debug.
