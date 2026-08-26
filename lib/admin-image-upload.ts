/**
 * Mesin upload gambar admin — dipakai bersama oleh SEMUA slot upload di
 * panel admin. Sebelumnya logika ini hanya ada di dalam MultiImageUpload,
 * jadi tiap slot upload lain (foto varian, logo brand, banner, popup)
 * menulis ulang versi telanjangnya sendiri: kirim file mentah, tanpa
 * kompresi, tanpa percobaan ulang. Akibatnya PNG 1,7 MB rutin gagal di
 * slot-slot itu meski slot foto produk utama sudah beres.
 *
 * Semua yang mengunggah gambar ke /api/admin/upload WAJIB lewat sini.
 */

export const MAX_SIZE_MB = 2;
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
export const UPLOAD_CONCURRENCY = 2;
/** Jeda sebelum percobaan ulang untuk kegagalan sementara. */
const UPLOAD_RETRY_DELAY_MS = 800;

/** Error upload yang tahu apakah percobaan ulang masuk akal. */
export class UploadError extends Error {
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
export async function runWithConcurrency<T, R>(
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
async function postImage(
  file: File,
  displayName: string,
  fields?: Record<string, string>,
): Promise<string> {
  const fd = new FormData();
  fd.append("file", file);
  // Field tambahan, mis. kind=brand-logo yang memicu normalizeBrandLogo di
  // server. WAJIB ikut terkirim — tanpa ini logo lolos mentah tanpa
  // di-trim & dipusatkan, jadi berat visualnya beda sendiri di grid Home.
  for (const [key, value] of Object.entries(fields ?? {})) fd.append(key, value);

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

  const url = String((await res.json()).url ?? "");
  if (!url) throw new UploadError(`Server tidak mengembalikan URL untuk "${displayName}"`, false);
  return url;
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
 * `preserveFormat` mematikan konversi PNG→JPEG. Dipakai logo brand dan
 * grafis bergaris tajam: JPEG menambah artefak ringing di tepi, dan server
 * menjalankan sharp().trim() yang justru mengandalkan tepi bersih untuk
 * memotong padding. Resize tetap jalan, jadi file besar tetap mengecil.
 *
 * Return: File baru (compressed) atau original kalau tidak bisa compress.
 */
export async function compressImage(
  file: File,
  preserveFormat = false,
): Promise<File> {
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

    // preserveFormat = pertahankan tipe ASLI, bukan paksa PNG. Memaksa PNG
    // untuk sumber JPEG justru MEMBENGKAKKAN ukurannya (foto lossy jadi
    // lossless) — kebalikan dari tujuan fungsi ini.
    // Selain itu: PNG dipertahankan hanya kalau memang butuh alpha.
    const outType = preserveFormat
      ? file.type
      : file.type === "image/png" && hasTransparency(ctx, targetW, targetH)
        ? "image/png"
        : "image/jpeg";
    // PNG mengabaikan quality; JPEG & WEBP memakainya.
    const quality = outType === "image/png" ? undefined : JPEG_QUALITY;

    const blob = await new Promise<Blob | null>((resolve) => {
      canvas.toBlob(resolve, outType, quality);
    });
    if (!blob) return file;

    // canvas.toBlob DIAM-DIAM jatuh ke PNG kalau tipe yang diminta tidak
    // didukung. Kalau itu terjadi untuk sumber non-PNG, hasilnya bisa jauh
    // lebih besar — pakai file asli saja.
    if (blob.type !== outType) return file;

    // Hanya pakai compressed kalau memang lebih kecil dari original.
    if (blob.size >= file.size) return file;

    const newName =
      outType === "image/jpeg" && file.type !== "image/jpeg"
        ? file.name.replace(/\.(png|webp)$/i, ".jpg")
        : file.name;
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
export async function uploadOne(
  file: File,
  prepare?: (f: File) => Promise<File>,
  options: AdminUploadOptions = {},
): Promise<string> {
  const maxBytes = options.maxBytes ?? MAX_SIZE_MB * 1024 * 1024;
  const processed = prepare ? await prepare(file) : file;
  if (processed.size > maxBytes) {
    const mb = (processed.size / (1024 * 1024)).toFixed(1);
    const limit = (maxBytes / (1024 * 1024)).toFixed(maxBytes % (1024 * 1024) ? 1 : 0);
    throw new UploadError(
      `"${file.name}" ${mb} MB — melebihi batas ${limit} MB`,
      false,
    );
  }
  try {
    return await postImage(processed, file.name, options.fields);
  } catch (e) {
    if (!(e instanceof UploadError) || !e.retriable) throw e;
    await sleep(UPLOAD_RETRY_DELAY_MS);
    return postImage(processed, file.name, options.fields);
  }
}

export type AdminUploadOptions = {
  /**
   * Batas ukuran yang diperiksa SETELAH kompresi. Default 2 MB (batas
   * server). Popup peluncuran memakai 1 MB karena tampil saat app dibuka.
   */
  maxBytes?: number;
  /** Field form tambahan, mis. `{ kind: "brand-logo" }`. */
  fields?: Record<string, string>;
  /** Jangan konversi format — lihat catatan di `compressImage`. */
  preserveFormat?: boolean;
};

/**
 * Upload SATU gambar admin lengkap dengan kompresi + percobaan ulang.
 * Ini pintu untuk semua slot upload gambar tunggal: foto varian, logo
 * brand, banner, dan popup peluncuran.
 */
export function uploadAdminImage(
  file: File,
  options: AdminUploadOptions = {},
): Promise<string> {
  return uploadOne(file, (f) => compressImage(f, options.preserveFormat), options);
}
