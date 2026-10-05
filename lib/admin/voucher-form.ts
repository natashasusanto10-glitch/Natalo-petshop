export function voucherFormError(values: {
  maxUsage: number | null; usageLimitPerUser: number; code: string; discountPercent: number | null; discountAmount: number | null;
  maxDiscountAmount: number | null; minimumOrder: number; startsAt: Date; expiresAt: Date | null;
}): string | null {
  if (!values.code) return "Kode voucher wajib diisi.";
  if ([values.discountPercent, values.discountAmount, values.maxDiscountAmount, values.minimumOrder, values.maxUsage, values.usageLimitPerUser].some(v => v !== null && (!Number.isSafeInteger(v) || v < 0))) return "Nominal dan persentase harus berupa angka bulat positif.";
  if (values.discountPercent !== null && (values.discountPercent < 1 || values.discountPercent > 100)) return "Diskon persen harus antara 1 dan 100.";
  if (values.discountPercent && values.discountAmount) return "Pilih satu bentuk diskon: persentase atau nominal.";
  if (!values.discountPercent && !values.discountAmount) return "Isi diskon nominal atau persentase lebih dari nol.";
  if (!Number.isFinite(values.startsAt.getTime()) || (values.expiresAt && (!Number.isFinite(values.expiresAt.getTime()) || values.expiresAt <= values.startsAt))) return "Tanggal akhir harus setelah tanggal mulai.";
  return null;
}
