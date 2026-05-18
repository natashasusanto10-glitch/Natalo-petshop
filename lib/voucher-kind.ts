export type VoucherKindValue =
  | "PRODUCT_DISCOUNT"
  | "FREE_SHIPPING"
  | "LOYALTY_CLAIM"
  | "MANUAL_PRIVATE";

export type VoucherSourceTypeValue = "CUSTOMER" | "SELLER_MANUAL";
export type VoucherSlotValue = "product" | "shipping" | "loyalty" | "manual";
export type VoucherTargetUserValue = "ALL_MEMBERS" | "NEW_MEMBER";

export const ADMIN_CREATABLE_VOUCHER_KINDS: VoucherKindValue[] = [
  "PRODUCT_DISCOUNT",
  "FREE_SHIPPING",
  "MANUAL_PRIVATE",
];

export function isAdminCreatableVoucherKind(
  kind: string,
): kind is Exclude<VoucherKindValue, "LOYALTY_CLAIM"> {
  return ADMIN_CREATABLE_VOUCHER_KINDS.includes(kind as VoucherKindValue);
}

export function deriveVoucherSourceType(
  kind: VoucherKindValue,
): VoucherSourceTypeValue {
  return kind === "MANUAL_PRIVATE" ? "SELLER_MANUAL" : "CUSTOMER";
}

export function isFreeShippingVoucher(voucher: { kind?: string | null }) {
  return voucher.kind === "FREE_SHIPPING";
}

export function isLoyaltyClaimVoucher(voucher: {
  kind?: string | null;
  userId?: string | null;
  code?: string | null;
}) {
  return (
    voucher.kind === "LOYALTY_CLAIM" ||
    Boolean(voucher.userId) ||
    Boolean(voucher.code?.startsWith("POIN-"))
  );
}

export function voucherKindLabel(kind?: string | null) {
  switch (kind) {
    case "FREE_SHIPPING":
      return "Gratis Ongkir";
    case "LOYALTY_CLAIM":
      return "Claim Loyalty Point";
    case "MANUAL_PRIVATE":
      return "Manual / Private";
    case "PRODUCT_DISCOUNT":
    default:
      return "Diskon Produk";
  }
}

export function voucherKindDescription(kind?: string | null) {
  switch (kind) {
    case "FREE_SHIPPING":
      return "Voucher member untuk semua user, memberi potongan ongkir saat checkout.";
    case "LOYALTY_CLAIM":
      return "Voucher otomatis dari penukaran loyalty point user. Admin tidak membuat tipe ini.";
    case "MANUAL_PRIVATE":
      return "Voucher rahasia dari admin/penjual, hanya bisa dipakai lewat input kode manual.";
    case "PRODUCT_DISCOUNT":
    default:
      return "Voucher member untuk semua user, memberi diskon produk/subtotal.";
  }
}

export function voucherTargetUserLabel(targetUser?: string | null) {
  return targetUser === "NEW_MEMBER" ? "Member Baru" : "Semua Member";
}

export function voucherBenefitText(input: {
  kind?: string | null;
  discount?: number | null;
  discountPercent?: number | null;
  discountAmount?: number | null;
  maxDiscountAmount?: number | null;
}) {
  if (isFreeShippingVoucher(input)) return "Gratis ongkir";
  if (typeof input.discount === "number" && input.discount > 0) {
    return `Hemat Rp${new Intl.NumberFormat("id-ID").format(input.discount)}`;
  }
  if (input.discountPercent && input.discountPercent > 0) {
    const cap =
      input.maxDiscountAmount && input.maxDiscountAmount > 0
        ? ` hingga Rp${new Intl.NumberFormat("id-ID").format(input.maxDiscountAmount)}`
        : "";
    return `Diskon ${input.discountPercent}%${cap}`;
  }
  if (input.discountAmount && input.discountAmount > 0) {
    return `Diskon Rp${new Intl.NumberFormat("id-ID").format(input.discountAmount)}`;
  }
  return voucherKindLabel(input.kind);
}

export function voucherSlotForKind(kind?: string | null): VoucherSlotValue {
  switch (kind) {
    case "FREE_SHIPPING":
      return "shipping";
    case "LOYALTY_CLAIM":
      return "loyalty";
    case "MANUAL_PRIVATE":
      return "manual";
    case "PRODUCT_DISCOUNT":
    default:
      return "product";
  }
}

export function collectOrderVoucherCodes(order: {
  voucherCode?: string | null;
  freeShippingVoucherCode?: string | null;
  productVoucherCode?: string | null;
  shippingVoucherCode?: string | null;
  loyaltyVoucherCode?: string | null;
  manualVoucherCode?: string | null;
  privateVoucherCode?: string | null;
}) {
  return [...new Set([
    order.voucherCode,
    order.freeShippingVoucherCode,
    order.productVoucherCode,
    order.shippingVoucherCode,
    order.loyaltyVoucherCode,
    order.manualVoucherCode,
    order.privateVoucherCode,
  ].filter((code): code is string => Boolean(code)))];
}
