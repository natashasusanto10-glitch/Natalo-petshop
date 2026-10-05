"use client";

import Image from "next/image";
import { useEffect, useId, useRef, useState } from "react";
import { AppStoreBadge } from "@/components/AppStoreBadge";
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
        className="m-auto max-h-[90dvh] w-[calc(100%-2rem)] max-w-sm overflow-y-auto rounded-2xl border border-zinc-100 bg-white p-6 text-center text-zinc-900 shadow-xl backdrop:bg-black/30">
        <button type="button" onClick={() => setOpen(false)} aria-label="Tutup download app"
          className="absolute right-2 top-2 flex h-10 w-10 items-center justify-center rounded-full text-zinc-500 hover:bg-zinc-100 focus-visible:outline-2 focus-visible:outline-blue-600">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="h-5 w-5" aria-hidden="true"><path d="m6 6 12 12M18 6 6 18" /></svg>
        </button>
        <Image src="/logo.png" alt="Natalo Petshop" width={600} height={196} className="mx-auto mb-5 h-10 w-auto" />
        <h2 id={titleId} className="text-lg font-bold">Download aplikasi Natalo</h2>
        <p className="mt-2 hidden text-sm font-normal leading-relaxed text-zinc-500 sm:block">Scan QR dengan kamera iPhone, lalu download di App Store.</p>
        <p className="mt-2 text-sm font-normal text-zinc-500 sm:hidden">Download langsung melalui App Store.</p>
        <Image src="/assets/app-store-qr.png" alt="QR code download Natalo Petshop di App Store" width={224} height={224} className="mx-auto my-4 hidden h-48 w-48 sm:block" />
        <AppStoreBadge className="mt-5 sm:mt-0" />
        <p className="mt-3 text-xs font-normal text-zinc-500">Tersedia untuk iPhone.</p>
      </dialog>
    </>
  );
}
