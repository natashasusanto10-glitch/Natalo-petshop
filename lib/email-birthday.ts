/**
 * Email "Selamat Ulang Tahun" + voucher code untuk customer.
 *
 * Backup channel kalau push notif gagal (user offline, FCM token expired,
 * uninstall app sementara). Email tetap masuk inbox, voucher tetap bisa
 * di-claim saat user buka app lagi.
 *
 * Dipanggil dari lib/birthday-voucher.ts setelah voucher sukses di-issue.
 * Fire-and-forget — kalau email service down, voucher tetap valid di DB,
 * user akan lihat saat buka app.
 */

import { Resend } from "resend";

const RESEND_API_KEY = process.env.RESEND_API_KEY ?? "";
const RESEND_FROM =
  process.env.RESEND_FROM ?? "Natalo Petshop <onboarding@resend.dev>";
const SITE_URL = process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000";
const BRAND = process.env.NEXT_PUBLIC_BRAND_NAME ?? "Natalo Petshop";

const resend = RESEND_API_KEY ? new Resend(RESEND_API_KEY) : null;

export interface BirthdayEmailContext {
  customerName: string;
  customerEmail: string | null;
  voucherCode: string;
  discountAmount: number;
  minimumOrder: number;
  expiresAt: Date;
}

function formatRupiah(n: number): string {
  return `Rp${new Intl.NumberFormat("id-ID").format(Math.round(n))}`;
}

function formatExpiry(date: Date): string {
  const months = [
    "Januari", "Februari", "Maret", "April", "Mei", "Juni",
    "Juli", "Agustus", "September", "Oktober", "November", "Desember",
  ];
  return `${date.getDate()} ${months[date.getMonth()]} ${date.getFullYear()}`;
}

export async function sendBirthdayVoucherEmail(
  ctx: BirthdayEmailContext,
): Promise<{ ok: boolean; skipped?: string; error?: string }> {
  if (!ctx.customerEmail) {
    return { ok: true, skipped: "no email" };
  }

  const firstName = (ctx.customerName.split(" ")[0] || "").trim() || "Sahabat";
  const subject = `🎂 Selamat Ulang Tahun, ${firstName}!`;
  const html = buildHtml(ctx, firstName);
  const text = buildText(ctx, firstName);

  // Dev mode fallback — log instead of sending.
  if (!resend) {
    console.log("\n" + "=".repeat(60));
    console.log(`📧 [DEV MODE] ${subject}`);
    console.log("=".repeat(60));
    console.log(`To       : ${ctx.customerEmail}`);
    console.log(`Voucher  : ${ctx.voucherCode}`);
    console.log(`Amount   : ${formatRupiah(ctx.discountAmount)}`);
    console.log(`Expires  : ${formatExpiry(ctx.expiresAt)}`);
    console.log("=".repeat(60) + "\n");
    return { ok: true, skipped: "dev mode (no RESEND_API_KEY)" };
  }

  try {
    const { error } = await resend.emails.send({
      from: RESEND_FROM,
      to: [ctx.customerEmail],
      subject,
      html,
      text,
    });
    if (error) {
      console.error("[email-birthday] Resend error:", error);
      return { ok: false, error: String(error) };
    }
    return { ok: true };
  } catch (err) {
    console.error("[email-birthday] send failed:", err);
    return { ok: false, error: err instanceof Error ? err.message : String(err) };
  }
}

function buildHtml(ctx: BirthdayEmailContext, firstName: string): string {
  const amount = formatRupiah(ctx.discountAmount);
  const minOrder = formatRupiah(ctx.minimumOrder);
  const expiry = formatExpiry(ctx.expiresAt);
  return `<!doctype html>
<html lang="id">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"></head>
<body style="margin:0;padding:0;background:#FEF3C7;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="padding:40px 20px;background:#FEF3C7;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;background:#fff;border-radius:24px;overflow:hidden;box-shadow:0 4px 24px rgba(180,83,9,0.15);">

        <!-- Hero -->
        <tr><td style="background:linear-gradient(135deg,#FBBF24,#F59E0B);padding:40px 24px;text-align:center;">
          <div style="font-size:56px;line-height:1;margin-bottom:8px;">🎂</div>
          <h1 style="margin:0;color:#fff;font-size:24px;font-weight:900;letter-spacing:-0.5px;">
            Selamat Ulang Tahun,<br>${firstName}!
          </h1>
          <p style="margin:8px 0 0 0;color:#FEF3C7;font-size:14px;font-weight:600;">
            Hadiah special dari ${BRAND}
          </p>
        </td></tr>

        <!-- Voucher card -->
        <tr><td style="padding:32px 24px;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#FFFBEB;border:2px dashed #FBBF24;border-radius:16px;padding:24px;">
            <tr><td align="center">
              <p style="margin:0;color:#92400E;font-size:11px;font-weight:900;letter-spacing:1.5px;text-transform:uppercase;">
                Voucher Diskon
              </p>
              <p style="margin:8px 0 0 0;color:#17202A;font-size:36px;font-weight:900;letter-spacing:-1px;">
                ${amount}
              </p>
              <p style="margin:4px 0 0 0;color:#6B7280;font-size:12px;font-weight:600;">
                Min. belanja ${minOrder}
              </p>
              <div style="margin:16px 0;border-top:1px solid #FCD34D;"></div>
              <p style="margin:0;color:#6B7280;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:1px;">
                Kode Voucher
              </p>
              <p style="margin:6px 0 0 0;font-family:'Courier New',monospace;color:#17202A;font-size:18px;font-weight:900;letter-spacing:2px;">
                ${ctx.voucherCode}
              </p>
              <p style="margin:8px 0 0 0;color:#B45309;font-size:11px;font-weight:700;">
                Berlaku sampai ${expiry}
              </p>
            </td></tr>
          </table>
        </td></tr>

        <!-- CTA -->
        <tr><td style="padding:0 24px 32px 24px;text-align:center;">
          <a href="${SITE_URL}" style="display:inline-block;background:#1E5FBF;color:#fff;text-decoration:none;font-weight:900;font-size:14px;padding:14px 32px;border-radius:999px;">
            Belanja Sekarang →
          </a>
          <p style="margin:16px 0 0 0;color:#6B7280;font-size:12px;font-weight:600;line-height:1.5;">
            Voucher otomatis tersedia di akunmu.<br>
            Buka app ${BRAND} → Voucher.
          </p>
        </td></tr>

        <!-- Footer -->
        <tr><td style="padding:20px 24px;background:#F9FAFB;text-align:center;border-top:1px solid #E5E7EB;">
          <p style="margin:0;color:#9CA3AF;font-size:11px;font-weight:600;line-height:1.6;">
            Email ini dikirim otomatis oleh ${BRAND} karena kamu menerima<br>
            voucher ulang tahun. Tidak perlu balas email ini.
          </p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;
}

function buildText(ctx: BirthdayEmailContext, firstName: string): string {
  return `Selamat Ulang Tahun, ${firstName}!

Hadiah special dari ${BRAND}:
🎁 Voucher Diskon ${formatRupiah(ctx.discountAmount)}
   Min. belanja ${formatRupiah(ctx.minimumOrder)}
   Berlaku sampai ${formatExpiry(ctx.expiresAt)}

Kode Voucher: ${ctx.voucherCode}

Voucher otomatis tersedia di akunmu. Buka app ${BRAND} → Voucher.

Belanja: ${SITE_URL}

—
${BRAND}`;
}
