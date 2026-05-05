export function WhatsAppButton({ message = "Halo, saya mau tanya produk." }: { message?: string }) {
  const phone = process.env.NEXT_PUBLIC_WHATSAPP_NUMBER || "6281234567890";
  const href = `https://wa.me/${phone}?text=${encodeURIComponent(message)}`;

  return (
    <a
      href={href}
      target="_blank"
      rel="noreferrer"
      className="inline-flex items-center justify-center gap-2 rounded-full border border-gray-200 px-5 py-3 text-sm font-semibold text-gray-700 transition hover:border-green-400 hover:text-green-600"
    >
      💬 Tanya via WhatsApp
    </a>
  );
}
