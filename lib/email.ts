/**
 * Email service via Resend.
 *
 * Setup:
 *   1. Daftar di https://resend.com (gratis 3000 email/bulan)
 *   2. Verify domain ATAU pakai sandbox mode (cuma bisa kirim ke email yg di-verify)
 *   3. Set env: RESEND_API_KEY, RESEND_FROM
 *
 * Fallback: kalau RESEND_API_KEY kosong, link reset di-print ke console
 *           (untuk dev tanpa setup email).
 */

import { Resend } from "resend";

const RESEND_API_KEY = process.env.RESEND_API_KEY ?? "";
const RESEND_FROM =
  process.env.RESEND_FROM ?? "Natalo Petshop <onboarding@resend.dev>";
const SITE_URL = process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000";
const BRAND = process.env.NEXT_PUBLIC_BRAND_NAME ?? "Natalo Petshop";

const resend = RESEND_API_KEY ? new Resend(RESEND_API_KEY) : null;

/**
 * Kirim email reset password ke user.
 * Return true kalau sukses, false kalau gagal.
 *
 * NOTE: Selalu return true ke caller (anti email enumeration) — error
 *       di-log internal saja.
 */
export async function sendPasswordResetEmail(params: {
  to: string;
  userName: string;
  token: string;
}): Promise<{ ok: boolean; error?: string }> {
  const { to, userName, token } = params;
  const resetUrl = `${SITE_URL}/member/reset-password?token=${encodeURIComponent(token)}`;

  // ── Dev fallback: tidak ada API key → log saja ───────────────
  if (!resend) {
    console.log("\n" + "=".repeat(60));
    console.log("📧 [DEV MODE] Email reset password");
    console.log("=".repeat(60));
    console.log(`To       : ${to}`);
    console.log(`Halo     : ${userName}`);
    console.log(`Reset URL: ${resetUrl}`);
    console.log(`Expires  : 1 jam`);
    console.log("=".repeat(60));
    console.log("Set RESEND_API_KEY di .env untuk kirim email beneran.\n");
    return { ok: true };
  }

  try {
    const { error } = await resend.emails.send({
      from: RESEND_FROM,
      to: [to],
      subject: `Reset Password ${BRAND}`,
      html: buildResetEmailHtml({ userName, resetUrl }),
      text: buildResetEmailText({ userName, resetUrl }),
    });

    if (error) {
      console.error("[email] Resend API error:", error);
      return { ok: false, error: error.message };
    }
    return { ok: true };
  } catch (e) {
    console.error("[email] Send failed:", e);
    return { ok: false, error: e instanceof Error ? e.message : String(e) };
  }
}

function buildResetEmailHtml({
  userName,
  resetUrl,
}: {
  userName: string;
  resetUrl: string;
}) {
  return `
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>Reset Password</title></head>
<body style="font-family:Arial,sans-serif;line-height:1.6;color:#333;background:#f5f5f5;padding:20px">
  <div style="max-width:560px;margin:0 auto;background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,0.05)">
    <div style="background:#468284;padding:24px;text-align:center;color:white">
      <p style="font-size:32px;margin:0">🐾</p>
      <h1 style="margin:8px 0 0;font-size:22px;font-weight:900">${BRAND}</h1>
    </div>
    <div style="padding:32px">
      <h2 style="margin:0 0 16px;font-size:20px;color:#111">Halo, ${userName}!</h2>
      <p style="margin:0 0 16px">
        Kami menerima permintaan reset password untuk akun kamu di ${BRAND}.
      </p>
      <p style="margin:0 0 24px">
        Klik tombol di bawah untuk membuat password baru:
      </p>
      <div style="text-align:center;margin:32px 0">
        <a href="${resetUrl}" style="display:inline-block;padding:14px 32px;background:#468284;color:white;text-decoration:none;font-weight:bold;border-radius:999px;font-size:14px">
          Reset Password
        </a>
      </div>
      <p style="margin:0 0 8px;font-size:13px;color:#666">
        Atau salin link berikut:
      </p>
      <p style="margin:0 0 24px;font-size:13px;color:#666;word-break:break-all">
        <a href="${resetUrl}" style="color:#468284">${resetUrl}</a>
      </p>
      <div style="border-top:1px solid #eee;padding-top:16px;margin-top:24px;font-size:12px;color:#999">
        <p style="margin:0 0 8px"><strong>⏱️ Link berlaku 1 jam.</strong> Setelah itu kamu harus minta link reset baru.</p>
        <p style="margin:0">Kalau kamu tidak meminta reset password, abaikan email ini. Akun kamu tetap aman.</p>
      </div>
    </div>
  </div>
</body>
</html>
`;
}

function buildResetEmailText({
  userName,
  resetUrl,
}: {
  userName: string;
  resetUrl: string;
}) {
  return `Halo ${userName},

Kami menerima permintaan reset password untuk akun kamu di ${BRAND}.

Klik link berikut untuk membuat password baru:
${resetUrl}

Link berlaku 1 jam. Setelah itu kamu harus minta link reset baru.

Kalau kamu tidak meminta reset password, abaikan email ini.

— ${BRAND}`;
}
