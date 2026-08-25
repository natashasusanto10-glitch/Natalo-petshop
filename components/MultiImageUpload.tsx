"use client";

import { useEffect, useRef, useState } from "react";

interface Props {
  /** Nama field hidden input untuk submit. Akan kirim 1 input per gambar. */
  name: string;
  /** Default URL gambar yg sudah ada saat edit. Index 0 = thumbnail utama. */
  defaultValue?: string[];
  label?: string;
  /** Maksimum jumlah gambar. Default 9. */
  max?: number;
  /**
   * Optional callback yang fire setiap kali list URL berubah. Dipakai
   * client form yang submit via fetch (bukan form action) — supaya
   * parent bisa baca state image. Tanpa ini, component tetap berfungsi
   * via hidden inputs (dipakai oleh form server action lama).
   */
  onChange?: (urls: string[]) => void;
}

const MAX_SIZE_MB = 2;
/** Resize foto > 1600px ke 1600px maks (cukup untuk produk display). */
const MAX_DIMENSION = 1600;
/** Quality JPEG compression — 0.85 = sweet spot quality vs size. */
const JPEG_QUALITY = 0.85;
/**
 * Batas upload paralel. Dulu SEMUA file ditembak sekaligus (6 foto = 6
 * request serentak); tiap request menjalankan getSession() ke Postgres +
 * panggilan ke UploadThing, jadi batch 6 rutin menguras koneksi DB /
 * kena throttle dan sebagian foto gagal — padahal ukurannya jauh di bawah
 * 2 MB. Ukuran file tidak pernah jadi penyebabnya; jumlah request serentak
 * yang jadi penyebab.
 */
const UPLOAD_CONCURRENCY = 2;
/** Jeda sebelum percobaan ulang untuk kegagalan sementara. */
const UPLOAD_RETRY_DELAY_MS = 800;

/** Error upload yang tahu apakah percobaan ulang masuk akal. */
class UploadError extends Error {
  readonly retriable: boolean;
  constructor(message: string, retriable: boolean) {
    super(message);
    this.name = "UploadError";
    this.retriable = retriable;
  }
}

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Worker pool sederhana: jalankan `task` untuk tiap item, maks `limit`
 * berjalan bersamaan. Hasil sejajar urutan input (index-stable), bentuknya
 * sama seperti Promise.allSettled supaya pemanggil tidak perlu berubah.
 */
async function runWithConcurrency<T, R>(
  items: T[],
  limit: number,
  task: (item: T) => Promise<R>,
): Promise<PromiseSettledResult<R>[]> {
  const results = new Array<PromiseSettledResult<R>>(items.length);
  let cursor = 0;

  async function worker() {
    while (cursor < items.length) {
      const index = cursor++;
      try {
        results[index] = { status: "fulfilled", value: await task(items[index]) };
      } catch (reason) {
        results[index] = { status: "rejected", reason };
      }
    }
  }

  await Promise.all(
    Array.from({ length: Math.min(limit, items.length) }, () => worker()),
  );
  return results;
}

/** POST satu file ke /api/admin/upload, kembalikan URL hasilnya. */
async function postImage(file: File, displayName: string): Promise<string> {
  const fd = new FormData();
  fd.append("file", file);

  let res: Response;
  try {
    res = await fetch("/api/admin/upload", { method: "POST", body: fd });
  } catch {
    // Jaringan putus/timeout — belum tentu server menolak, layak diulang.
    throw new UploadError(`Gagal upload "${displayName}" — jaringan bermasalah`, true);
  }

  if (!res.ok) {
    const data = await res.json().catch(() => null);
    // 4xx = permintaan memang ditolak (format salah, > 2 MB, sesi habis) →
    // mengulang tidak akan menolong. 5xx/429 = server sibuk (koneksi DB
    // habis, UploadThing throttle) → justru kasus yang layak diulang.
    const retriable = res.status >= 500 || res.status === 429;
    throw new UploadError(data?.error || `Gagal upload "${displayName}"`, retriable);
  }

  return String((await res.json()).url);
}

