import Link from "next/link";

export function AnnouncementBar() {
  const wa = process.env.NEXT_PUBLIC_WHATSAPP_NUMBER || process.env.NEXT_PUBLIC_WA_NUMBER || "";
  const waHref = wa ? `https://wa.me/${wa.replace("+", "")}` : null;

  return (
    <div className="hidden bg-natalo-500 text-white md:block">
      <div className="mx-auto flex max-w-[var(--nat-container)] items-center justify-between gap-4 px-[var(--nat-gutter)] py-1.5 text-xs font-semibold">
        <div className="flex items-center gap-5">
          <span>🚚 Gratis ongkir area Medan</span>
          <span className="opacity-40">•</span>
          <span>✅ 100% Produk Original</span>
        </div>
        {waHref && (
          <Link href={waHref} className="inline-flex items-center gap-1 transition hover:opacity-80">
            💬 Chat admin via WhatsApp
          </Link>
        )}
      </div>
    </div>
  );
}
