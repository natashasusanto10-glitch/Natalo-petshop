"use client";

import {
  useEffect,
  useRef,
  useState,
  type Ref,
  type PointerEvent,
  type KeyboardEvent,
} from "react";
import ProductVideoDraft, {
  type ProductVideoDraftHandle,
} from "./ProductVideoDraft";
import {
  canRemoveImage,
  removeImageAt,
  reorderImages,
} from "@/lib/product/product-media";
import { uploadProductImageFiles } from "../MultiImageUpload";
import { AdminDialog } from "./ui/AdminDialog";
import { LayoutMotion, adminMotionAllowed } from "./ui/Motion";
export { canRemoveImage, removeImageAt } from "@/lib/product/product-media";

export type ProductVideoDraftValue = {
  videoGuid?: string | null;
  videoStatus?: string | null;
  videoThumbnailUrl?: string | null;
  videoDurationSec?: number | null;
};
export type ProductVideoIntent = "keep" | "remove" | "replace";

export function ProductMediaRail({
  images,
  video,
  onImagesChange,
  onVideoIntentChange,
  videoDraftRef,
  onBusyChange,
  onDraftVideoPreview,
}: {
  images: string[];
  video?: ProductVideoDraftValue | null;
  onImagesChange(images: string[]): void;
  onVideoIntentChange(intent: ProductVideoIntent): void;
  videoDraftRef?: Ref<ProductVideoDraftHandle>;
  onBusyChange?(busy: boolean): void;
  onDraftVideoPreview?(
    media: { url: string; durationSec: number } | null
  ): void;
}) {
  const fileRef = useRef<HTMLInputElement>(null);
  const gridRef = useRef<HTMLDivElement>(null);
  const latest = useRef(images);
  latest.current = images;
  const changeRef = useRef(onImagesChange);
  changeRef.current = onImagesChange;
  const cleanupRef = useRef<(() => void) | null>(null);
  const uploadingRef = useRef(false);
  const suppressClick = useRef(false);
  const [preview, setPreview] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [dragged, setDragged] = useState<string | null>(null);
  const [pending, setPending] = useState(0);
  const [videoBusy, setVideoBusy] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [announcement, setAnnouncement] = useState("");
  useEffect(() => () => cleanupRef.current?.(), []);
  useEffect(() => {
    onBusyChange?.(uploading || videoBusy);
  }, [uploading, videoBusy, onBusyChange]);
  function change(next: string[]) {
    latest.current = next;
    changeRef.current(next);
  }

  async function addFiles(files: FileList | null) {
    if (!files || uploadingRef.current) return;
    const remaining = Math.max(0, 9 - latest.current.length);
    const incoming = Array.from(files).slice(0, remaining);
    if (!incoming.length) return;
    uploadingRef.current = true;
    setUploading(true);
    setError(null);
    setPending(incoming.length);
    const base = [...latest.current];
    const slots = new Array<string | undefined>(incoming.length);
    try {
      const result = await uploadProductImageFiles(
        incoming,
        remaining,
        (settled) => {
          setPending((count) => Math.max(0, count - 1));
          if (settled.url) {
            slots[settled.index] = settled.url;
            change([
              ...base,
              ...slots.filter((url): url is string => Boolean(url)),
            ]);
          }
        }
      );
      setError(result.errors.length ? result.errors.join(" · ") : null);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unggah foto gagal.");
    } finally {
      setPending(0);
      uploadingRef.current = false;
      setUploading(false);
    }
  }

  function beginDrag(event: PointerEvent<HTMLButtonElement>, url: string) {
    if (uploadingRef.current || event.button !== 0 || cleanupRef.current)
      return;
    const card = event.currentTarget.parentElement!;
    const bounds = card.getBoundingClientRect();
    const start = { x: event.clientX, y: event.clientY };
    const original = [...latest.current];
    let clone: HTMLElement | null = null,
      frame = 0,
      lastX = start.x,
      lastY = start.y,
      ended = false;
    const pointerId = event.pointerId;
    const draw = () => {
      frame = 0;
      if (!clone) return;
      clone.style.transform = `translate3d(${lastX - start.x}px,${
        lastY - start.y
      }px,0)`;
      const cards = Array.from(
        gridRef.current?.querySelectorAll<HTMLElement>("[data-photo-url]") ?? []
      );
      const target = cards.find((item) => {
        const rect = item.getBoundingClientRect();
        return (
          lastX >= rect.left &&
          lastX <= rect.right &&
          lastY >= rect.top &&
          lastY <= rect.bottom
        );
      });
      if (target) {
        const from = latest.current.indexOf(url),
          to = latest.current.indexOf(target.dataset.photoUrl!);
        if (from !== to && from >= 0 && to >= 0)
          change(reorderImages(latest.current, from, to));
      }
    };
    const move = (e: globalThis.PointerEvent) => {
      if (e.pointerId !== pointerId || ended) return;
      lastX = e.clientX;
      lastY = e.clientY;
      if (!clone && Math.hypot(lastX - start.x, lastY - start.y) >= 6) {
        clone = card.cloneNode(true) as HTMLElement;
        clone.classList.add("admin-photo-drag");
        clone.classList.remove("is-dragging");
        clone.setAttribute("aria-hidden", "true");
        clone.inert = true;
        Object.assign(clone.style, {
          left: `${bounds.left}px`,
          top: `${bounds.top}px`,
          width: `${bounds.width}px`,
          height: `${bounds.height}px`,
          margin: "0",
        });
        document.body.appendChild(clone);
        setDragged(url);
        suppressClick.current = true;
      }
      if (clone) {
        e.preventDefault();
        if (!frame) frame = requestAnimationFrame(draw);
      }
    };
    const finish = (cancel: boolean) => {
      if (ended) return;
      ended = true;
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
      window.removeEventListener("pointercancel", cancelPointer);
      window.removeEventListener("keydown", key);
      cancelAnimationFrame(frame);
      if (cancel) change(original);
      const target = Array.from(
        gridRef.current?.querySelectorAll<HTMLElement>("[data-photo-url]") ?? []
      )
        .find((item) => item.dataset.photoUrl === url)
        ?.getBoundingClientRect();
      const floating = clone;
      const dispose = () => {
        floating?.remove();
        setDragged(null);
        cleanupRef.current = null;
        setTimeout(() => {
          suppressClick.current = false;
        }, 0);
      };
      if (floating && target && adminMotionAllowed() && !cancel) {
        const animation = floating.animate(
          [
            { transform: floating.style.transform },
            {
              transform: `translate3d(${target.left - bounds.left}px,${
                target.top - bounds.top
              }px,0)`,
            },
          ],
          {
            duration: 200,
            easing: "cubic-bezier(.2,.8,.2,1)",
            fill: "forwards",
          }
        );
        cleanupRef.current = () => {
          animation.cancel();
          floating.remove();
        };
        void animation.finished.then(dispose).catch(dispose);
      } else dispose();
      if (floating && !cancel)
        setAnnouncement(
          `Foto dipindahkan ke urutan ${latest.current.indexOf(url) + 1}.`
        );
    };
    const up = (e: globalThis.PointerEvent) => {
      if (e.pointerId === pointerId) finish(false);
    };
    const cancelPointer = () => finish(true);
    const key = (e: globalThis.KeyboardEvent) => {
      if (e.key === "Escape") {
        e.preventDefault();
        finish(true);
      }
    };
    window.addEventListener("pointermove", move, { passive: false });
    window.addEventListener("pointerup", up);
    window.addEventListener("pointercancel", cancelPointer);
    window.addEventListener("keydown", key);
    cleanupRef.current = () => {
      ended = true;
      cancelAnimationFrame(frame);
      clone?.remove();
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
      window.removeEventListener("pointercancel", cancelPointer);
      window.removeEventListener("keydown", key);
    };
  }
  function keyboard(event: KeyboardEvent<HTMLButtonElement>, index: number) {
    const destination =
      event.key === "ArrowLeft"
        ? index - 1
        : event.key === "ArrowRight"
        ? index + 1
        : event.key === "Home"
        ? 0
        : event.key === "End"
        ? images.length - 1
        : null;
    if (destination === null || uploading) return;
    event.preventDefault();
    if (destination < 0 || destination >= images.length) return;
    change(reorderImages(images, index, destination));
    setAnnouncement(`Foto dipindahkan ke urutan ${destination + 1}.`);
  }
  return (
    <div>
      <div ref={gridRef}>
        <LayoutMotion revision={images.join("|")} className="admin-photo-grid">
          {images.map((url, index) => (
            <div
              key={`${url}-${
                images.slice(0, index).filter((u) => u === url).length
              }`}
              data-motion-key={url}
              data-photo-url={url}
              className={`admin-photo ${dragged === url ? "is-dragging" : ""}`}
            >
              <button
                type="button"
                disabled={uploading}
                aria-label={`Pratinjau foto ${index + 1}`}
                aria-keyshortcuts="ArrowLeft ArrowRight Home End"
                onPointerDown={(event) => beginDrag(event, url)}
                onKeyDown={(event) => keyboard(event, index)}
                onClick={() => {
                  if (!suppressClick.current) setPreview(url);
                }}
              >
                <img
                  src={url}
                  alt={`Foto produk ${index + 1}`}
                  draggable={false}
                />
                {index === 0 && <span className="admin-photo-main">Utama</span>}
                <span className="admin-photo-caption">
                  {index === 0 ? "Foto utama" : `Foto ${index + 1}`}
                </span>
              </button>
              <button
                type="button"
                className="admin-photo-remove"
                aria-label={`Hapus foto ${index + 1}`}
                disabled={uploading || !canRemoveImage(images)}
                onClick={() => change(removeImageAt(images, index))}
              >
                ×
              </button>
            </div>
          ))}
          {Array.from({ length: pending }, (_, index) => (
            <div
              key={`pending-${index}`}
              className="admin-photo-upload"
              role="status"
            >
              Mengunggah…
            </div>
          ))}
          {images.length + pending < 9 && (
            <button
              type="button"
              className="admin-photo-upload"
              disabled={uploading}
              onClick={() => fileRef.current?.click()}
              aria-label="Tambah foto"
            >
              <svg
                width="22"
                height="22"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="1.5"
              >
                <path d="M12 5v14M5 12h14" />
              </svg>
              <span>Tambah foto</span>
              <span className="text-slate-500">
                {images.length + pending}/9
              </span>
            </button>
          )}
        </LayoutMotion>
      </div>
      <input
        ref={fileRef}
        type="file"
        accept="image/jpeg,image/png,image/webp,image/gif"
        multiple
        className="hidden"
        onChange={(event) => {
          void addFiles(event.target.files);
          event.currentTarget.value = "";
        }}
      />
      <ProductVideoDraft
        onDraftPreview={onDraftVideoPreview}
        onBusyChange={setVideoBusy}
        ref={videoDraftRef}
        onIntentChange={onVideoIntentChange}
        initial={
          video
            ? {
                videoGuid: video.videoGuid ?? null,
                videoStatus: video.videoStatus ?? null,
                videoThumbnailUrl: video.videoThumbnailUrl ?? null,
                videoDurationSec: video.videoDurationSec ?? null,
              }
            : undefined
        }
      />
      {error && (
        <p role="alert" className="mt-3 text-sm text-red-700">
          {error}
        </p>
      )}
      <p className="sr-only" role="status">
        {announcement}
      </p>
      <AdminDialog
        open={Boolean(preview)}
        title="Pratinjau foto"
        onClose={() => setPreview(null)}
      >
        {preview && (
          <img
            src={preview}
            alt="Pratinjau foto produk"
            className="mx-auto max-h-[60dvh] max-w-full object-contain"
          />
        )}
      </AdminDialog>
    </div>
  );
}
export default ProductMediaRail;
