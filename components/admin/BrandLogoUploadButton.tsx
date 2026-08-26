"use client";

import { useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";

import { uploadAdminImage } from "@/lib/admin-image-upload";

type BrandLogoUploadButtonProps = {
  brandId: string;
  brandName: string;
  logoUrl: string | null;
  updateLogoAction: (brandId: string, logoUrl: string) => Promise<void>;
};

function ImageIcon({ className = "h-5 w-5" }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <rect x="4" y="5" width="16" height="14" rx="3" stroke="currentColor" strokeWidth="1.8" />
      <path
        d="m7 16 3.2-3.2a1.2 1.2 0 0 1 1.7 0L14 15l1.1-1.1a1.2 1.2 0 0 1 1.7 0L19 16"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <circle cx="15.5" cy="9.5" r="1.25" fill="currentColor" />
    </svg>
  );
}

export function BrandLogoUploadButton({
  brandId,
  brandName,
  logoUrl,
  updateLogoAction,
}: BrandLogoUploadButtonProps) {
  const router = useRouter();
  const fileRef = useRef<HTMLInputElement>(null);
  const [previewUrl, setPreviewUrl] = useState(logoUrl);
  const [error, setError] = useState("");
  const [uploading, setUploading] = useState(false);
  const [isPending, startTransition] = useTransition();
  const isBusy = uploading || isPending;

  async function upload(file: File) {
    setError("");
    setUploading(true);

    try {
      // Batas ukuran TIDAK dicek di sini — kompresi jalan dulu, batasnya
      // diperiksa setelahnya. `preserveFormat` wajib: server menjalankan
      // sharp().trim() untuk memotong padding logo, dan artefak JPEG di
      // tepi bikin trim itu meleset.
      const url = await uploadAdminImage(file, {
        fields: { kind: "brand-logo" },
        preserveFormat: true,
      });

      startTransition(() => {
        void updateLogoAction(brandId, url)
          .then(() => {
            setPreviewUrl(url);
            router.refresh();
          })
          .catch(() => {
            setError("Gagal menyimpan logo");
          });
      });
    } catch (e) {
      setError(e instanceof Error ? e.message : "Upload gagal");
    } finally {
      setUploading(false);
    }
  }

  return (
    <div className="shrink-0">
      <button
        type="button"
        onClick={() => fileRef.current?.click()}
        disabled={isBusy}
        className="group flex h-12 w-16 items-center justify-center overflow-hidden rounded-xl border border-zinc-100 bg-white p-2 text-zinc-400 transition hover:border-blue-200 hover:bg-blue-50 hover:text-blue-600 disabled:cursor-wait disabled:opacity-70"
        title={previewUrl ? `Ganti logo ${brandName}` : `Upload logo ${brandName}`}
        aria-label={previewUrl ? `Ganti logo ${brandName}` : `Upload logo ${brandName}`}
      >
        {previewUrl ? (
          <img
            src={previewUrl}
            alt=""
            className="max-h-full max-w-full object-contain transition group-hover:scale-95"
            draggable={false}
          />
        ) : isBusy ? (
          <span className="h-4 w-4 animate-spin rounded-full border-2 border-blue-200 border-t-blue-600" />
        ) : (
          <ImageIcon />
        )}
      </button>
      <input
        ref={fileRef}
        type="file"
        accept="image/jpeg,image/png,image/webp,image/gif"
        className="hidden"
        onChange={(event) => {
          const file = event.target.files?.[0];
          if (file) void upload(file);
          event.target.value = "";
        }}
      />
      {error && <p className="mt-1 max-w-16 text-[10px] font-bold leading-tight text-red-500">{error}</p>}
    </div>
  );
}
