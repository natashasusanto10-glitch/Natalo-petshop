/** Tautan WhatsApp toko; nomor memakai sumber yang sama dengan halaman produk. */
export function chatWhatsAppHref(text?: string): string {
  const phone = (
    process.env.NEXT_PUBLIC_WA_NUMBER ??
    process.env.NEXT_PUBLIC_WHATSAPP_NUMBER ??
    "6281260000000"
  ).replace(/[^\d]/g, "");
  return `https://wa.me/${phone}${text ? `?text=${encodeURIComponent(text)}` : ""}`;
}
