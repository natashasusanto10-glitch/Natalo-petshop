/**
 * Label status pesanan / pembayaran / review — SATU sumber kebenaran.
 *
 * Sebelumnya tiap halaman (orders list, orders/[id], print, reviews)
 * mendefinisikan ulang peta label + kadang membocorkan enum Inggris mentah
 * ("VISIBLE/HIDDEN", "PENDING") ke UI, plus tidak seragam ("Menunggu" vs
 * "Menunggu verifikasi"). Impor dari sini + render lewat komponen Badge
 * (warna) supaya konsisten otomatis.
 */

export const ORDER_STATUS_LABEL: Record<string, string> = {
  PENDING: "Order Baru",
  PAID: "Sudah Dibayar",
  PROCESSING: "Diproses",
  READY_FOR_PICKUP: "Siap Diambil",
  SHIPPED: "Dikirim",
  DELIVERED: "Selesai",
  CANCELLED: "Dibatalkan",
  REFUNDED: "Refund",
  // Filter turunan di daftar order (bukan status nyata di DB).
  NEED_PACKING: "Siap packing",
};

export const PAYMENT_STATUS_LABEL: Record<string, string> = {
  WAITING: "Menunggu bayar",
  UNPAID: "Belum bayar",
  // Kanonik: manual transfer perlu diverifikasi admin.
  PENDING: "Menunggu verifikasi",
  PAID: "Lunas",
  FAILED: "Gagal",
  EXPIRED: "Kedaluwarsa",
  REFUNDED: "Refund",
};

export const REVIEW_STATUS_LABEL: Record<string, string> = {
  VISIBLE: "Tampil",
  HIDDEN: "Disembunyikan",
  PENDING: "Menunggu",
  FLAGGED: "Dilaporkan",
  REMOVED: "Dihapus",
};

export function orderStatusLabel(status: string | null | undefined): string {
  if (!status) return "-";
  return ORDER_STATUS_LABEL[status] ?? status;
}

export function paymentStatusLabel(status: string | null | undefined): string {
  if (!status) return "-";
  return PAYMENT_STATUS_LABEL[status] ?? status;
}

export function reviewStatusLabel(status: string | null | undefined): string {
  if (!status) return "-";
  return REVIEW_STATUS_LABEL[status] ?? status;
}
