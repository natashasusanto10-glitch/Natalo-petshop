"use client";

import Image from "next/image";
import { useRef, useState } from "react";
import { FiArrowRight, FiCopy, FiImage, FiMaximize2 } from "react-icons/fi";
import { AdminDialog } from "@/components/admin/ui/AdminDialog";
import { Button, useAdminToast } from "@/components/admin/ui";
import { formatRupiah } from "@/lib/format";

export function CopySku({ sku }: { sku: string }) {
  const { show } = useAdminToast();
  return (
    <button type="button" className="od-copy" aria-label={`Salin SKU ${sku}`} title="Salin SKU"
      onClick={async () => {
        try {
          await navigator.clipboard.writeText(sku);
          show("SKU berhasil disalin");
        } catch {
          show("SKU belum dapat disalin. Pilih teks SKU untuk menyalinnya secara manual.", "error");
        }
      }}>
      <FiCopy aria-hidden="true" />
    </button>
  );
}

export function OrderProductImage({ src, name }: { src: string | null; name: string }) {
  const [failedSrc, setFailedSrc] = useState<string | null>(null);
  return (
    <div className="od-product-image">
      {src && src !== failedSrc ? (
        <Image src={src} alt={name} width={80} height={80} unoptimized onError={() => setFailedSrc(src)} />
      ) : <FiImage role="img" aria-label="Foto produk tidak tersedia" />}
    </div>
  );
}

export function OrderPaymentProof({ url, fontClassName }: { url: string; fontClassName: string }) {
  const [open, setOpen] = useState(false);
  const [motion, setMotion] = useState(true);
  return (
    <>
      <button type="button" className="od-proof-preview" onClick={event => { setMotion(event.detail > 0); setOpen(true); }}>
        <Image src={url} alt="Bukti transfer pelanggan. Buka untuk memperbesar." width={600} height={600} unoptimized />
        <span><FiMaximize2 aria-hidden="true" /> Perbesar bukti transfer</span>
      </button>
      <p className="od-proof-note">Periksa mutasi rekening sebelum mengonfirmasi pembayaran.</p>
      <AdminDialog open={open} title="Bukti transfer" onClose={() => setOpen(false)} motion={motion} onKeyDown={() => setMotion(false)}
        className={`${fontClassName} od-proof-dialog`}
        footer={<Button type="button" variant="secondary" onClick={() => setOpen(false)}>Tutup</Button>}>
        <Image src={url} alt="Bukti transfer pelanggan" width={1000} height={1400} unoptimized className="od-proof-full" />
        <a href={url} target="_blank" rel="noreferrer" className="od-proof-original">Buka gambar asli di tab baru</a>
      </AdminDialog>
    </>
  );
}

export function ConfirmOrderPayment({ action, amount, orderNumber, manual, fontClassName }: {
  action: () => Promise<void>; amount: number; orderNumber: string; manual: boolean; fontClassName: string;
}) {
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [motion, setMotion] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const inFlight = useRef(false);
  const { show } = useAdminToast();
  async function confirm() {
    if (inFlight.current) return;
    inFlight.current = true; setBusy(true); setError(null);
    try {
      await action();
      setOpen(false); show("Pembayaran berhasil dikonfirmasi");
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Pembayaran belum dapat dikonfirmasi. Coba lagi.");
    } finally {
      inFlight.current = false; setBusy(false);
    }
  }
  return (
    <>
      <Button type="button" onClick={event => { setMotion(event.detail > 0); setError(null); setOpen(true); }}>
        Konfirmasi pembayaran <FiArrowRight aria-hidden="true" />
      </Button>
      <AdminDialog open={open} title="Konfirmasi pembayaran?" motion={motion} busy={busy} onKeyDown={() => setMotion(false)}
        onClose={() => { if (!busy) setOpen(false); }} className={`${fontClassName} od-payment-dialog`}
        footer={<>
          <Button type="button" variant="secondary" data-dialog-autofocus onClick={() => setOpen(false)} disabled={busy}>Batal</Button>
          <Button type="button" onClick={confirm} disabled={busy} aria-busy={busy}>{busy ? "Memproses…" : "Ya, pembayaran diterima"}</Button>
        </>}>
        <p>Pesanan <strong>{orderNumber}</strong></p>
        <div className="od-dialog-amount"><span>{manual ? "Nominal transfer yang harus masuk" : "Nominal pembayaran"}</span><strong>{formatRupiah(amount)}</strong></div>
        <p>{manual ? "Pastikan dana sudah masuk di mutasi rekening. Foto bukti transfer saja belum memastikan pembayaran diterima." : "Pastikan pembayaran sudah diterima dan cocokkan dengan status transaksi penyedia pembayaran."}</p>
        {error && <p role="alert" className="od-action-error">{error}</p>}
      </AdminDialog>
    </>
  );
}

export function InspectOrderItems() {
  return <Button type="button" variant="secondary" onClick={event => {
    const target = document.getElementById("order-items-title");
    target?.scrollIntoView({ block: "start", behavior: event.detail === 0 || matchMedia("(prefers-reduced-motion: reduce)").matches ? "instant" : "smooth" });
    target?.focus({ preventScroll: true });
  }}>Periksa barang</Button>;
}
