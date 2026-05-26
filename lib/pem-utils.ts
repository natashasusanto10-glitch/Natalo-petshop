/**
 * Normalize PEM private key dari env var ke format yang OpenSSL terima.
 *
 * Vercel env var biasanya disimpan dengan literal `\n` (2 character),
 * tapi browser dashboard kadang strip newline saat paste sehingga value
 * jadi single-line tanpa marker apapun. OpenSSL `crypto.privateDecrypt`
 * / `jose.SignJWT` butuh PEM format proper:
 *
 *   -----BEGIN PRIVATE KEY-----
 *   <base64 body wrapped at 64 char per line>
 *   -----END PRIVATE KEY-----
 *
 * Function ini handle 3 input format:
 *
 *   1. Multi-line PEM (already correct) → trim trailing whitespace, return
 *   2. Single-line dengan literal `\n` (Vercel CLI behavior) →
 *      `replace(/\\n/g, "\n")` → multi-line
 *   3. Single-line tanpa newline marker (Vercel dashboard behavior, paling
 *      sering bikin bug "DECODER routines::unsupported") → extract body,
 *      re-wrap ke 64-char lines
 *
 * Error PEM yang umum:
 *   - `error:1E08010C:DECODER routines::unsupported` — PEM single-line tanpa newline
 *   - `error:0909006C:PEM routines:get_name:no start line` — header missing / corrupted
 *   - `app/invalid-credential` (Firebase Admin) — wrapper around the OpenSSL error
 */
export function normalizePemKey(raw: string): string {
  // Step 1: replace literal `\n` (2 character) ke real newline. No-op kalau
  // sudah real newline.
  let key = raw.replace(/\\n/g, "\n").trim();

  // Step 2: kalau PEM single-line (header + body + footer di 1 baris,
  // tanpa newline antara), auto-wrap. Detection: ada header/footer marker
  // tapi `\n` nyata tidak ada.
  if (
    key.includes("-----BEGIN PRIVATE KEY-----") &&
    key.includes("-----END PRIVATE KEY-----") &&
    !key.includes("\n")
  ) {
    const body = key
      .replace("-----BEGIN PRIVATE KEY-----", "")
      .replace("-----END PRIVATE KEY-----", "")
      .replace(/\s/g, "");
    const wrappedBody = (body.match(/.{1,64}/g) ?? []).join("\n");
    key =
      "-----BEGIN PRIVATE KEY-----\n" +
      wrappedBody +
      "\n-----END PRIVATE KEY-----";
  }

  return key;
}
