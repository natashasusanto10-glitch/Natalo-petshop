# 🎨 Icon & Splash Screen Setup

App Anda butuh 2 file gambar source untuk generate semua ukuran icon Android:

## File yang harus disiapkan

Letakkan di folder `resources/`:

### 1. `resources/icon.png`
- Ukuran: **1024×1024 pixel**
- Format: PNG dengan background solid (jangan transparent)
- Padding: minimal 10% dari edge (icon Android di-mask jadi rounded square)
- Tip: Pakai logo 🐾 Natalo dengan background `#468284` (theme color)

### 2. `resources/splash.png`
- Ukuran: **2732×2732 pixel** (square, akan di-crop sesuai device)
- Format: PNG
- Logo di tengah, max 30% dari ukuran total
- Background: `#468284` (sama dengan splash di capacitor.config.ts)

---

## Cara generate

Anda sudah punya `icon-512x512.png` di website. Bisa upscale ke 1024x1024:

### Opsi 1: Pakai @capacitor/assets (otomatis, recommended)

```bash
# Setelah resources/icon.png dan resources/splash.png siap:
npx @capacitor/assets generate --android

# Ini akan otomatis generate:
# - android/app/src/main/res/mipmap-*/ (semua density)
# - android/app/src/main/res/drawable-*/splash.png
# - android/app/src/main/res/values/colors.xml
```

### Opsi 2: Manual via online generator

Kalau cara di atas error:
1. Buka https://icon.kitchen/ atau https://www.appicon.co/
2. Upload icon Anda
3. Download ZIP "Android"
4. Extract ke `android/app/src/main/res/`

### Opsi 3: Pakai Figma / Photoshop

Buat 2 versi manual sesuai ukuran density:
- `mdpi` 48×48
- `hdpi` 72×72
- `xhdpi` 96×96
- `xxhdpi` 144×144
- `xxxhdpi` 192×192

Kemudian copy ke `android/app/src/main/res/mipmap-{density}/ic_launcher.png`

---

## Adaptive Icon (Android 8+)

Android 8+ pakai "adaptive icon" yang terdiri dari foreground + background layer.
@capacitor/assets sudah handle ini otomatis kalau icon source punya padding 25% di edge.

Kalau mau manual: edit `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`
