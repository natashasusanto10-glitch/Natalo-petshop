export const ORIGIN_AREA_NOT_CONFIGURED_CODE = "ORIGIN_AREA_NOT_CONFIGURED";

export const SHIPPING_ORIGIN_UNAVAILABLE_MESSAGE =
  "Metode pengiriman belum tersedia. Silakan coba beberapa saat lagi atau hubungi admin.";

export const SHIPPING_ORIGIN_UNAVAILABLE_DETAIL =
  "Alamat asal toko belum siap digunakan untuk menghitung ongkir. Silakan coba lagi nanti atau hubungi admin Natalo Petshop.";

export function toCustomerShippingErrorMessage(message: unknown) {
  const text = typeof message === "string" ? message : "";
  if (/SHOP_ORIGIN_AREA_ID|WAREHOUSE_AREA_ID|origin_area_id|origin area/i.test(text)) {
    return SHIPPING_ORIGIN_UNAVAILABLE_MESSAGE;
  }
  return text || "Gagal memuat ongkir, coba lagi.";
}