/**
 * Cek apakah gambar punya piksel transparan.
 *
 * Penting untuk PNG: foto produk PNG (mis. 1,7 MB) kalau di-encode ulang
 * jadi PNG nyaris tidak mengecil karena PNG itu lossless — hasilnya lolos
 * `blob.size >= file.size` dan file asli yang dikirim. Konversi ke JPEG
 * memangkasnya ke ratusan KB. Tapi JPEG tidak punya alpha, jadi area
 * transparan akan jadi hitam — makanya konversi hanya untuk yang opaque.
 *
 * Kalau pembacaan piksel gagal, anggap saja transparan (pertahankan PNG) —
 * lebih baik file besar daripada gambar rusak.
 */
function hasTransparency(ctx: CanvasRenderingContext2D, w: number, h: number): boolean {
  try {
    const { data } = ctx.getImageData(0, 0, w, h);
    for (let i = 3; i < data.length; i += 4) {
      if (data[i] < 255) return true;
    }
    return false;
  } catch {
    return true;
  }
}

/**
 * Compress + resize image di client sebelum upload supaya:
 * - Ukuran file lebih kecil → upload lebih cepat & tidak membebani route
 * - Dimensi max 1600px (cukup untuk display produk, retina-OK)
 * - PNG opaque dikonversi ke JPEG (hemat besar); PNG transparan tetap PNG;
 *   GIF dilewati (preserve animation).
 *
 * Return: File baru (compressed) atau original kalau tidak bisa compress.
 */
async function compressImage(file: File): Promise<File> {
  // Skip compression untuk GIF (preserve animation) dan file <300KB
  // (sudah cukup kecil, compression overhead tidak worth it).
  if (file.type === "image/gif") return file;
  if (file.size < 300 * 1024) return file;

  try {
    const bitmap = await createImageBitmap(file);
    const ratio = Math.min(
      MAX_DIMENSION / bitmap.width,
      MAX_DIMENSION / bitmap.height,
      1, // jangan upscale
    );
    const targetW = Math.round(bitmap.width * ratio);
    const targetH = Math.round(bitmap.height * ratio);

    const canvas = document.createElement("canvas");
    canvas.width = targetW;
    canvas.height = targetH;
    const ctx = canvas.getContext("2d");
    if (!ctx) {
      bitmap.close();
      return file;
    }
    ctx.drawImage(bitmap, 0, 0, targetW, targetH);
    bitmap.close();

    // Hanya pertahankan PNG kalau memang butuh alpha — selain itu ke JPEG.
    const keepPng = file.type === "image/png" && hasTransparency(ctx, targetW, targetH);
    const outType = keepPng ? "image/png" : "image/jpeg";
    const quality = keepPng ? undefined : JPEG_QUALITY;

    const blob = await new Promise<Blob | null>((resolve) => {
      canvas.toBlob(resolve, outType, quality);
    });
    if (!blob) return file;

    // Hanya pakai compressed kalau memang lebih kecil dari original.
    if (blob.size >= file.size) return file;

    const newName = keepPng
      ? file.name
      : file.name.replace(/\.(png|webp|jpeg)$/i, ".jpg");
    return new File([blob], newName, { type: outType });
  } catch {
    // Compression error (unsupported codec, dst.) → fallback ke original
    return file;
  }
}

/**
 * Upload satu file dengan satu kali percobaan ulang untuk kegagalan
 * sementara. `prepare` (kompresi) hanya dijalankan sekali — percobaan ulang
 * memakai hasil yang sama, tidak kompres dua kali.
 *
 * Batas 2 MB dicek SETELAH kompresi, bukan sebelum: foto 4 MB yang menyusut
 * ke 400 KB seharusnya lolos, bukan ditolak mentah-mentah.
 */
