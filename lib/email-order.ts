/**
 * Email notifikasi untuk customer saat status order berubah.
 *
 * Skip otomatis kalau:
 *   - Customer tidak punya email (cuma phone)
 *   - RESEND_API_KEY belum dikonfigurasi (dev mode → log ke console)
 *
 * Error tidak block status update — silently log.
 */

import { Resend } from "resend";
import { formatRupiah } from "@/lib/format";

const RESEND_API_KEY = process.env.RESEND_API_KEY ?? "";
const RESEND_FROM =
  process.env.RESEND_FROM ?? "Natalo Petshop <onboarding@resend.dev>";
const SITE_URL = process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000";
const BRAND = process.env.NEXT_PUBLIC_BRAND_NAME ?? "Natalo Petshop";

const resend = RESEND_API_KEY ? new Resend(RESEND_API_KEY) : null;

export interface OrderEmailContext {
  orderNumber: string;
  customerName: string;
  customerEmail: string | null;
  total: number;
  trackingNumber?: string | null;
  courierCode?: string | null;
  courierService?: string | null;
}

type EmailKind = "PAID" | "SHIPPED" | "DELIVERED" | "CANCELLED";

const SUBJECTS: Record<EmailKind, (orderNumber: string) => string> = {
  PAID: (n) => `✅ Pembayaran Diterima — Order ${n}`,
  SHIPPED: (n) => `🚚 Pesanan ${n} Sudah Dikirim!`,
  DELIVERED: (n) => `📦 Pesanan ${n} Sudah Sampai`,
  CANCELLED: (n) => `❌ Pesanan ${n} Dibatalkan`,
};

/**
 * Kirim email status order ke customer.
 * Return true kalau berhasil dikirim (atau di-log di dev mode), false kalau error fatal.
 */
export async function sendOrderStatusEmail(
  kind: EmailKind,
  ctx: OrderEmailContext
): Promise<{ ok: boolean; skipped?: string; error?: string }> {
  // Skip kalau customer tidak punya email
  if (!ctx.customerEmail) {
    return { ok: true, skipped: "no email" };
  }

  const subject = SUBJECTS[kind](ctx.orderNumber);
  const trackingUrl = `${SITE_URL}/order-status?order=${ctx.orderNumber}`;
  const html = buildEmailHtml(kind, ctx, trackingUrl);
  const text = buildEmailText(kind, ctx, trackingUrl);

  // Dev mode fallback
  if (!resend) {
    console.log("\n" + "=".repeat(60));
    console.log(`📧 [DEV MODE] ${subject}`);
    console.log("=".repeat(60));
    console.log(`To       : ${ctx.customerEmail}`);
    console.log(`Order    : ${ctx.orderNumber}`);
    console.log(`Customer : ${ctx.customerName}`);
    if (ctx.trackingNumber) console.log(`Tracking : ${ctx.trackingNumber}`);
    console.log(`URL      : ${trackingUrl}`);
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
      console.error("[email-order] Resend error:", error);
      return { ok: false, error: error.message };
    }
    return { ok: true };
  } catch (e) {
    console.error("[email-order] Send failed:", e);
    return { ok: false, error: e instanceof Error ? e.message : String(e) };
  }
}

// ── Templates ──────────────────────────────────────────────────

function buildEmailHtml(
  kind: EmailKind,
  ctx: OrderEmailContext,
  trackingUrl: string
): string {
  const headerColor = "#1E88E5";
  const headerEmoji = {
    PAID: "✅",
    SHIPPED: "🚚",
    DELIVERED: "📦",
    CANCELLED: "❌",
  }[kind];
  const headerTitle = {
    PAID: "Pembayaran Diterima",
    SHIPPED: "Pesanan Sudah Dikirim",
    DELIVERED: "Pesanan Sudah Sampai",
    CANCELLED: "Pesanan Dibatalkan",
  }[kind];

  const body = buildBodyHtml(kind, ctx);

  return `<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>${headerTitle}</title></head>
<body style="font-family:Arial,sans-serif;line-height:1.6;color:#333;background:#f5f5f5;padding:20px">
  <div style="max-width:560px;margin:0 auto;background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,0.05)">
    <div style="background:${headerColor};padding:24px;text-align:center;color:white">
      <p style="font-size:32px;margin:0">${headerEmoji}</p>
      <h1 style="margin:8px 0 0;font-size:22px;font-weight:900">${BRAND}</h1>
    </div>
    <div style="padding:32px">
      <h2 style="margin:0 0 12px;font-size:20px;color:#111">Halo, ${ctx.customerName}!</h2>
      ${body}

      <div style="text-align:center;margin:32px 0">
        <a href="${trackingUrl}" style="display:inline-block;padding:14px 32px;background:${headerColor};color:white;text-decoration:none;font-weight:bold;border-radius:999px;font-size:14px">
          Lihat Detail Pesanan
        </a>
      </div>

      <div style="border-top:1px solid #eee;padding-top:16px;margin-top:24px;font-size:12px;color:#999">
        <p style="margin:0">Ada pertanyaan? Balas email ini atau hubungi WhatsApp kami.</p>
      </div>
    </div>
  </div>
</body></html>`;
}

