"use client";

import Image from "next/image";
import { useEffect, useId, useRef, useState } from "react";
import { AppStoreBadge } from "@/components/AppStoreBadge";
import { PlayStoreBadge } from "@/components/PlayStoreBadge";
import { isCapacitorNative } from "@/lib/native-platform";

export function AppDownloadMenu() {
  const [open, setOpen] = useState(false);
  const [isNative, setIsNative] = useState(false);
  const dialogRef = useRef<HTMLDialogElement>(null);
  const titleId = useId();

  useEffect(() => { setIsNative(isCapacitorNative()); }, []);
  useEffect(() => {
    const dialog = dialogRef.current;
    if (!open || !dialog) return;
    dialog.showModal();
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      dialog.close();
      document.body.style.overflow = previousOverflow;
    };
  }, [open]);

  if (isNative) return null;
  return (
    <>
      <button type="button" onClick={() => setOpen(true)} aria-haspopup="dialog"
        className="inline-flex min-h-9 shrink-0 items-center gap-1.5 whitespace-nowrap text-xs font-semibold hover:underline focus-visible:outline-2 focus-visible:outline-offset-2">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" className="h-3.5 w-3.5" aria-hidden="true">
          <rect x="6" y="2" width="12" height="20" rx="3" /><path d="M10 18h4M10 5h4" />
        </svg>
        Download App
      </button>
      <dialog ref={dialogRef} aria-labelledby={titleId} onClose={() => setOpen(false)}
        onClick={event => {
          if (event.target !== event.currentTarget) return;
          const box = event.currentTarget.getBoundingClientRect();
          if (event.clientX < box.left || event.clientX > box.right || event.clientY < box.top || event.clientY > box.bottom) setOpen(false);
        }}
        className="m-auto max-h-[90dvh] w-[calc(100%-2rem)] max-w-lg overflow-y-auto rounded-2xl border border-zinc-100 bg-white p-6 text-center text-zinc-900 shadow-xl backdrop:bg-black/30">
        <button type="button" onClick={() => setOpen(false)} aria-label="Tutup download app"
          className="absolute right-2 top-2 flex h-10 w-10 items-center justify-center rounded-full text-zinc-500 hover:bg-zinc-100 focus-visible:outline-2 focus-visible:outline-blue-600">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="h-5 w-5" aria-hidden="true"><path d="m6 6 12 12M18 6 6 18" /></svg>
        </button>
        <Image src="/logo.png" alt="Natalo Petshop" width={600} height={196} className="mx-auto mb-5 h-10 w-auto" />
        <h2 id={titleId} className="text-lg font-bold">Download aplikasi Natalo</h2>
        <p className="mt-2 hidden text-sm font-normal leading-relaxed text-zinc-500 sm:block">Scan QR sesuai perangkatmu untuk download aplikasi.</p>
        <p className="mt-2 text-sm font-normal text-zinc-500 sm:hidden">Pilih toko aplikasi sesuai perangkatmu.</p>
        <div className="mt-5 grid gap-5 sm:grid-cols-2 sm:gap-4">
          <div>
            <p className="text-xs font-semibold text-zinc-600">iPhone · App Store</p>
            <Image src="/assets/app-store-qr.png" alt="QR code download Natalo Petshop di App Store" width={224} height={224} className="mx-auto my-3 hidden h-44 w-44 sm:block" />
            <AppStoreBadge className="mt-2 !px-3 sm:mt-0" />
          </div>
          <div>
            <p className="text-xs font-semibold text-zinc-600">Android · Google Play</p>
            <Image src="/assets/play-store-qr.png" alt="QR code download Natalo Petshop di Google Play" width={224} height={224} className="mx-auto my-3 hidden h-44 w-44 sm:block" />
            <PlayStoreBadge className="mt-2 !px-3 sm:mt-0" />
          </div>
        </div>
      </dialog>
    </>
  );
}
