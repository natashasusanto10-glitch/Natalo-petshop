import type { ProductVoucherPreview } from "@/lib/product-vouchers";

type Props = {
  voucherPreview?: ProductVoucherPreview | null;
  shippingVoucherPreview?: ProductVoucherPreview | null;
};

export function ProductVoucherBadges({ voucherPreview, shippingVoucherPreview }: Props) {
  if (!voucherPreview && !shippingVoucherPreview) return null;
  return (
    <div className="mt-2 flex flex-wrap gap-1" data-product-vouchers>
      {[shippingVoucherPreview, voucherPreview].map(voucher => {
        if (!voucher) return null;
        const shipping = voucher.discountScope === "SHIPPING";
        const label = voucher.badgeLabel.trim() || (shipping ? "Gratis Ongkir" : "Voucher produk");
        const details = [voucher.sheetTitle, voucher.sheetSubtitle,
          voucher.targetUser === "NEW_MEMBER" ? "Khusus member baru" : "Voucher member",
          "Syarat berlaku"].join(" · ");
        return (
          <span key={voucher.id} title={details} data-voucher-scope={voucher.discountScope}
            className={`inline-flex max-w-full items-center gap-1 rounded-md border px-1.5 py-1 text-[10px] font-bold leading-tight ${shipping
              ? "border-green-200 bg-green-50 text-green-800"
              : "border-rose-200 bg-rose-50 text-rose-700"}`}>
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"
              className="h-3 w-3 shrink-0" aria-hidden="true">
              {shipping ? <>
                <path d="M3 6h11v11H3zM14 10h4l3 4v3h-7" />
                <circle cx="7" cy="18" r="2" /><circle cx="18" cy="18" r="2" />
              </> : <>
                <path d="M3 6h18v4a2 2 0 0 0 0 4v4H3v-4a2 2 0 0 0 0-4zM9 6v12" />
                <path d="m12 15 5-6M13 9h.01M16 15h.01" strokeLinecap="round" />
              </>}
            </svg>
            <span>{label}</span>
          </span>
        );
      })}
    </div>
  );
}
