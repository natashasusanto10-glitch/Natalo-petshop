"use client";

import { AdminPage, PageHeader, Button } from "@/components/admin/ui";
import { useAdminConfirm } from "@/components/admin/ui/useAdminConfirm";
import { FiPlus, FiTrash2, FiSearch } from "react-icons/fi";

import { NumberInput } from "@/components/admin/ui/NumberInput";

import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { AdminDialog } from "@/components/admin/ui/AdminDialog";

// ── Types ───────────────────────────────────────────────────────

interface ProductSummary {
  id: string;
  name: string;
  imageUrl: string | null;
  price: number;
  stock: number;
}

interface VariantSummary {
  id: string;
  label: string;
  sku: string | null;
  price: number;
  stock: number;
  imageUrl: string | null;
}

/** 1 item dalam promo — bisa produk single (variant=null) atau 1 varian. */
interface PromoItem {
  productId: string;
  variantId: string | null;
  discountedPrice: number;
  isItemActive: boolean;
  product: ProductSummary;
  variant: VariantSummary | null;
}

interface InitialData {
  id?: string;
  name: string;
  startsAt: string; // datetime-local format
  endsAt: string;
  items: PromoItem[];
  isActive: boolean;
}

interface Props {
  initial?: InitialData;
  /** Saat edit, kirim id supaya endpoint eligible-products exclude. */
  excludeId?: string;
}

// Eligible product (dari API eligible-products endpoint) — bisa
// punya nested variants.
interface EligibleProduct {
  id: string;
  name: string;
  imageUrl: string | null;
  price: number;
  stock: number;
  hasVariants: boolean;
  category: { name: string } | null;
  variants: Array<{
    id: string;
    label: string;
    sku: string | null;
    price: number;
    stock: number;
    imageUrl: string | null;
    isBlocked: boolean;
  }>;
}

const emptyInitial: InitialData = {
  name: "",
  startsAt: "",
  endsAt: "",
  items: [],
  isActive: true,
};

/**
 * Form Promo Toko — create + edit shared component.
 *
 * Grouped product/variant editor with a searchable picker and bulk discounts.
 * Layout:
 *  1. Informasi Dasar (Nama Promo + Periode)
 *  2. Produk dalam Promo Toko (tabel editable per-item)
 *     - Empty state: [+ Tambah Produk] button → buka modal product picker
 *     - With items: tabel dengan kolom: Foto + Nama | Harga Awal |
 *       Harga Diskon (Rp) | %Diskon | Stok | Toggle Aktif | Hapus
 *     - Produk berVarian: parent row collapsed, sub-rows per varian
 *     - 2-way binding antara Harga Diskon dan %Diskon
 */
