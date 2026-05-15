"use client";

import {
  useEffect,
  useMemo,
  useRef,
  useState,
  type MouseEvent,
  type TouchEvent,
} from "react";
import { Drawer } from "vaul";
import {
  FiAlertCircle,
  FiCheck,
  FiInfo,
  FiPackage,
  FiPlus,
  FiX,
} from "react-icons/fi";
import { formatRupiah } from "@/lib/format";
import { hapticSuccess, hapticTap, hapticWarning } from "@/lib/native/haptics";

const MAX_CAPTION_LENGTH = 300;
const MAX_PINNED_PRODUCTS = 3;
const DRAG_CLOSE_THRESHOLD = 80;
const SNAP_BACK_MS = 260;
const SNAP_BACK_EASE = "cubic-bezier(0.34, 1.26, 0.64, 1)";

type PinnableProduct = {
  productId: string;
  slug: string;
  name: string;
  imageUrl: string | null;
  price: number;
  originalPrice: number;
  stock: number;
  avgRating: number;
  reviewCount: number;
  purchasedAt: string;
  orderNumber: string;
};

const PET_TYPES = [
  "🐶 Anjing",
  "🐱 Kucing",
  "🦜 Burung",
  "🐠 Ikan",
  "🐰 Lainnya",
];

type Props = {
  open: boolean;
  onClose: () => void;
};

