# Resources — sumber asset Capacitor

File di folder ini dipakai oleh `@capacitor/assets` untuk auto-generate icon & splash native iOS.

## File yang dibutuhkan

| File | Ukuran | Status | Catatan |
|---|---|---|---|
| `icon-only.png` | 1024×1024 | ⚠️ saat ini 512×512 | App icon utama. **Replace dengan 1024×1024** untuk kualitas produksi. |
| `icon-foreground.png` | 1024×1024 | ⚠️ saat ini 512×512 | Versi maskable / foreground. |
| `splash.png` | 2732×2732 | ❌ belum ada | Splash screen — background brand `#1E5FBF` dengan logo di tengah. |
| `splash-dark.png` | 2732×2732 | optional | Dark mode splash (pakai background lebih gelap). |

## Generate

```bash
npm run cap:assets
```

Output otomatis ke `ios/App/App/Assets.xcassets/`. Tidak perlu edit manual di Xcode.

## Bikin splash.png cepat

Pakai Figma / Canva:
1. Canvas 2732×2732.
2. Background solid `#1E5FBF`.
3. Logo Natalo di tengah, kira-kira 30% dari lebar canvas (~800px).
4. Export PNG, simpan sebagai `resources/splash.png`.

Atau export dari `public/icons/icon-512x512.png` di-resize 4× (akan blur, hanya untuk preview cepat).