export function PromoTokoForm({ initial, excludeId }: Props) {
  const router = useRouter();
  const formFields = useRef<HTMLFieldSetElement>(null);
  const { confirm: confirmLeave, confirmation } = useAdminConfirm();
  const [selectedItems, setSelectedItems] = useState<Set<string>>(new Set());
  const [bulkPercent, setBulkPercent] = useState("10");
  const [feedback, setFeedback] = useState("");
  const isEdit = !!initial?.id;
  const data = initial ?? emptyInitial;

  // ── Form state ──────────────────────────────────────────────
  const [name, setName] = useState(data.name);
  // Empty default supaya admin sadar perlu isi (no auto-fill). Pakai
  // tombol "Mulai sekarang" + "7 hari" sebagai quick fill.
  const [startsAt, setStartsAt] = useState(data.startsAt);
  const [endsAt, setEndsAt] = useState(data.endsAt);
  const [items, setItems] = useState<PromoItem[]>(data.items);
  const [notifyCustomers, setNotifyCustomers] = useState(false);

  // ── Promo ongoing check ─────────────────────────────────────
  // Detect kalau promo yang lagi di-edit sudah ONGOING (start <= now
  // < end). Kalau iya:
  //  - startsAt input di-disable (server juga reject perubahan, UX dulu)
  //  - Quick-fill preset hide (tidak applicable saat ongoing)
  //  - endsAt tetap editable supaya admin bisa adjust akhir atau
  //    "akhiri lebih awal"
  const isOngoing = useMemo(() => {
    if (!isEdit || !data.startsAt || !data.endsAt) return false;
    const now = new Date();
    const start = new Date(data.startsAt);
    const end = new Date(data.endsAt);
    return start <= now && end > now;
  }, [isEdit, data.startsAt, data.endsAt]);

  // Product picker modal state
  const [pickerOpen, setPickerOpen] = useState(false);

  // Submit state
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");
  const [showFieldErrors, setShowFieldErrors] = useState(false);

  // ── Validasi ────────────────────────────────────────────────
  const errors: { [k: string]: string } = {};
  if (!name.trim()) errors.name = "Nama promo wajib diisi";
  if (!startsAt) errors.startsAt = "Waktu mulai wajib diisi";
  if (!endsAt) errors.endsAt = "Waktu berakhir wajib diisi";
  if (startsAt && endsAt && new Date(endsAt) <= new Date(startsAt)) {
    errors.endsAt = "Waktu berakhir harus setelah waktu mulai";
  }
  // Max 90 hari dari startsAt — block client side supaya admin tidak
  // terbentur server validation di-akhir. Server juga validate sama.
  if (startsAt && endsAt) {
    const start = new Date(startsAt);
    const end = new Date(endsAt);
    const ninetyDays = 90 * 24 * 60 * 60 * 1000;
    if (end.getTime() - start.getTime() > ninetyDays) {
      errors.endsAt = "Periode maksimal 90 hari dari waktu mulai";
    }
  }
  if (items.length === 0) {
    errors.items = "Tambah minimal 1 produk";
  }
  // Validasi tiap item — harga diskon harus > 0 dan <= harga awal.
  for (const item of items) {
    const basePrice = item.variant?.price ?? item.product.price;
    if (
      !Number.isFinite(item.discountedPrice) ||
      !Number.isInteger(item.discountedPrice) ||
      item.discountedPrice > 999_999_999 ||
      (item.isItemActive && item.discountedPrice <= 0)
    ) {
      errors.itemPrice = "Semua produk aktif harus punya harga diskon > 0";
      break;
    }
    if (item.discountedPrice > basePrice) {
      errors.itemPrice = "Harga diskon tidak boleh melebihi harga awal";
      break;
    }
  }
  const canSubmit = Object.keys(errors).length === 0;

  // ── Item handlers ───────────────────────────────────────────
  function addItems(newItems: PromoItem[]) {
    // Dedupe by productId+variantId
    setItems((prev) => {
      const existing = new Set(
        prev.map((i) => `${i.productId}::${i.variantId ?? ""}`)
      );
      const filtered = newItems.filter(
        (i) => !existing.has(`${i.productId}::${i.variantId ?? ""}`)
      );
      return [...prev, ...filtered];
    });
  }

  function updateItem(
    productId: string,
    variantId: string | null,
    patch: Partial<Pick<PromoItem, "discountedPrice" | "isItemActive">>
  ) {
    setItems((prev) =>
      prev.map((i) =>
        i.productId === productId && i.variantId === variantId
          ? { ...i, ...patch }
          : i
      )
    );
  }

  function removeItem(productId: string, variantId: string | null) {
    setSelectedItems((previous) => {
      const next = new Set(previous);
      next.delete(`${productId}::${variantId ?? ""}`);
      return next;
    });
    setItems((prev) =>
      prev.filter(
        (i) => !(i.productId === productId && i.variantId === variantId)
      )
    );
  }

  /** Hapus seluruh produk (semua variannya juga). Dipakai untuk
   *  parent row Hapus action. */
  function removeProduct(productId: string) {
    setSelectedItems(
      (previous) =>
        new Set(
          [...previous].filter((key) => !key.startsWith(`${productId}::`))
        )
    );
    setItems((prev) => prev.filter((i) => i.productId !== productId));
  }

  // ── Group items by productId for display ────────────────────
  // Kalau produk berVarian: parent row + sub-rows.
  // Kalau produk tanpa varian: 1 row saja.
  const groupedItems: Array<{
    product: ProductSummary;
    items: PromoItem[];
  }> = [];
  for (const item of items) {
    const existing = groupedItems.find((g) => g.product.id === item.productId);
    if (existing) {
      existing.items.push(item);
    } else {
      groupedItems.push({ product: item.product, items: [item] });
    }
  }

  const selectedCount = items.filter((item) =>
    selectedItems.has(itemKey(item))
  ).length;
  function toggleItem(key: string) {
    setSelectedItems((previous) => {
      const next = new Set(previous);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  }
  function applyBulk() {
    const percent = Number(bulkPercent);
    if (!Number.isFinite(percent) || percent <= 0 || percent >= 100) {
      setError("Diskon harus lebih dari 0 dan kurang dari 100%.");
      return;
    }
    setError("");
    setItems((previous) =>
      previous.map((item) =>
        selectedItems.has(itemKey(item))
          ? {
              ...item,
              discountedPrice: Math.max(
                1,
                Math.round(
                  (item.variant?.price ?? item.product.price) *
                    (1 - percent / 100)
                )
              ),
            }
          : item
      )
    );
    setFeedback(`Diskon ${percent}% diterapkan pada ${selectedCount} pilihan.`);
  }
  async function leaveForm() {
    if (submitting) return;
    const dirty =
      name !== data.name ||
      startsAt !== data.startsAt ||
      endsAt !== data.endsAt ||
      JSON.stringify(items) !== JSON.stringify(data.items) ||
      notifyCustomers;
    if (
      dirty &&
      !(await confirmLeave(
        "Tinggalkan form? Perubahan yang belum disimpan akan hilang."
      ))
    )
      return;
    router.push("/admin/diskon/promo-toko");
  }
  async function handleSubmit() {
    if (submitting) return;
    setShowFieldErrors(true);
    setError("");
    if (!canSubmit) {
      setError("Periksa isian yang ditandai sebelum menyimpan.");
      requestAnimationFrame(() =>
        formFields.current
          ?.querySelector<HTMLInputElement>('input[aria-invalid="true"]')
          ?.focus()
      );
      return;
    }
    setSubmitting(true);
    try {
      const payload = {
        name: name.trim(),
        startsAt: new Date(startsAt).toISOString(),
        endsAt: new Date(endsAt).toISOString(),
        items: items.map((it) => ({
          productId: it.productId,
          variantId: it.variantId,
          discountedPrice: Math.max(0, Math.round(it.discountedPrice)),
          isItemActive: it.isItemActive,
        })),
        notifyCustomers,
      };
      const url = isEdit
        ? `/api/admin/discounts/promo-toko/${initial!.id}`
        : "/api/admin/discounts/promo-toko";
      const method = isEdit ? "PUT" : "POST";
      const res = await fetch(url, {
        method,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      const json = await res.json();
      if (!res.ok) {
        if (json.conflictingPromoNames) {
          throw new Error(
            `Produk sudah masuk Promo Toko lain: ${json.conflictingPromoNames.join(
              ", "
            )}. Hapus produk yang konflik dulu.`
          );
        }
        throw new Error(json.error ?? "Gagal menyimpan");
      }
      router.push("/admin/diskon/promo-toko");
      router.refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Gagal menyimpan");
      setSubmitting(false);
    }
  }

  return (
    <AdminPage maxWidth="xl" className="pt admin-operational-page">
      <button
        type="button"
        className="pt-back"
        disabled={submitting}
        onClick={() => void leaveForm()}
      >
        ← Promo Toko
      </button>
      <PageHeader
        title={isEdit ? "Edit Promo Toko" : "Buat Promo Toko"}
        subtitle="Atur periode dan harga spesial untuk produk pilihan."
      />
      <fieldset
        disabled={submitting}
        className="pt-form-fields"
        ref={formFields}
      >
        <section className="pt-panel">
          <div className="pt-panel-title">
            <h2>Informasi dasar</h2>
            <span>Nama promo hanya terlihat oleh admin</span>
          </div>
          <div className="pt-fields">
            <label>
              Nama promo
              <input
                value={name}
                maxLength={150}
                onChange={(e) => setName(e.target.value)}
                aria-invalid={showFieldErrors && Boolean(errors.name)}
              />
              {showFieldErrors && errors.name && (
                <em className="pt-field-error">{errors.name}</em>
              )}
            </label>
            <label>
              Mulai
              <input
                type="datetime-local"
                value={startsAt}
                disabled={isOngoing}
                onChange={(e) => setStartsAt(e.target.value)}
                aria-invalid={showFieldErrors && Boolean(errors.startsAt)}
              />
              {showFieldErrors && errors.startsAt && (
                <em className="pt-field-error">{errors.startsAt}</em>
              )}
            </label>
            <label>
              Berakhir
              <input
                type="datetime-local"
                value={endsAt}
                onChange={(e) => setEndsAt(e.target.value)}
                aria-invalid={showFieldErrors && Boolean(errors.endsAt)}
              />
              {showFieldErrors && errors.endsAt && (
                <em className="pt-field-error">{errors.endsAt}</em>
              )}
            </label>
          </div>
          {isOngoing && (
            <p className="pt-muted pt-ongoing">
              Promo sedang berjalan. Waktu mulai tidak dapat diubah.
            </p>
          )}
          {!isEdit && !isOngoing && (
            <div className="pt-period">
              <span>Durasi cepat</span>
              <button
                type="button"
                onClick={() => {
                  setStartsAt(nowDateTimeLocal());
                  if (!endsAt) setEndsAt(daysFromNowDateTimeLocal(7));
                }}
              >
                Mulai sekarang
              </button>
              {[7, 30, 90].map((days) => (
                <button
                  type="button"
                  key={days}
                  onClick={() => {
                    const start = startsAt ? new Date(startsAt) : new Date();
                    if (!startsAt) setStartsAt(toDateTimeLocalString(start));
                    const finish = new Date(start.getTime() + days * 86400000);
                    setEndsAt(toDateTimeLocalString(finish));
                  }}
                >
                  {days} hari
                </button>
              ))}
              <span className="pt-muted">Maksimal 90 hari</span>
            </div>
          )}
        </section>
        <section className="pt-panel">
          <div className="pt-panel-title">
            <div>
              <h2>Produk dalam promo</h2>
              <p>
                {groupedItems.length} produk · {items.length} pilihan
                produk/variasi
              </p>
            </div>
            <Button variant="secondary" onClick={() => setPickerOpen(true)}>
              <FiPlus /> Tambah produk
            </Button>
          </div>
          {items.length > 0 && (
            <>
              <div className="pt-bulk">
                <div>
                  <strong>Perubahan massal</strong>
                  <p>{selectedCount} dipilih</p>
                </div>
                <label className="pt-mobile-select">
                  <input
                    type="checkbox"
                    aria-label="Pilih semua item promo pada mobile"
                    checked={
                      items.length > 0 &&
                      items.every((item) => selectedItems.has(itemKey(item)))
                    }
                    onChange={(e) =>
                      setSelectedItems(
                        new Set(e.target.checked ? items.map(itemKey) : [])
                      )
                    }
                  />
                  Pilih semua
                </label>
                <label>
                  Diskon (%)
                  <input
                    aria-label="Diskon massal"
                    inputMode="decimal"
                    value={bulkPercent}
                    maxLength={5}
                    onChange={(e) => {
                      if (/^\d*(?:[.,]\d{0,2})?$/.test(e.target.value))
                        setBulkPercent(e.target.value.replace(",", "."));
                    }}
                  />
                </label>
                <Button
                  variant="secondary"
                  disabled={!selectedCount}
                  onClick={applyBulk}
                >
                  Terapkan
                </Button>
                <button
                  className="pt-text"
                  type="button"
                  disabled={!selectedCount}
                  onClick={() => {
                    setItems((previous) =>
                      previous.filter(
                        (item) => !selectedItems.has(itemKey(item))
                      )
                    );
                    setSelectedItems(new Set());
                  }}
                >
                  Hapus pilihan
                </button>
              </div>
              <div className="pt-table-head">
                <label>
                  <input
                    type="checkbox"
                    aria-label="Pilih semua item promo"
                    checked={
                      items.length > 0 &&
                      items.every((item) => selectedItems.has(itemKey(item)))
                    }
                    onChange={(e) =>
                      setSelectedItems(
                        new Set(e.target.checked ? items.map(itemKey) : [])
                      )
                    }
                  />
                  Produk / variasi
                </label>
                <span>Harga awal</span>
                <span>Harga promo</span>
                <span>Diskon (%)</span>
                <span>Stok</span>
                <span>Aktif</span>
                <span />
              </div>
            </>
          )}
          <div className="pt-groups">
            {groupedItems.map((group) => (
              <article key={group.product.id} className="pt-group">
                <header>
                  {group.product.imageUrl && (
                    <img
                      src={group.product.imageUrl}
                      width={36}
                      height={44}
                      alt=""
                      loading="lazy"
                    />
                  )}
                  <div>
                    <strong>{group.product.name}</strong>
                  </div>
                  <button
                    type="button"
                    className="pt-text"
                    onClick={() => removeProduct(group.product.id)}
                  >
                    Hapus produk
                  </button>
                </header>
                {group.items.map((item) => (
                  <PromoItemRow
                    key={itemKey(item)}
                    item={item}
                    selected={selectedItems.has(itemKey(item))}
                    onSelect={() => toggleItem(itemKey(item))}
                    onUpdate={(patch) =>
                      updateItem(item.productId, item.variantId, patch)
                    }
                    onRemove={() => removeItem(item.productId, item.variantId)}
                  />
                ))}
              </article>
            ))}
            {!items.length && (
              <div className="pt-empty">
                Belum ada produk. Tambahkan produk untuk mulai mengatur diskon.
              </div>
            )}
          </div>
          {showFieldErrors && (errors.items || errors.itemPrice) && (
            <p role="alert" className="pt-field-error">
              {errors.items || errors.itemPrice}
            </p>
          )}
        </section>
        <section className="pt-notify">
          <label>
            <input
              type="checkbox"
              checked={notifyCustomers}
              onChange={(e) => setNotifyCustomers(e.target.checked)}
            />
            <span>
              <strong>Beri tahu pelanggan</strong>
              <p>Kirim notifikasi saat promo mulai aktif.</p>
            </span>
          </label>
        </section>
      </fieldset>
      {error && (
        <p role="alert" className="pt-error">
          {error}
        </p>
      )}
      {feedback && (
        <p role="status" className="pt-success">
          {feedback}
        </p>
      )}
      <footer className="pt-save">
        <span>
          {items.filter((item) => item.isItemActive).length} pilihan aktif
        </span>
        <Button
          variant="secondary"
          disabled={submitting}
          onClick={() => void leaveForm()}
        >
          Batal
        </Button>
        <Button disabled={submitting} onClick={() => void handleSubmit()}>
          {submitting ? "Menyimpan…" : "Simpan promo"}
        </Button>
      </footer>
      <ProductPickerModal
        open={pickerOpen}
        excludeId={excludeId}
        existingItems={items}
        onClose={() => setPickerOpen(false)}
        onAdd={(newItems) => {
          addItems(newItems);
          setPickerOpen(false);
          setFeedback(`${newItems.length} pilihan ditambahkan.`);
        }}
      />
      {confirmation}
    </AdminPage>
  );
}
function itemKey(item: PromoItem) {
  return `${item.productId}::${item.variantId ?? ""}`;
}
function PromoItemRow({
  item,
  selected,
  onSelect,
  onUpdate,
  onRemove,
}: {
  item: PromoItem;
  selected: boolean;
  onSelect(): void;
  onUpdate(
    patch: Partial<Pick<PromoItem, "discountedPrice" | "isItemActive">>
  ): void;
  onRemove(): void;
}) {
  const base = item.variant?.price ?? item.product.price;
  const label = item.variant?.label ?? "Produk utama";
  const discount =
    base > 0
      ? Math.max(0, Math.round((1 - item.discountedPrice / base) * 10000) / 100)
      : 0;
  const [percentDraft, setPercentDraft] = useState<string | null>(null);
  const invalid =
    item.discountedPrice > base ||
    (item.isItemActive && item.discountedPrice <= 0);
  return (
    <div className={`pt-row ${item.isItemActive ? "" : "pt-off"}`}>
      <label className="pt-variant">
        <input
          type="checkbox"
          checked={selected}
          aria-label={`Pilih ${item.product.name} ${label}`}
          onChange={onSelect}
        />
        <span>
          <strong>{label}</strong>
          {item.variant?.sku && <small>{item.variant.sku}</small>}
        </span>
      </label>
      <div className="pt-price-original">
        <small>Harga awal</small>
        {Math.round(base).toLocaleString("id-ID")}
      </div>
      <div>
        <small>Harga promo</small>
        <NumberInput
          aria-label={`Harga promo ${item.product.name} ${label}`}
          value={String(item.discountedPrice || "")}
          maxLength={13}
          aria-invalid={invalid}
          onValueChange={(value) => {
            onUpdate({
              discountedPrice: Number(value.replace(/[^0-9]/g, "").slice(0, 9)),
            });
          }}
        />
        {invalid && (
          <em>
            Harga harus lebih dari 0 dan maksimal {base.toLocaleString("id-ID")}
          </em>
        )}
      </div>
      <div>
        <small>Diskon (%)</small>
        <input
          aria-label={`Diskon ${item.product.name} ${label}`}
          inputMode="decimal"
          maxLength={5}
          value={percentDraft ?? discount}
          onFocus={() => setPercentDraft(String(discount))}
          onBlur={() => setPercentDraft(null)}
          onChange={(e) => {
            const raw = e.target.value.replace(",", ".");
            if (!/^\d*(?:\.\d{0,2})?$/.test(raw)) return;
            const percent = Number(raw);
            if (percent >= 0 && percent < 100) {
              setPercentDraft(raw);
              onUpdate({
                discountedPrice: Math.max(
                  1,
                  Math.round(base * (1 - percent / 100))
                ),
              });
            }
          }}
        />
      </div>
      <div className="pt-stock">
        <small>Stok</small>
        {item.variant?.stock ?? item.product.stock}
      </div>
      <button
        type="button"
        role="switch"
        aria-checked={item.isItemActive}
        aria-label={`Aktifkan ${item.product.name} ${label}`}
        className="pt-switch"
        onClick={() => onUpdate({ isItemActive: !item.isItemActive })}
      >
        <span />
      </button>
      <button
        type="button"
        className="pt-icon"
        aria-label={`Hapus ${item.product.name} ${label}`}
        onClick={onRemove}
      >
        <FiTrash2 />
      </button>
    </div>
  );
}

function ProductPickerModal({
  open,
  excludeId,
  existingItems,
  onClose,
  onAdd,
}: {
  open: boolean;
  excludeId?: string;
  existingItems: PromoItem[];
  onClose: () => void;
  onAdd: (items: PromoItem[]) => void;
}) {
  const [products, setProducts] = useState<EligibleProduct[]>([]);
  const [knownProducts, setKnownProducts] = useState<EligibleProduct[]>([]);
  const [loading, setLoading] = useState(false);
  const [loadError, setLoadError] = useState("");
  const [retry, setRetry] = useState(0);
  const [search, setSearch] = useState("");
  const [categoryId, setCategoryId] = useState("");
  const [categories, setCategories] = useState<
    Array<{ id: string; name: string }>
  >([]);
  const [categoryError, setCategoryError] = useState("");
  const [availableOnly, setAvailableOnly] = useState(true);
  useEffect(() => {
    if (!open) return;
    const controller = new AbortController();
    setCategoryError("");
    void fetch("/api/categories", { signal: controller.signal })
      .then(async (response) => {
        if (!response.ok) throw new Error("Gagal memuat kategori.");
        const json = await response.json();
        if (!controller.signal.aborted) setCategories(json.categories ?? []);
      })
      .catch(() => {
        if (!controller.signal.aborted)
          setCategoryError(
            "Kategori belum dapat dimuat. Pencarian produk tetap tersedia."
          );
      });
    return () => controller.abort();
  }, [open, retry]);
  // Selected: key = "productId::variantId|nullForNoVariant"
  const [selected, setSelected] = useState<Set<string>>(new Set());

  // Existing items keys — sudah ditambah ke promo, di-grey-out di picker.
  const existingKeys = new Set(
    existingItems.map((i) => `${i.productId}::${i.variantId ?? ""}`)
  );

  useEffect(() => {
    if (!open) return;
    let cancelled = false;
    const controller = new AbortController();
    setLoading(true);
    setProducts([]);
    const fetchProducts = async () => {
      setLoading(true);
      setLoadError("");
      try {
        const params = new URLSearchParams();
        if (search.trim()) params.set("q", search.trim());
        if (excludeId) params.set("excludeId", excludeId);
        if (categoryId) params.set("categoryId", categoryId);
        const res = await fetch(
          `/api/admin/discounts/promo-toko/eligible-products?${params.toString()}`,
          { signal: controller.signal }
        );
        if (!res.ok) throw new Error("Gagal load produk");
        const json = await res.json();
        if (!cancelled) {
          const loaded: EligibleProduct[] = json.products ?? [];
          setProducts(loaded);
          setKnownProducts((previous) => {
            const byId = new Map(
              previous.map((product) => [product.id, product])
            );
            for (const product of loaded) byId.set(product.id, product);
            return Array.from(byId.values());
          });
        }
      } catch (e) {
        if (!cancelled)
          setLoadError(e instanceof Error ? e.message : "Gagal memuat produk.");
      } finally {
        if (!cancelled) setLoading(false);
      }
    };
    const debounce = setTimeout(fetchProducts, search ? 300 : 0);
    return () => {
      cancelled = true;
      clearTimeout(debounce);
      controller.abort();
    };
  }, [search, categoryId, excludeId, open, retry]);

  useEffect(() => {
    if (open) {
      setSelected(new Set());
      setKnownProducts([]);
    }
  }, [open]);

  function toggle(key: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  }

  function confirm() {
    const itemsToAdd: PromoItem[] = [];
    for (const product of knownProducts) {
      if (product.hasVariants && product.variants.length > 0) {
        // Variant product — add per varian terpilih
        for (const v of product.variants) {
          const key = `${product.id}::${v.id}`;
          if (selected.has(key) && !v.isBlocked && !existingKeys.has(key)) {
            itemsToAdd.push({
              productId: product.id,
              variantId: v.id,
              discountedPrice: v.price, // default: full price (admin akan adjust)
              isItemActive: true,
              product: {
                id: product.id,
                name: product.name,
                imageUrl: product.imageUrl,
                price: product.price,
                stock: product.stock,
              },
              variant: {
                id: v.id,
                label: v.label,
                sku: v.sku,
                price: v.price,
                stock: v.stock,
                imageUrl: v.imageUrl,
              },
            });
          }
        }
      } else {
        // Single product — variantId null
        const key = `${product.id}::`;
        if (selected.has(key) && !existingKeys.has(key)) {
          itemsToAdd.push({
            productId: product.id,
            variantId: null,
            discountedPrice: product.price,
            isItemActive: true,
            product: {
              id: product.id,
              name: product.name,
              imageUrl: product.imageUrl,
              price: product.price,
              stock: product.stock,
            },
            variant: null,
          });
        }
      }
    }
    onAdd(itemsToAdd);
  }

  const visibleProducts = products
    .map((product) => ({
      ...product,
      variants: product.variants.filter(
        (variant) => !availableOnly || variant.stock > 0
      ),
    }))
    .filter((product) =>
      product.hasVariants
        ? product.variants.length > 0
        : !availableOnly || product.stock > 0
    );
  const visibleKeys = visibleProducts.flatMap((product) =>
    product.hasVariants
      ? product.variants
          .filter(
            (variant) =>
              !variant.isBlocked &&
              !existingKeys.has(`${product.id}::${variant.id}`)
          )
          .map((variant) => `${product.id}::${variant.id}`)
      : existingKeys.has(`${product.id}::`)
      ? []
      : [`${product.id}::`]
  );
  function pickAll(checked: boolean) {
    setSelected((previous) => {
      const next = new Set(previous);
      for (const key of visibleKeys) {
        if (checked) next.add(key);
        else next.delete(key);
      }
      return next;
    });
  }
  return (
    <AdminDialog
      open={open}
      title="Pilih produk"
      onClose={onClose}
      className="pt-picker"
      footer={
        <>
          <span className="pt-selection-count">{selected.size} dipilih</span>
          <Button variant="secondary" onClick={onClose}>
            Batal
          </Button>
          <Button
            onClick={confirm}
            disabled={!selected.size || loading || Boolean(loadError)}
          >
            Tambahkan ({selected.size})
          </Button>
        </>
      }
    >
      <div className="pt-pick-filters">
        <label>
          Kategori
          <select
            value={categoryId}
            onChange={(e) => setCategoryId(e.target.value)}
            disabled={!categories.length}
          >
            <option value="">Semua kategori</option>
            {categories.map((category) => (
              <option key={category.id} value={category.id}>
                {category.name}
              </option>
            ))}
          </select>
        </label>
        <label>
          Cari produk
          <div className="pt-search">
            <FiSearch aria-hidden />
            <input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Nama produk, brand atau SKU"
            />
          </div>
        </label>
      </div>
      {categoryError && (
        <p role="status" className="pt-field-error">
          {categoryError}
          <button
            type="button"
            className="pt-text"
            onClick={() => setRetry((value) => value + 1)}
          >
            Coba lagi
          </button>
        </p>
      )}
      <div className="pt-pick-toolbar">
        <label>
          <input
            type="checkbox"
            checked={availableOnly}
            onChange={(e) => setAvailableOnly(e.target.checked)}
          />
          Hanya produk dengan stok tersedia
        </label>
        <button
          type="button"
          className="pt-text"
          onClick={() => {
            setSearch("");
            setCategoryId("");
            setAvailableOnly(true);
          }}
        >
          Atur ulang filter
        </button>
      </div>
      <div className="pt-pick-head">
        <label>
          <input
            type="checkbox"
            aria-label="Pilih semua produk yang tersedia di hasil"
            checked={
              visibleKeys.length > 0 &&
              visibleKeys.every((key) => selected.has(key))
            }
            disabled={loading || !visibleKeys.length || Boolean(loadError)}
            onChange={(e) => pickAll(e.target.checked)}
          />
          Produk / variasi
        </label>
        <span>Harga awal</span>
        <span>Stok</span>
      </div>
      <div className="pt-pick-results" aria-busy={loading}>
        {loading ? (
          <p role="status" className="pt-empty">
            Memuat produk…
          </p>
        ) : loadError ? (
          <div role="alert" className="pt-empty">
            {loadError}
            <button
              type="button"
              className="pt-text"
              onClick={() => setRetry((n) => n + 1)}
            >
              Coba lagi
            </button>
          </div>
        ) : !visibleProducts.length ? (
          <p className="pt-empty">
            Tidak ada produk yang cocok. Coba kata kunci atau filter lain.
          </p>
        ) : (
          visibleProducts.map((product) => {
            const rows = product.hasVariants
              ? product.variants
              : [
                  {
                    id: "",
                    label: "Produk utama",
                    price: product.price,
                    stock: product.stock,
                    isBlocked: false,
                  },
                ];
            return (
              <article key={product.id}>
                <header>
                  {product.imageUrl && (
                    <img
                      src={product.imageUrl}
                      alt=""
                      width={36}
                      height={44}
                      loading="lazy"
                    />
                  )}
                  <div>
                    <strong>{product.name}</strong>
                    <p>
                      {product.category?.name ?? "Tanpa kategori"} ·{" "}
                      {rows.length} pilihan
                    </p>
                  </div>
                </header>
                {rows.map((variant) => {
                  const key = `${product.id}::${variant.id}`;
                  const existing = existingKeys.has(key);
                  const disabled = existing || variant.isBlocked;
                  return (
                    <label
                      key={key}
                      className={`pt-pick-row ${disabled ? "pt-added" : ""}`}
                    >
                      <span>
                        <input
                          type="checkbox"
                          disabled={disabled}
                          checked={selected.has(key)}
                          onChange={() => toggle(key)}
                        />
                        {variant.label}
                        {disabled && (
                          <em>
                            {existing ? "Sudah ditambahkan" : "Di promo lain"}
                          </em>
                        )}
                      </span>
                      <span>{variant.price.toLocaleString("id-ID")}</span>
                      <span>{variant.stock}</span>
                    </label>
                  );
                })}
              </article>
            );
          })
        )}
      </div>
      <p className="pt-result-note">
        Menampilkan maksimal 200 produk. Gunakan pencarian untuk menemukan
        produk lainnya.
      </p>
    </AdminDialog>
  );
}

// ── Helpers ──────────────────────────────────────────────────────

/** Convert Date ke string format datetime-local input (YYYY-MM-DDTHH:MM
 *  in LOCAL time, no timezone suffix). Pakai untuk default value form. */
function toDateTimeLocalString(d: Date): string {
  const local = new Date(d.getTime() - d.getTimezoneOffset() * 60000);
  return local.toISOString().slice(0, 16);
}

function nowDateTimeLocal(): string {
  return toDateTimeLocalString(new Date());
}

function daysFromNowDateTimeLocal(days: number): string {
  const d = new Date();
  d.setDate(d.getDate() + days);
  return toDateTimeLocalString(d);
}
