/**
 * Android Digital Asset Links — required oleh Android untuk App Links.
 *
 * URL harus tepat:
 * - https://www.natalopetshop.com/.well-known/assetlinks.json
 * - https://natalopetshop.com/.well-known/assetlinks.json
 *
 * Cara kerja:
 * - User klik link "https://natalopetshop.com/u/asiong" di WhatsApp
 * - Android check assetlinks.json di domain → cocok dengan signature
 *   APK yang ter-install → open app langsung (bukan browser)
 * - Tanpa file ini, link buka di Chrome (default behavior)
 *
 * Format: array of object dengan target.package_name + target.sha256_cert_fingerprints.
 * Reference: https://developers.google.com/digital-asset-links/v1/getting-started
 *
 * SHA-256 fingerprint diambil dari signing cert APK production. Cara
 * dapat fingerprint:
 *   keytool -list -v -keystore <release.keystore> -alias <alias>
 *
 * Atau dari Play Console:
 *   Setup → App integrity → App signing key certificate → SHA-256
 *
 * Set di env var NATALO_ANDROID_SHA256 (uppercase, dengan colon
 * separator format `AA:BB:CC:...`). Multi-fingerprint (debug + release
 * + Play upload key) bisa di-split dengan koma — semua di-include di
 * response.
 */
import { NextResponse } from "next/server";

const PACKAGE_NAME = "com.natalo.petshop";

// Env var: comma-separated SHA-256 fingerprints. Format per item:
// `AA:BB:CC:...` (uppercase, colon-delimited, 32 bytes = 95 chars).
// Multi-value supaya bisa include debug + release + Play upload key
// dalam 1 deploy.
function parseFingerprints(): string[] {
  const raw = process.env.NATALO_ANDROID_SHA256 ?? "";
  return raw
    .split(",")
    .map((s) => s.trim().toUpperCase())
    .filter((s) => /^[A-F0-9:]+$/.test(s) && s.length >= 50);
}

export async function GET() {
  const fingerprints = parseFingerprints();
  const body = fingerprints.length > 0
    ? [
        {
          relation: [
            "delegate_permission/common.handle_all_urls",
            "delegate_permission/common.get_login_creds",
          ],
          target: {
            namespace: "android_app",
            package_name: PACKAGE_NAME,
            sha256_cert_fingerprints: fingerprints,
          },
        },
      ]
    : [];

  return new NextResponse(JSON.stringify(body, null, 2), {
    status: 200,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "public, max-age=3600",
    },
  });
}
