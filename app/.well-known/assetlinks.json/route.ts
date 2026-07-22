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
 * Bisa >1 fingerprint (mis. Play signing key + upload key) — tambahkan saja
 * ke array SHA256_FINGERPRINTS.
 *
 * Fingerprint di bawah = App signing key certificate SHA-256 dari Play
 * Console → App integrity, untuk package com.natalo.petshop (app Flutter
 * native, BUKAN keystore Capacitor lama). Diambil user 2026-07-22.
 */
import { NextResponse } from "next/server";

const PACKAGE_NAME = "com.natalo.petshop";

const SHA256_FINGERPRINTS = [
  "B3:07:D9:B5:2C:4A:C8:DD:60:A6:25:3C:DF:E4:36:B3:99:60:DB:E5:C8:A7:AE:EE:1A:5A:07:70:28:D8:19:50",
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