export function FeedCreatePostSheet({ open, onClose }: Props) {
  const dragStartYRef = useRef(0);
  const dragYRef = useRef(0);
  const isDraggingRef = useRef(false);
  const snapBackTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [caption, setCaption] = useState("");
  const [petType, setPetType] = useState<string | null>(null);
  const [petName, setPetName] = useState("");
  const [products, setProducts] = useState<PinnableProduct[]>([]);
  const [selectedProductIds, setSelectedProductIds] = useState<string[]>([]);
  const [productPickerOpen, setProductPickerOpen] = useState(false);
  const [productsLoading, setProductsLoading] = useState(false);
  const [productsLoaded, setProductsLoaded] = useState(false);
  const [productsError, setProductsError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [formMessage, setFormMessage] = useState<string | null>(null);
  const [formError, setFormError] = useState<string | null>(null);
  const [dragY, setDragY] = useState(0);
  const [isDragging, setIsDragging] = useState(false);
  const [isSnappingBack, setIsSnappingBack] = useState(false);

  const selectedProducts = useMemo(
    () =>
      selectedProductIds
        .map((id) => products.find((product) => product.productId === id))
        .filter((product): product is PinnableProduct => Boolean(product)),
    [products, selectedProductIds],
  );

  const canSubmit = caption.trim().length > 0;

  useEffect(() => {
    if (!open || productsLoaded) return;
    let cancelled = false;
    setProductsLoading(true);
    setProductsError(null);

    fetch("/api/feed/pinnable-products")
      .then(async (res) => {
        const data = await res.json().catch(() => ({}));
        if (!res.ok) {
          throw new Error(
            typeof data?.error === "string"
              ? data.error
              : "Gagal memuat riwayat pembelian.",
          );
        }
        return data as { products: PinnableProduct[] };
      })
      .then((data) => {
        if (cancelled) return;
        setProducts(data.products ?? []);
        setProductsLoaded(true);
      })
      .catch((err) => {
        if (cancelled) return;
        setProducts([]);
        setProductsError(
          err instanceof Error ? err.message : "Gagal memuat riwayat pembelian.",
        );
      })
      .finally(() => {
        if (!cancelled) setProductsLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [open, productsLoaded]);

  useEffect(() => {
    if (!open) return;
    document.body.classList.add("nat-modal-open", "bottom-sheet-open");
    return () => {
      document.body.classList.remove("nat-modal-open", "bottom-sheet-open");
    };
  }, [open]);

  useEffect(() => {
    if (!open) {
      setDragY(0);
      dragYRef.current = 0;
      isDraggingRef.current = false;
      setIsDragging(false);
      setIsSnappingBack(false);
    }
  }, [open]);

  useEffect(() => {
    if (!isDragging) return;

    function handleMouseMove(event: globalThis.MouseEvent) {
      if (!isDraggingRef.current) return;
      const nextDragY = Math.max(0, event.clientY - dragStartYRef.current);
      dragYRef.current = nextDragY;
      setDragY(nextDragY);
      if (dragYRef.current > 0) event.preventDefault();
    }

    function handleMouseUp() {
      if (!isDraggingRef.current) return;
      isDraggingRef.current = false;
      setIsDragging(false);

      if (dragYRef.current > DRAG_CLOSE_THRESHOLD) {
        if (!submitting) onClose();
        return;
      }

      setIsSnappingBack(true);
      dragYRef.current = 0;
      setDragY(0);
      snapBackTimerRef.current = setTimeout(() => {
        setIsSnappingBack(false);
      }, SNAP_BACK_MS);
    }

    document.addEventListener("mousemove", handleMouseMove, { passive: false });
    document.addEventListener("mouseup", handleMouseUp);
    return () => {
      document.removeEventListener("mousemove", handleMouseMove);
      document.removeEventListener("mouseup", handleMouseUp);
    };
  }, [isDragging, onClose, submitting]);

  useEffect(() => {
    return () => {
      if (snapBackTimerRef.current) clearTimeout(snapBackTimerRef.current);
    };
  }, []);

  function closeSheet() {
    if (submitting) return;
    onClose();
  }

  function beginDrag(target: EventTarget | null, clientY: number) {
    if (target instanceof HTMLElement && target.closest("button")) return;

    const active = document.activeElement;
    if (
      active instanceof HTMLElement &&
      (active.tagName === "INPUT" || active.tagName === "TEXTAREA")
    ) {
      active.blur();
      return;
    }

    if (snapBackTimerRef.current) clearTimeout(snapBackTimerRef.current);
    dragStartYRef.current = clientY;
    dragYRef.current = 0;
    isDraggingRef.current = true;
    setDragY(0);
    setIsDragging(true);
    setIsSnappingBack(false);
  }

  function updateDrag(clientY: number) {
    if (!isDraggingRef.current) return;
    const nextDragY = Math.max(0, clientY - dragStartYRef.current);
    dragYRef.current = nextDragY;
    setDragY(nextDragY);
  }

  function finishDrag() {
    if (!isDraggingRef.current) return;
    isDraggingRef.current = false;
    setIsDragging(false);

    if (dragYRef.current > DRAG_CLOSE_THRESHOLD) {
      closeSheet();
      return;
    }

    setIsSnappingBack(true);
    dragYRef.current = 0;
    setDragY(0);
    snapBackTimerRef.current = setTimeout(() => setIsSnappingBack(false), SNAP_BACK_MS);
  }

  function handleMouseDown(event: MouseEvent<HTMLDivElement>) {
    if (event.button !== 0) return;
    beginDrag(event.target, event.clientY);
  }

  function handleTouchStart(event: TouchEvent<HTMLDivElement>) {
    const touch = event.touches[0];
    if (!touch) return;
    beginDrag(event.target, touch.clientY);
  }

  function handleTouchMove(event: TouchEvent<HTMLDivElement>) {
    const touch = event.touches[0];
    if (!touch) return;
    updateDrag(touch.clientY);
    if (dragYRef.current > 0 && event.cancelable) event.preventDefault();
  }

  function updateCaption(value: string) {
    setCaption(value.slice(0, MAX_CAPTION_LENGTH));
    setFormError(null);
    setFormMessage(null);
  }

  function toggleProduct(productId: string) {
    setFormError(null);
    setFormMessage(null);
    setSelectedProductIds((current) => {
      if (current.includes(productId)) {
        return current.filter((id) => id !== productId);
      }
      if (current.length >= MAX_PINNED_PRODUCTS) {
        void hapticWarning();
        setFormError(`Maksimal ${MAX_PINNED_PRODUCTS} produk yang bisa di-pin.`);
        return current;
      }
      void hapticTap();
      return [...current, productId];
    });
  }

  async function submitPost() {
    if (submitting) return;
    if (!canSubmit) {
      setFormError("Isi caption dulu sebelum posting.");
      void hapticWarning();
      return;
    }

    setSubmitting(true);
    setFormError(null);
    setFormMessage(null);

    const petInfo = [petType, petName.trim()].filter(Boolean).join(" · ");
    const description = petInfo
      ? `${caption.trim()}\n\nInfo peliharaan: ${petInfo}`
      : caption.trim();

    try {
      const res = await fetch("/api/feed/posts", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          title: "Postingan Natalo",
          description,
          productId: selectedProductIds[0] ?? null,
          productIds: selectedProductIds,
        }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error(
          typeof data?.error === "string" ? data.error : "Gagal membuat postingan.",
        );
      }

      setCaption("");
      setPetType(null);
      setPetName("");
      setSelectedProductIds([]);
      setProductPickerOpen(false);
      setFormMessage("Postingan menunggu review admin dan belum tayang di Feed.");
      void hapticSuccess();
    } catch (err) {
      setFormError(err instanceof Error ? err.message : "Gagal membuat postingan.");
      void hapticWarning();
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Drawer.Root
      open={open}
      onOpenChange={(nextOpen) => {
        if (!nextOpen) closeSheet();
      }}
      direction="bottom"
      modal
      dismissible
      closeThreshold={0.28}
      scrollLockTimeout={350}
    >
      <Drawer.Portal>
        <Drawer.Overlay
          data-no-pull
          data-no-swipe-back="true"
          className="fixed inset-0 z-[2000] bg-black/55"
        />
        <Drawer.Content
          data-no-pull
          data-no-swipe-back="true"
          data-no-tap-press="true"
          aria-describedby={undefined}
          className="fixed inset-x-0 bottom-0 z-[2001] mx-auto flex w-full max-w-2xl flex-col overflow-hidden rounded-t-[28px] bg-gray-50 shadow-[0_-22px_55px_rgba(0,0,0,0.32)] outline-none"
          style={{
            maxHeight: "min(88dvh, calc(100dvh - env(safe-area-inset-top) - 10px))",
            transform:
              isDragging || isSnappingBack ? `translate3d(0, ${dragY}px, 0)` : undefined,
            transition: isDragging
              ? "none"
              : isSnappingBack
                ? `transform ${SNAP_BACK_MS}ms ${SNAP_BACK_EASE}`
                : undefined,
          }}
          onOpenAutoFocus={(event) => event.preventDefault()}
        >
          <div
            className="shrink-0 cursor-grab bg-white px-4 pb-3 pt-2 active:cursor-grabbing"
            onMouseDown={handleMouseDown}
            onTouchStart={handleTouchStart}
            onTouchMove={handleTouchMove}
            onTouchEnd={finishDrag}
            onTouchCancel={finishDrag}
          >
            <div className="flex justify-center py-1.5">
              <div className="h-1.5 w-11 rounded-full bg-zinc-300" />
            </div>
            <div className="grid grid-cols-[44px_1fr_auto] items-center gap-2">
              <button
                type="button"
                onClick={closeSheet}
                aria-label="Tutup"
                className="grid h-11 w-11 place-items-center rounded-full bg-zinc-100 text-zinc-700 transition active:scale-95"
              >
                <FiX className="h-5 w-5" />
              </button>
              <Drawer.Title className="text-center text-base font-black text-zinc-950">
                Buat Postingan
              </Drawer.Title>
              <button
                type="button"
                onClick={submitPost}
                disabled={!canSubmit || submitting}
                className="rounded-full bg-natalo-600 px-4 py-2.5 text-sm font-black text-white shadow-sm transition active:scale-95 disabled:cursor-not-allowed disabled:bg-zinc-300 disabled:shadow-none"
              >
                {submitting ? "..." : "Posting"}
              </button>
            </div>
          </div>

          <div className="min-h-0 flex-1 space-y-4 overflow-y-auto px-4 py-4 [padding-bottom:calc(18px+env(safe-area-inset-bottom))]">
            {formMessage && (
              <div className="flex items-start gap-2 rounded-3xl border border-emerald-100 bg-emerald-50 p-3 text-xs font-bold leading-relaxed text-emerald-800">
                <FiCheck className="mt-0.5 h-4 w-4 shrink-0" />
                <span>{formMessage}</span>
              </div>
            )}
            {formError && (
              <div className="flex items-start gap-2 rounded-3xl border border-red-100 bg-red-50 p-3 text-xs font-bold leading-relaxed text-red-700">
                <FiAlertCircle className="mt-0.5 h-4 w-4 shrink-0" />
                <span>{formError}</span>
              </div>
            )}

            <section className="rounded-3xl border border-zinc-100 bg-white p-4 shadow-sm">
              <div className="flex items-center justify-between gap-3">
                <h2 className="text-sm font-black text-zinc-950">✍️ Caption</h2>
                <span className="text-xs font-extrabold text-zinc-400">
                  {caption.length} / {MAX_CAPTION_LENGTH}
                </span>
              </div>
              <textarea
                value={caption}
                onChange={(event) => updateCaption(event.target.value)}
                maxLength={MAX_CAPTION_LENGTH}
                rows={5}
                placeholder="Ceritakan pengalamanmu bersama hewan peliharaan & produk Natalo..."
                className="mt-3 w-full resize-none rounded-2xl border border-zinc-200 bg-zinc-50 px-3 py-3 text-sm font-semibold leading-relaxed text-zinc-900 outline-none placeholder:text-zinc-400 focus:border-natalo-500 focus:bg-white"
              />
            </section>

            <section className="rounded-3xl border border-zinc-100 bg-white p-4 shadow-sm">
              <h2 className="text-sm font-black text-zinc-950">
                🛒 Pin Produk yang Dipakai
              </h2>
              <p className="mt-1 text-xs font-semibold leading-relaxed text-zinc-500">
                Maksimal 3 produk · Hanya dari riwayat pembelianmu yang sudah diterima
              </p>

              {selectedProducts.length > 0 && (
                <div className="mt-3 flex flex-wrap gap-2">
                  {selectedProducts.map((product) => (
                    <button
                      key={product.productId}
                      type="button"
                      onClick={() => toggleProduct(product.productId)}
                      className="inline-flex max-w-full items-center gap-1.5 rounded-full border border-natalo-200 bg-natalo-50 px-3 py-1.5 text-left text-[11px] font-extrabold text-natalo-700"
                    >
                      <span className="truncate">{product.name}</span>
                      <FiX className="h-3.5 w-3.5 shrink-0" />
                    </button>
                  ))}
                </div>
              )}

              <button
                type="button"
                onClick={() => {
                  setProductPickerOpen((value) => !value);
                  void hapticTap();
                }}
                className="mt-3 flex w-full items-center justify-center gap-2 rounded-2xl border border-dashed border-natalo-400 bg-natalo-50 px-3 py-3 text-sm font-black text-natalo-700 transition active:scale-[0.99]"
              >
                <FiPlus className="h-4 w-4" />
                Pilih Produk dari Riwayat Pembelian
              </button>

              {productPickerOpen && (
                <ProductPickerPanel
                  products={products}
                  selectedProductIds={selectedProductIds}
                  loading={productsLoading}
                  error={productsError}
                  onToggleProduct={toggleProduct}
                />
              )}
            </section>

            <section className="rounded-3xl border border-zinc-100 bg-white p-4 shadow-sm">
              <h2 className="text-sm font-black text-zinc-950">🐾 Info Peliharaan</h2>
              <p className="mt-1 text-xs font-semibold text-zinc-500">
                Bantu viewer kenal lebih dekat
              </p>
              <div className="mt-3 flex flex-wrap gap-2">
                {PET_TYPES.map((type) => {
                  const selected = petType === type;
                  return (
                    <button
                      key={type}
                      type="button"
                      onClick={() => {
                        setPetType(selected ? null : type);
                        void hapticTap();
                      }}
                      className={`rounded-full border px-3 py-2 text-xs font-black transition active:scale-95 ${
                        selected
                          ? "border-natalo-500 bg-natalo-50 text-natalo-700"
                          : "border-zinc-200 bg-zinc-100 text-zinc-600"
                      }`}
                    >
                      {type}
                    </button>
                  );
                })}
              </div>
              <input
                type="text"
                value={petName}
                onChange={(event) => setPetName(event.target.value.slice(0, 80))}
                placeholder="Nama peliharaan & jenis ras (cth: Miko · Persian)"
                className="mt-3 w-full rounded-2xl border border-zinc-200 bg-zinc-50 px-3 py-3 text-sm font-semibold text-zinc-900 outline-none placeholder:text-zinc-400 focus:border-natalo-500 focus:bg-white"
              />
            </section>

            <div className="flex items-start gap-2 rounded-3xl border border-amber-200 bg-amber-50 p-4 text-xs font-bold leading-relaxed text-amber-900">
              <FiInfo className="mt-0.5 h-4 w-4 shrink-0" />
              <p>
                Postingan akan ditinjau admin sebelum tayang di Feed (max. 1×24
                jam). Pastikan konten sesuai pedoman komunitas Natalo.
              </p>
            </div>
          </div>
        </Drawer.Content>
      </Drawer.Portal>
    </Drawer.Root>
  );
}

function ProductPickerPanel({
  products,
  selectedProductIds,
  loading,
  error,
  onToggleProduct,
}: {
  products: PinnableProduct[];
  selectedProductIds: string[];
  loading: boolean;
  error: string | null;
  onToggleProduct: (productId: string) => void;
}) {
  if (loading) {
    return (
      <p className="mt-3 rounded-2xl bg-zinc-50 p-4 text-center text-xs font-bold text-zinc-400">
        Memuat riwayat pembelian...
      </p>
    );
  }

  if (error) {
    return (
      <p className="mt-3 rounded-2xl bg-red-50 p-4 text-center text-xs font-bold leading-relaxed text-red-700">
        {error}
      </p>
    );
  }

  if (products.length === 0) {
    return (
      <div className="mt-3 rounded-2xl bg-zinc-50 p-4 text-center">
        <p className="text-sm font-black text-zinc-700">
          Belum ada produk yang bisa dipilih
        </p>
        <p className="mt-1 text-xs font-semibold leading-relaxed text-zinc-500">
          Produk akan muncul setelah pesananmu sudah diterima.
        </p>
      </div>
    );
  }

  return (
    <div className="mt-3 max-h-72 space-y-2 overflow-y-auto pr-1">
      {products.map((product) => {
        const selected = selectedProductIds.includes(product.productId);
        return (
          <button
            key={`${product.productId}-${product.orderNumber}`}
            type="button"
            onClick={() => onToggleProduct(product.productId)}
            className={`flex w-full items-center gap-3 rounded-2xl border p-3 text-left transition active:scale-[0.99] ${
              selected
                ? "border-natalo-500 bg-natalo-50"
                : "border-zinc-100 bg-white"
            }`}
          >
            <div className="grid h-14 w-14 shrink-0 place-items-center overflow-hidden rounded-2xl bg-zinc-100 text-natalo-600">
              {product.imageUrl ? (
                <img
                  src={product.imageUrl}
                  alt=""
                  className="h-full w-full object-cover"
                />
              ) : (
                <FiPackage className="h-5 w-5" />
              )}
            </div>
            <div className="min-w-0 flex-1">
              <p className="line-clamp-2 text-xs font-black leading-snug text-zinc-900">
                {product.name}
              </p>
              <p className="mt-1 text-xs font-black text-natalo-600">
                {formatRupiah(product.price)}
              </p>
              <p className="mt-0.5 text-[11px] font-semibold text-zinc-500">
                Dibeli {formatDate(product.purchasedAt)}
              </p>
            </div>
            <span
              className={`grid h-7 w-7 shrink-0 place-items-center rounded-full border ${
                selected
                  ? "border-natalo-600 bg-natalo-600 text-white"
                  : "border-zinc-200 bg-white text-transparent"
              }`}
            >
              <FiCheck className="h-4 w-4" />
            </span>
          </button>
        );
      })}
    </div>
  );
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString("id-ID", {
    day: "numeric",
    month: "short",
    year: "numeric",
  });
}