async function uploadOne(
  file: File,
  prepare?: (f: File) => Promise<File>,
): Promise<string> {
  const processed = prepare ? await prepare(file) : file;
  if (processed.size > MAX_SIZE_MB * 1024 * 1024) {
    const mb = (processed.size / (1024 * 1024)).toFixed(1);
    throw new UploadError(
      `"${file.name}" ${mb} MB — melebihi batas ${MAX_SIZE_MB} MB`,
      false,
    );
  }
  try {
    return await postImage(processed, file.name);
  } catch (e) {
    if (!(e instanceof UploadError) || !e.retriable) throw e;
    await sleep(UPLOAD_RETRY_DELAY_MS);
    return postImage(processed, file.name);
  }
}

/**
 * Kabar satu file selesai — dipakai UI untuk mengisi slot skeleton satu per satu.
 * `index` = posisi file pada daftar yang dikirim, BUKAN urutan selesainya.
 * UI wajib memakai index ini supaya urutan foto (dan cover) tidak teracak saat
 * file kecil selesai lebih dulu dari file besar.
 */
export type UploadSettled = { index: number; name: string; url?: string; error?: string };

/**
 * Upload sekumpulan file foto produk. Dipakai ProductMediaRail (form produk
 * admin). Sekarang ikut kompresi — sebelumnya jalur ini mengirim file mentah,
 * jadi 6 PNG @1,7 MB berangkat apa adanya dan rutin gagal sebagian.
 *
 * `onSettled` dipanggil begitu SATU file tuntas (berhasil atau gagal), bukan
 * menunggu seluruh batch. Ini yang membuat foto bisa muncul satu per satu
 * menggantikan skeleton — kalau menunggu semua, layar diam lama lalu 6 foto
 * muncul sekaligus.
 *
 * `failed` = nama file yang gagal (dipertahankan untuk pemanggil lama),
 * `errors` = pesan siap-tampil dengan alasannya.
 */
export async function uploadProductImageFiles(
  files: File[],
  remaining: number,
  onSettled?: (settled: UploadSettled) => void,
): Promise<{ uploaded: string[]; failed: string[]; errors: string[] }> {
  const incoming = files.slice(0, Math.max(0, remaining));

  // Hasil disimpan per-index, bukan di-push saat selesai: dengan paralel 2,
  // file kecil bisa tuntas lebih dulu dari file besar. Kalau di-push apa
  // adanya, urutan foto (dan foto COVER) ikut teracak.
  const urlAt = new Array<string | undefined>(incoming.length);
  const errorAt = new Array<string | undefined>(incoming.length);

  await runWithConcurrency(
    incoming.map((file, index) => ({ file, index })),
    UPLOAD_CONCURRENCY,
    async ({ file, index }) => {
      try {
        const url = await uploadOne(file, compressImage);
        urlAt[index] = url;
        onSettled?.({ index, name: file.name, url });
      } catch (e) {
        const error = e instanceof Error ? e.message : `Gagal upload "${file.name}"`;
        errorAt[index] = error;
        onSettled?.({ index, name: file.name, error });
      }
    },
  );

  const uploaded: string[] = [];
  const failed: string[] = [];
  const errors: string[] = [];
  incoming.forEach((file, index) => {
    const url = urlAt[index];
    if (url) {
      uploaded.push(url);
      return;
    }
    failed.push(file.name);
    errors.push(errorAt[index] ?? `Gagal upload "${file.name}"`);
  });

  return { uploaded, failed, errors };
}

/**
 * Upload 1–{max} gambar ke UploadThing via /api/admin/upload.
 * - Gambar pertama jadi thumbnail utama (akan disimpan ke product.imageUrl).
 * - Sisa gambar masuk ke product.gallery (dipakai di carousel detail).
 * - Tiap gambar maks 2 MB.
 * - Upload paralel TERBATAS ({UPLOAD_CONCURRENCY} sekaligus) + kompresi
 *   client supaya cepat tanpa membanjiri route upload.
 * - Support drag & drop reorder antar slot (HTML5 native).
 *
 * Performance:
 *  - Sequential 6 foto @ 2s = 12s → 2 paralel = ~6s, dan tidak lagi
 *    bikin sebagian foto gagal seperti saat 6 request ditembak serentak.
 *  - Compression 2MB JPG (2000x2000) → ~400KB WebP (1600x1600 q=0.85)
 *    = upload bandwidth turun ~80% → total upload 3-5x faster
 */
