/**
 * Android Digital Asset Links — required oleh Android untuk App Links.
 *
 * URL harus tepat:
 * - https://www.natalopetshop.com/.well-known/assetlinks.json
 * - https://natalopetshop.com/.well-known/assetlinks.json
 *
 * Cara kerja:
 * - User klik/scan link "https://natalopetshop.com/u/asiong"
 * - Android verifikasi assetlinks.json di domain → cocok dgn package +
 *   signature APK yang ter-install → buka app native (bukan Chrome)
 * - Tanpa file valid, link jatuh ke browser (default behavior)
 *
 * SUMBER KEBENARAN TUNGGAL untuk assetlinks. Dulu ada juga file statis
 * `public/.well-known/assetlinks.json` (peninggalan app Capacitor lama,
 * package `com.natalopetshop.app`) yang MENUTUPI route ini di Vercel dan
 * berisi package salah — sudah dihapus. Sekarang cuma route ini, hardcoded
 * seperti AASA iOS (app/.well-known/apple-app-site-association/route.ts)
 * supaya nilainya eksplisit di source, bukan env var tersembunyi yang bisa
 * gagal-senyap ke `[]` kalau lupa di-set.
 *
 * CARA DAPAT FINGERPRINT (WAJIB dibetulkan sebelum rilis):
 *   Play Console → Setup → App integrity → App signing key certificate →
 *   SHA-256   (ini kunci yang dipakai Google Play App Signing, BUKAN upload
 *   key). Atau dari keystore rilis:
 *     keytool -list -v -keystore <release.keystore> -alias <alias>
 *   Format: uppercase, colon-delimited (`AA:BB:CC:...`).
 *
 * Bisa >1 fingerprint (mis. Play signing key + upload key) — tambahkan saja
 * ke array SHA256_FINGERPRINTS.
 */
import { NextResponse } from "next/server";

const PACKAGE_NAME = "com.natalo.petshop";

// TODO(rilis): GANTI dengan SHA-256 dari Play Console (App signing key).
// Nilai di bawah dibawa dari file statis lama & kemungkinan milik keystore
// Capacitor lama — verifikasi App Links akan GAGAL sampai ini dibetulkan.
const SHA256_FINGERPRINTS = [
  "F6:C8:F6:3F:5B:DF:24:3A:8F:9E:3E:C4:AC:91:23:08:EC:0B:57:77:85:A1:2A:7C:DB:12:1F:BF:26:85:2A:44",
];

export async function GET() {
  const body = [
    {
      relation: [
        "delegate_permission/common.handle_all_urls",
        "delegate_permission/common.get_login_creds",
      ],
      target: {
        namespace: "android_app",
        package_name: PACKAGE_NAME,
        sha256_cert_fingerprints: SHA256_FINGERPRINTS,
      },
    },
  ];

  return new NextResponse(JSON.stringify(body, null, 2), {
    status: 200,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "public, max-age=3600",
    },
  });
}