function buildBodyHtml(kind: EmailKind, ctx: OrderEmailContext): string {
  const orderRow = `
    <p style="margin:0 0 16px">
      <strong>Nomor Pesanan:</strong> ${ctx.orderNumber}<br>
      <strong>Total:</strong> ${formatRupiah(ctx.total)}
    </p>`;

  if (kind === "PAID") {
    return `
      <p>Pembayaran kamu untuk pesanan kami sudah kami terima ✓</p>
      ${orderRow}
      <p>Pesanan akan segera kami proses dan packing. Kamu akan dapat email lagi saat pesanan dikirim beserta nomor resi.</p>`;
  }

  if (kind === "SHIPPED") {
    const courierLabel = [ctx.courierCode?.toUpperCase(), ctx.courierService]
      .filter(Boolean)
      .join(" — ");
    const tracking = ctx.trackingNumber
      ? `
      <div style="margin:20px 0;padding:16px;background:#EFF6FF;border-radius:12px;border:1px solid #BFDBFE">
        <p style="margin:0 0 8px;font-size:13px;color:#666">Nomor Resi:</p>
        <p style="margin:0;font-family:monospace;font-size:18px;font-weight:bold;color:#1E88E5;letter-spacing:1px">
          ${ctx.trackingNumber}
        </p>
        ${courierLabel ? `<p style="margin:8px 0 0;font-size:12px;color:#999">Kurir: ${courierLabel}</p>` : ""}
      </div>`
      : "";
    return `
      <p>Pesanan kamu sudah kami kirim! 🚚</p>
      ${orderRow}
      ${tracking}
      <p>Kamu bisa cek status pengiriman dengan klik tombol di bawah.</p>`;
  }

  if (kind === "DELIVERED") {
    return `
      <p>Pesanan kamu sudah sampai tujuan 🎉</p>
      ${orderRow}
      <p>Semoga kamu & si peliharaan suka produknya!</p>
      <p style="margin-top:16px;padding:12px;background:#fef3c7;border-radius:8px;font-size:14px">
        ⭐ <strong>Yuk kasih review!</strong> Klik tombol di bawah untuk membantu pembeli lain.
      </p>`;
  }

  // CANCELLED
  return `
    <p>Pesanan kamu telah dibatalkan.</p>
    ${orderRow}
    <p>Kalau kamu sudah transfer, mohon tunggu refund dalam 1-3 hari kerja, atau hubungi admin via WhatsApp untuk konfirmasi.</p>
    <p style="margin-top:16px;font-size:13px;color:#666">Kalau pembatalan ini tidak sengaja atau tidak diminta dari sisimu, segera hubungi admin.</p>`;
}

function buildEmailText(
  kind: EmailKind,
  ctx: OrderEmailContext,
  trackingUrl: string
): string {
  const lines = [
    `Halo ${ctx.customerName},`,
    "",
    {
      PAID: "Pembayaran kamu sudah kami terima.",
      SHIPPED: "Pesanan kamu sudah kami kirim.",
      DELIVERED: "Pesanan kamu sudah sampai tujuan.",
      CANCELLED: "Pesanan kamu telah dibatalkan.",
    }[kind],
    "",
    `Nomor Pesanan: ${ctx.orderNumber}`,
    `Total: ${formatRupiah(ctx.total)}`,
  ];
  if (kind === "SHIPPED" && ctx.trackingNumber) {
    lines.push(`Nomor Resi: ${ctx.trackingNumber}`);
    if (ctx.courierCode) {
      lines.push(`Kurir: ${ctx.courierCode.toUpperCase()} ${ctx.courierService ?? ""}`);
    }
  }
  lines.push("", `Detail pesanan: ${trackingUrl}`, "", `— ${BRAND}`);
  return lines.join("\n");
}
