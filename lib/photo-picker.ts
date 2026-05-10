/**
 * Universal photo picker — abstract antar Capacitor native camera/photo library
 * dan web file input. Dipakai untuk upload foto review, profile picture, dll.
 *
 * Native (iOS/.ipa): Camera plugin dengan action sheet (Take Photo / Photo Library)
 *                    + auto-resize via plugin (saveToGallery: false, quality: 80).
 *                    Permission auto-prompt dengan usage description di Info.plist.
 * Web/PWA:           Trigger hidden file input. Browser kasih native picker.
 *
 * Returns: Blob siap di-upload via FormData ke /api/.../upload endpoint.
 */

export type PickPhotoOptions = {
  /** Quality 0-100. Default 80 (sweet spot quality vs file size). */
  quality?: number;
  /** Max width pixels. Image scaled down kalau lebih besar. Default 1600. */
  maxWidth?: number;
  /** Max height pixels. Default 1600. */
  maxHeight?: number;
  /** Source: "prompt" (action sheet), "camera" (langsung kamera), "photos" (langsung library) */
  source?: "prompt" | "camera" | "photos";
};

export type PickPhotoResult =
  | { ok: true; blob: Blob; format: string; method: "native" | "web" }
  | { ok: false; cancelled: true }
  | { ok: false; error: Error };

export async function pickPhoto(opts: PickPhotoOptions = {}): Promise<PickPhotoResult> {
  const { quality = 80, maxWidth = 1600, maxHeight = 1600, source = "prompt" } = opts;

  // Try Capacitor Camera plugin (iOS/Android native)
  try {
    const { Camera, CameraSource, CameraResultType } = await import("@capacitor/camera");

    const sourceMap = {
      prompt: CameraSource.Prompt,
      camera: CameraSource.Camera,
      photos: CameraSource.Photos,
    } as const;

    const photo = await Camera.getPhoto({
      quality,
      width: maxWidth,
      height: maxHeight,
      allowEditing: false,
      resultType: CameraResultType.Base64, // base64 langsung, gampang convert ke Blob
      source: sourceMap[source],
      promptLabelHeader: "Pilih Foto",
      promptLabelCancel: "Batal",
      promptLabelPhoto: "Pilih dari Galeri",
      promptLabelPicture: "Ambil Foto",
    });

    if (!photo.base64String) {
      return { ok: false, error: new Error("No photo data returned") };
    }

    const format = photo.format || "jpeg";
    const blob = base64ToBlob(photo.base64String, `image/${format}`);
    return { ok: true, blob, format, method: "native" };
  } catch (err) {
    if (err && typeof err === "object" && "message" in err) {
      const msg = String((err as Error).message).toLowerCase();
      if (msg.includes("cancel") || msg.includes("denied")) {
        return { ok: false, cancelled: true };
      }
    }
    // Plugin not available (web non-Capacitor) → fall through to web input
  }

  // Web fallback: trigger hidden file input
  return pickPhotoViaWebInput(opts);
}

function pickPhotoViaWebInput(opts: PickPhotoOptions): Promise<PickPhotoResult> {
  return new Promise((resolve) => {
    const input = document.createElement("input");
    input.type = "file";
    input.accept = "image/jpeg,image/png,image/webp,image/heic,image/heif";
    if (opts.source === "camera") input.capture = "environment";
    input.onchange = async () => {
      const file = input.files?.[0];
      if (!file) {
        resolve({ ok: false, cancelled: true });
        return;
      }
      try {
        const resized = await resizeImageBlob(file, opts);
        const format = file.type.replace("image/", "") || "jpeg";
        resolve({ ok: true, blob: resized, format, method: "web" });
      } catch (err) {
        resolve({
          ok: false,
          error: err instanceof Error ? err : new Error("Resize failed"),
        });
      }
    };
    input.oncancel = () => resolve({ ok: false, cancelled: true });
    input.click();
  });
}

/** Convert base64 string to Blob (for upload via FormData) */
function base64ToBlob(base64: string, mimeType: string): Blob {
  const byteString = atob(base64);
  const buffer = new Uint8Array(byteString.length);
  for (let i = 0; i < byteString.length; i++) {
    buffer[i] = byteString.charCodeAt(i);
  }
  return new Blob([buffer], { type: mimeType });
}

/** Web-side image resize via canvas — reduce upload size */
async function resizeImageBlob(file: Blob, opts: PickPhotoOptions): Promise<Blob> {
  const { maxWidth = 1600, maxHeight = 1600, quality = 80 } = opts;
  const url = URL.createObjectURL(file);
  try {
    const img = await new Promise<HTMLImageElement>((resolve, reject) => {
      const i = new Image();
      i.onload = () => resolve(i);
      i.onerror = () => reject(new Error("Image load failed"));
      i.src = url;
    });

    const ratio = Math.min(maxWidth / img.width, maxHeight / img.height, 1);
    const w = Math.round(img.width * ratio);
    const h = Math.round(img.height * ratio);

    const canvas = document.createElement("canvas");
    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext("2d");
    if (!ctx) throw new Error("Canvas 2D context unavailable");
    ctx.drawImage(img, 0, 0, w, h);

    return await new Promise<Blob>((resolve, reject) => {
      canvas.toBlob(
        (blob) => {
          if (blob) resolve(blob);
          else reject(new Error("Blob conversion failed"));
        },
        "image/jpeg",
        quality / 100,
      );
    });
  } finally {
    URL.revokeObjectURL(url);
  }
}