export function MultiImageUpload({
  name,
  defaultValue = [],
  label = "Gambar produk",
  max = 9,
  onChange,
}: Props) {
  const [urls, setUrls] = useState<string[]>(defaultValue);
  const [uploadingCount, setUploadingCount] = useState(0);
  const [error, setError] = useState("");
  const [dragIndex, setDragIndex] = useState<number | null>(null);
  const [dragOverIndex, setDragOverIndex] = useState<number | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    onChange?.(urls);
  }, [urls, onChange]);

  async function handleFiles(files: FileList) {
    setError("");
    if (urls.length >= max) {
      setError(`Maksimal ${max} gambar.`);
      return;
    }

    const remaining = max - urls.length;
    const incoming = Array.from(files).slice(0, remaining);
    if (files.length > remaining) {
      setError(`Hanya ${remaining} gambar yg ditambahkan — sisa terlewat (maks ${max}).`);
    }
    if (incoming.length === 0) return;

    setUploadingCount(incoming.length);

    // Batas 2 MB TIDAK dicek di sini — kompresi dijalankan dulu di uploadOne,
    // baru ukurannya divalidasi. Foto besar yang menyusut jauh di bawah batas
    // seharusnya lolos, bukan ditolak sebelum sempat dikompres.
    const { uploaded, errors } = await uploadProductImageFiles(incoming, remaining);

    if (errors.length > 0) {
      setError(errors.join(" · "));
    }

    setUrls((prev) => [...prev, ...uploaded].slice(0, max));
    setUploadingCount(0);
  }

  function removeAt(idx: number) {
    setUrls((prev) => prev.filter((_, i) => i !== idx));
  }

  function reorder(from: number, to: number) {
    if (from === to) return;
    setUrls((prev) => {
      if (from < 0 || from >= prev.length || to < 0 || to >= prev.length) {
        return prev;
      }
      const next = [...prev];
      const [picked] = next.splice(from, 1);
      next.splice(to, 0, picked);
      return next;
    });
  }

  function handleDragStart(idx: number) {
    return (e: React.DragEvent) => {
      setDragIndex(idx);
      e.dataTransfer.effectAllowed = "move";
      e.dataTransfer.setData("text/plain", String(idx));
    };
  }
  function handleDragOver(idx: number) {
    return (e: React.DragEvent) => {
      e.preventDefault();
      e.dataTransfer.dropEffect = "move";
      if (dragIndex !== null && dragIndex !== idx) {
        setDragOverIndex(idx);
      }
    };
  }
  function handleDragLeave() {
    setDragOverIndex(null);
  }
  function handleDrop(idx: number) {
    return (e: React.DragEvent) => {
      e.preventDefault();
      if (dragIndex !== null && dragIndex !== idx) {
        reorder(dragIndex, idx);
      }
      setDragIndex(null);
      setDragOverIndex(null);
    };
  }
  function handleDragEnd() {
    setDragIndex(null);
    setDragOverIndex(null);
  }

  const canAdd = urls.length + uploadingCount < max;
  const isUploading = uploadingCount > 0;

  return (
    <div>
      <label className="block text-sm font-medium text-zinc-700">{label}</label>
      <p className="mt-0.5 text-xs text-zinc-500">
        1–{max} gambar, masing-masing maks {MAX_SIZE_MB} MB. Gambar pertama
        jadi <span className="font-semibold">cover</span> (tampil kotak 1:1 di toko).{" "}
        <span className="font-semibold">Geser foto</span> untuk ubah urutan.
      </p>

      {/* Hidden inputs — satu per gambar, dikirim sebagai {name}[] */}
      {urls.map((url, idx) => (
        <input key={idx} type="hidden" name={name} value={url} />
      ))}

      <div className="mt-3 grid grid-cols-3 gap-3 sm:grid-cols-5">
        {urls.map((url, idx) => {
          const isDragging = dragIndex === idx;
          const isDragOver = dragOverIndex === idx && dragIndex !== idx;
          return (
            <div
              key={`${url}-${idx}`}
              draggable
              onDragStart={handleDragStart(idx)}
              onDragOver={handleDragOver(idx)}
              onDragLeave={handleDragLeave}
              onDrop={handleDrop(idx)}
              onDragEnd={handleDragEnd}
              className={`group relative aspect-square cursor-grab overflow-hidden rounded-2xl border bg-zinc-50 transition active:cursor-grabbing ${
                isDragging
                  ? "border-natalo-500 opacity-40 ring-2 ring-natalo-300"
                  : isDragOver
                    ? "border-natalo-600 ring-2 ring-natalo-400"
                    : "border-zinc-200"
              }`}
            >
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={url}
                alt={`Gambar ${idx + 1}`}
                className="pointer-events-none h-full w-full object-cover"
                draggable={false}
              />
              {idx === 0 && (
                <span className="absolute left-1.5 top-1.5 rounded-full bg-zinc-950/85 px-2 py-0.5 text-[10px] font-bold text-white">
                  Cover
                </span>
              )}
              <span className="absolute right-1.5 top-1.5 rounded-full bg-white/90 px-1.5 py-0.5 text-[10px] font-bold text-zinc-700 shadow">
                {idx + 1}
              </span>
              <div className="absolute inset-0 flex items-center justify-center opacity-0 transition group-hover:opacity-100">
                <span className="rounded-full bg-zinc-950/70 px-2 py-1 text-[10px] font-bold text-white">
                  ⇅ Geser
                </span>
              </div>
              <div className="absolute inset-x-1 bottom-1 flex justify-end opacity-0 transition group-hover:opacity-100">
                <button
                  type="button"
                  onClick={() => removeAt(idx)}
                  className="rounded-full bg-red-600 px-3 py-1 text-[10px] font-bold text-white shadow"
                >
                  Hapus
                </button>
              </div>
            </div>
          );
        })}

        {/* Placeholder slots untuk file yang sedang di-upload — supaya admin
            lihat progress visual (jumlah slot bertambah saat upload). */}
        {isUploading &&
          Array.from({ length: uploadingCount }).map((_, i) => (
            <div
              key={`uploading-${i}`}
              className="flex aspect-square items-center justify-center rounded-2xl border-2 border-dashed border-natalo-300 bg-natalo-50/50"
            >
              <div className="flex flex-col items-center gap-2">
                <div className="h-6 w-6 animate-spin rounded-full border-2 border-natalo-300 border-t-natalo-600" />
                <span className="text-[10px] font-bold text-natalo-700">
                  Upload...
                </span>
              </div>
            </div>
          ))}

        {canAdd && (
          <button
            type="button"
            onClick={() => fileRef.current?.click()}
            disabled={isUploading}
            className="flex aspect-square flex-col items-center justify-center gap-1 rounded-2xl border-2 border-dashed border-zinc-300 bg-zinc-50 text-zinc-400 transition hover:border-zinc-500 hover:text-zinc-600 disabled:opacity-50"
          >
            <span className="text-2xl">+</span>
            <span className="text-[10px] font-bold">
              {urls.length + uploadingCount}/{max}
            </span>
          </button>
        )}
      </div>

      <input
        ref={fileRef}
        type="file"
        accept="image/jpeg,image/png,image/webp,image/gif"
        multiple
        className="hidden"
        onChange={(e) => {
          if (e.target.files && e.target.files.length > 0) {
            handleFiles(e.target.files);
          }
          e.target.value = "";
        }}
      />

      {error && <p className="mt-2 text-xs text-red-500">{error}</p>}
    </div>
  );
}
