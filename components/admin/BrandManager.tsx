"use client";
import React, {
  useRef,
  useState,
  type CSSProperties,
  type ReactNode,
} from "react";
import { AdminPage, Button, Badge, useAdminToast } from "@/components/admin/ui";
import { AdminDialog } from "@/components/admin/ui/AdminDialog";
import { LayoutMotion, adminMotionAllowed } from "@/components/admin/ui/Motion";

import { uploadAdminImage } from "@/lib/admin-image-upload";
export type ManagedBrand = {
  id: string;
  name: string;
  slug: string;
  products: number;
  position: number;
  active: boolean;
  hasLogo: boolean;
  logoUrl: string | null;
  color?: string;
};
type Draft = Omit<ManagedBrand, "id"> & { id: string | null };
type Props = {
  initialBrands: ManagedBrand[];
  initialEditId?: string;
  needsReviewCount: number;
  noBrandCount: number;
  saveBrandAction: (data: FormData) => Promise<ManagedBrand>;
  saveOrderAction: (data: FormData) => Promise<void>;
  deleteBrandAction: (id: string) => Promise<void>;
};
type Ghost = {
  brand: ManagedBrand;
  x: number;
  y: number;
  width: number;
  height: number;
};
const slugify = (name: string) =>
  name
    .toLowerCase()
    .replace(/&/g, "and")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
const move = (list: string[], from: number, to: number) => {
  const next = [...list];
  const [item] = next.splice(from, 1);
  next.splice(to, 0, item);
  return next;
};

function Icon({ name }: { name: string }) {
  const paths: Record<string, ReactNode> = {
    search: (
      <>
        <circle cx="10.5" cy="10.5" r="6.5" />
        <path d="m16 16 4 4" />
      </>
    ),
    plus: <path d="M12 5v14M5 12h14" />,
    image: (
      <>
        <rect x="3" y="4" width="18" height="16" rx="3" />
        <path d="m3 16 5-5 5 5 3-3 5 5" />
        <circle cx="16" cy="9" r="1" />
      </>
    ),
    edit: (
      <>
        <path d="m15 4 5 5-10 10-6 1 1-6zM13 6l5 5" />
      </>
    ),
    check: <path d="m5 12 4 4L19 6" />,
    grid: (
      <>
        <rect x="3" y="3" width="7" height="7" rx="1" />
        <rect x="14" y="3" width="7" height="7" rx="1" />
        <rect x="3" y="14" width="7" height="7" rx="1" />
        <rect x="14" y="14" width="7" height="7" rx="1" />
      </>
    ),
    grip: <path d="M9 5h.01M15 5h.01M9 12h.01M15 12h.01M9 19h.01M15 19h.01" />,
  };
  return (
    <svg
      viewBox="0 0 24 24"
      width="18"
      height="18"
      fill="none"
      stroke="currentColor"
      strokeWidth={name === "grip" ? 3 : 1.7}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {paths[name] || paths.image}
    </svg>
  );
}
function Logo({ brand }: { brand: Draft }) {
  return (
    <span
      className={`bm-logo ${!brand.hasLogo ? "bm-logo-empty" : ""}`}
      style={{ "--brand-color": brand.color || "#46698c" } as CSSProperties}
    >
      {brand.logoUrl ? (
        <img src={brand.logoUrl} alt={`Logo ${brand.name}`} />
      ) : brand.hasLogo ? (
        <span>
          {brand.name
            .split(/[ /&]+/)
            .filter(Boolean)
            .map((word) => word[0])
            .slice(0, 2)
            .join("")}
        </span>
      ) : (
        <Icon name="image" />
      )}
    </span>
  );
}

export default function BrandManager({
  initialBrands,
  initialEditId,
  needsReviewCount,
  noBrandCount,
  saveBrandAction,
  saveOrderAction,
  deleteBrandAction,
}: Props) {
  const seed = initialBrands;
  const { show } = useAdminToast();
  const [brands, setBrands] = useState(seed);
  const [tab, setTab] = useState("all");
  const [query, setQuery] = useState("");
  const [filter, setFilter] = useState("all");
  const [sort, setSort] = useState("name");
  const [order, setOrder] = useState(
    seed
      .filter((b) => b.active && b.hasLogo)
      .sort(
        (a, b) => a.position - b.position || a.name.localeCompare(b.name, "id")
      )
      .slice(0, 8)
      .map((b) => b.id)
  );
  const [saved, setSaved] = useState(order);
  const [form, setForm] = useState<Draft | null>(
    () => initialBrands.find((brand) => brand.id === initialEditId) || null
  );
  const [error, setError] = useState("");
  const [ghost, setGhost] = useState<Ghost | null>(null);
  const [announcement, setAnnouncement] = useState("");
  const [leaveOpen, setLeaveOpen] = useState(false);
  const [deleteOpen, setDeleteOpen] = useState(false);
  const [replaceId, setReplaceId] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [orderBusy, setOrderBusy] = useState(false);
  const [replacementQuery, setReplacementQuery] = useState("");
  const drag = useRef<{
    id: string;
    offsetX: number;
    offsetY: number;
    before: string[];
  } | null>(null);
  const upload = useRef<HTMLInputElement>(null);
  const overlay = useRef<HTMLDivElement>(null);
  const dirty = order.join("|") !== saved.join("|");
  const primary = order
    .map((id) => brands.find((brand) => brand.id === id))
    .filter((b): b is ManagedBrand => Boolean(b));
  const matches = brands.filter(
    (brand) =>
      brand.name.toLowerCase().includes(query.toLowerCase()) &&
      (filter === "all" ||
        (filter === "active" && brand.active) ||
        (filter === "archived" && !brand.active) ||
        (filter === "no-logo" && !brand.hasLogo) ||
        (filter === "primary" && order.includes(brand.id)))
  );
  const visible = [...matches].sort((a, b) =>
    sort === "products"
      ? b.products - a.products
      : a.name.localeCompare(b.name, "id")
  );

  function openForm(brand: ManagedBrand | null) {
    if (orderBusy) return;
    setError("");
    setForm(
      brand
        ? { ...brand }
        : {
            id: null,
            slug: "",
            position: 1000,
            name: "",
            products: 0,
            color: "#58739b",
            hasLogo: false,
            logoUrl: null,
            active: true,
          }
    );
  }
  async function saveForm(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!form || busy) return;
    const name = form.name.trim();
    if (!name) {
      setError("Nama brand harus diisi.");
      return;
    }
    if (
      brands.some(
        (brand) =>
          brand.id !== form.id &&
          brand.name.toLowerCase() === name.toLowerCase()
      )
    ) {
      setError("Nama brand sudah digunakan.");
      return;
    }
    setBusy(true);
    try {
      const data = new FormData();
      data.set("id", form.id || "");
      data.set("name", name);
      data.set("logoUrl", form.logoUrl || "");
      data.set("isActive", form.active ? "on" : "");
      const value = await saveBrandAction(data);
      setBrands((p) =>
        form.id ? p.map((b) => (b.id === form.id ? value : b)) : [...p, value]
      );
      if (!value.active || !value.hasLogo) {
        setOrder((p) => p.filter((id) => id !== value.id));
        setSaved((p) => p.filter((id) => id !== value.id));
      }
      setForm(null);
      show("Brand berhasil disimpan.");
    } catch (e) {
      setError(e instanceof Error ? e.message : "Gagal menyimpan brand.");
    } finally {
      setBusy(false);
    }
  }
  async function persistOrder() {
    if (orderBusy) return false;
    setOrderBusy(true);
    try {
      const d = new FormData();
      d.set("orderedIds", JSON.stringify(order));
      await saveOrderAction(d);
      setSaved([...order]);
      show("Urutan berhasil disimpan.");
      return true;
    } catch {
      show("Gagal menyimpan urutan. Coba kembali.");
      return false;
    } finally {
      setOrderBusy(false);
    }
  }
  function addPrimary(brand: ManagedBrand) {
    if (orderBusy) return;
    if (order.length >= 8) {
      show(
        "Delapan posisi sudah terisi. Pilih Ganti brand pada posisi yang diinginkan."
      );
      return;
    }
    setOrder((previous) => [...previous, brand.id]);
    setAnnouncement(`${brand.name} ditambahkan ke urutan utama.`);
  }
  function keyboardMove(
    event: React.KeyboardEvent<HTMLButtonElement>,
    id: string
  ) {
    if (event.key === "Escape" && drag.current) {
      event.preventDefault();
      finishDrag(true);
      return;
    }
    if (drag.current || orderBusy) return;
    const keys = ["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"];
    if (!keys.includes(event.key)) return;
    event.preventDefault();
    const from = order.indexOf(id);
    const grid = event.currentTarget.closest(".bm-order-grid");
    const columns = getComputedStyle(grid!).gridTemplateColumns.split(
      " "
    ).length;
    const step =
      event.key === "ArrowLeft"
        ? -1
        : event.key === "ArrowRight"
        ? 1
        : event.key === "ArrowUp"
        ? -columns
        : columns;
    const to = Math.max(0, Math.min(order.length - 1, from + step));
    if (from === to) return;
    setOrder(move(order, from, to));
    setAnnouncement(
      `${brands.find((brand) => brand.id === id)?.name}, urutan ${to + 1}.`
    );
  }
  function startDrag(
    event: React.PointerEvent<HTMLButtonElement>,
    brand: ManagedBrand
  ) {
    if (event.button !== 0 || orderBusy) return;
    if (ghost && !drag.current) return;
    const rect = event.currentTarget
      .closest("[data-brand-id]")!
      .getBoundingClientRect();
    event.currentTarget.setPointerCapture(event.pointerId);
    drag.current = {
      id: brand.id,
      offsetX: event.clientX - rect.left,
      offsetY: event.clientY - rect.top,
      before: [...order],
    };
    setGhost({
      brand,
      x: rect.left,
      y: rect.top,
      width: rect.width,
      height: rect.height,
    });
  }
  function dragMove(event: React.PointerEvent<HTMLButtonElement>) {
    if (!drag.current) return;
    const current = drag.current;
    setGhost(
      (previous) =>
        previous && {
          ...previous,
          x: event.clientX - current.offsetX,
          y: event.clientY - current.offsetY,
        }
    );
    const hit = document
      .elementFromPoint(event.clientX, event.clientY)
      ?.closest<HTMLElement>("[data-brand-id]");
    if (hit && hit.dataset.brandId !== current.id)
      setOrder((previous) => {
        const from = previous.indexOf(current.id),
          to = previous.indexOf(hit.dataset.brandId || "");
        return from < 0 || to < 0 ? previous : move(previous, from, to);
      });
  }
  function finishDrag(cancel = false) {
    if (!drag.current) return;
    if (cancel) setOrder(drag.current.before);
    setAnnouncement(
      cancel ? "Pengurutan dibatalkan." : "Posisi brand diperbarui."
    );
    const card = document.querySelector(`[data-brand-id="${drag.current.id}"]`);
    drag.current = null;
    if (!cancel && ghost && card && overlay.current && adminMotionAllowed()) {
      const rect = card.getBoundingClientRect();
      const transform = getComputedStyle(card).transform;
      const matrix =
        transform === "none" ? null : new DOMMatrixReadOnly(transform);
      const dx = rect.left - (matrix?.m41 || 0) - ghost.x,
        dy = rect.top - (matrix?.m42 || 0) - ghost.y;
      const animation = overlay.current.animate(
        [
          { transform: "scale(1.03)" },
          { transform: `translate(${dx}px,${dy}px) scale(1)` },
        ],
        { duration: 160, easing: "cubic-bezier(.2,.8,.2,1)", fill: "forwards" }
      );
      void animation.finished
        .then(() => setGhost(null))
        .catch(() => setGhost(null));
    } else setGhost(null);
  }
  function changeTab(next: string) {
    if (next === "all" && dirty) {
      setLeaveOpen(true);
      return;
    }
    setTab(next);
  }

  return (
    <AdminPage maxWidth="xl" className="brand-mockup">
      <div className="bm-heading">
        <div>
          <span className="bm-eyebrow">KATALOG</span>
          <h1>Brand</h1>
          <p>Kelola identitas brand dan urutannya di aplikasi.</p>
        </div>
        <div className="bm-heading-actions">
          <Button onClick={() => openForm(null)}>
            <Icon name="plus" /> Tambah brand
          </Button>
        </div>
      </div>
      <div className="bm-summary">
        {[
          {
            label: "Total brand",
            value: brands.length,
            icon: "grid",
            filter: "all",
          },
          {
            label: "Brand aktif",
            value: brands.filter((brand) => brand.active).length,
            icon: "check",
            filter: "active",
          },
          {
            label: "Belum ada logo",
            value: brands.filter((brand) => !brand.hasLogo).length,
            icon: "image",
            filter: "no-logo",
          },
          {
            label: "Produk perlu konfirmasi",
            value: needsReviewCount,
            icon: "edit",
            filter: null,
          },
        ].map((item) => (
          <button
            key={item.label}
            type="button"
            className="bm-stat"
            onClick={() => {
              if (item.filter) {
                changeTab("all");
                setFilter(item.filter);
                setQuery("");
              } else window.location.assign("/admin/brands/review");
            }}
          >
            <span className="bm-stat-icon">
              <Icon name={item.icon} />
            </span>
            <span>
              <span className="bm-stat-label">{item.label}</span>
              <strong>{item.value.toLocaleString("id-ID")}</strong>
            </span>
          </button>
        ))}
      </div>
      {noBrandCount > 0 && (
        <a className="bm-no-brand" href="/admin/products?brand=none">
          {noBrandCount} produk tanpa brand · Lihat produk
        </a>
      )}
      <section className="bm-panel">
        <div className="bm-tabbar">
          <div className="bm-tabs" aria-label="Tampilan brand">
            {[
              ["all", "Semua Brand"],
              ["order", "8 Brand Utama"],
            ].map(([key, label]) => (
              <button
                key={key}
                type="button"
                aria-pressed={tab === key}
                onClick={() => changeTab(key)}
              >
                {label}
              </button>
            ))}
          </div>
          <span className="bm-muted">
            {tab === "all"
              ? `${brands.length} brand`
              : `${order.length} / 8 posisi terisi`}
          </span>
        </div>
        {tab === "all" ? (
          <>
            <div className="bm-toolbar">
              <label className="bm-search">
                <Icon name="search" />
                <input
                  aria-label="Cari brand"
                  placeholder="Cari nama brand…"
                  value={query}
                  onChange={(event) => setQuery(event.target.value)}
                />
                {query && (
                  <button
                    type="button"
                    aria-label="Hapus pencarian"
                    onClick={() => setQuery("")}
                  >
                    ×
                  </button>
                )}
              </label>
              <select
                aria-label="Filter brand"
                value={filter}
                onChange={(event) => setFilter(event.target.value)}
              >
                <option value="all">Semua status</option>
                <option value="active">Aktif</option>
                <option value="archived">Nonaktif</option>
                <option value="no-logo">Tanpa logo</option>
                <option value="primary">Brand utama</option>
              </select>
              <select
                aria-label="Urutkan brand"
                value={sort}
                onChange={(event) => setSort(event.target.value)}
              >
                <option value="name">Nama A–Z</option>
                <option value="products">Produk terbanyak</option>
              </select>
            </div>
            <div className="bm-list-header">
              <span>Brand</span>
              <span>Produk</span>
              <span>Status</span>
              <span>Aksi</span>
            </div>
            <div className="bm-list">
              {visible.map((brand) => (
                <div className="bm-row" key={brand.id}>
                  <div className="bm-identity">
                    <Logo brand={brand} />
                    <div>
                      <button
                        className="bm-name"
                        type="button"
                        onClick={() => openForm(brand)}
                      >
                        {brand.name}
                      </button>
                      <div className="bm-row-meta">
                        {order.includes(brand.id) ? (
                          <span>Utama #{order.indexOf(brand.id) + 1}</span>
                        ) : (
                          <span>/{slugify(brand.name)}</span>
                        )}
                        {!brand.hasLogo && (
                          <span className="bm-warning">Tanpa logo</span>
                        )}
                      </div>
                    </div>
                  </div>
                  <a
                    href={`/admin/products?brand=${encodeURIComponent(
                      brand.slug
                    )}`}
                    className="bm-product-count"
                  >
                    {brand.products} <span>produk</span>
                  </a>
                  <span className="bm-status">
                    <Badge variant={brand.active ? "success" : "neutral"}>
                      {brand.active ? "Aktif" : "Nonaktif"}
                    </Badge>
                  </span>
                  <Button
                    variant="secondary"
                    size="sm"
                    onClick={() => openForm(brand)}
                  >
                    <Icon name="edit" /> Edit
                  </Button>
                </div>
              ))}
            </div>
            {!visible.length && (
              <div className="bm-empty">
                <Icon name="search" />
                <h2>Brand tidak ditemukan</h2>
                <p>Coba nama lain atau tampilkan semua brand.</p>
                <Button
                  variant="secondary"
                  onClick={() => {
                    setQuery("");
                    setFilter("all");
                  }}
                >
                  Reset pencarian
                </Button>
              </div>
            )}
            <div className="bm-list-footer" role="status">
              {visible.length} dari {brands.length} brand
            </div>
          </>
        ) : (
          <div className="bm-order-body">
            <div className="bm-order-heading">
              <div>
                <h2>Delapan shortcut pilihan</h2>
                <p>
                  Posisi 1–8 mengikuti susunan ini. Daftar semua brand di
                  aplikasi tetap A–Z.
                </p>
              </div>
              <span className="bm-soft-badge">{order.length} brand</span>
            </div>
            <LayoutMotion revision={order.join("|")} className="bm-order-grid">
              {primary.map((brand, index) => (
                <div
                  key={brand.id}
                  data-motion-key={brand.id}
                  data-brand-id={brand.id}
                  className={`bm-order-card ${
                    ghost?.brand.id === brand.id ? "bm-lifted" : ""
                  }`}
                >
                  <span className="bm-order-number">{index + 1}</span>
                  <Logo brand={brand} />
                  <strong>{brand.name}</strong>
                  <button
                    type="button"
                    disabled={orderBusy}
                    className="bm-replace-button"
                    aria-label={`Ganti brand posisi ${index + 1}: ${
                      brand.name
                    }`}
                    onClick={() => {
                      setReplaceId(brand.id);
                      setReplacementQuery("");
                    }}
                  >
                    Ganti brand
                  </button>
                  <button
                    type="button"
                    className="bm-drag-handle"
                    aria-label={`Atur urutan ${brand.name}`}
                    onKeyDown={(event) => keyboardMove(event, brand.id)}
                    onPointerDown={(event) => startDrag(event, brand)}
                    onPointerMove={dragMove}
                    onPointerUp={() => finishDrag()}
                    onPointerCancel={() => finishDrag(true)}
                    onLostPointerCapture={() => finishDrag()}
                  >
                    <Icon name="grip" />
                  </button>
                </div>
              ))}
            </LayoutMotion>
            <div className="bm-order-other">
              <h3>Brand lainnya</h3>
              <p className="bm-other-description">
                Brand aktif tetap tersedia di daftar semua brand.
              </p>
              <div>
                {brands
                  .filter((brand) => !order.includes(brand.id))
                  .sort((a, b) => a.name.localeCompare(b.name, "id"))
                  .map((brand) => (
                    <div className="bm-other-row" key={brand.id}>
                      <Logo brand={brand} />
                      <strong>{brand.name}</strong>
                      {brand.active && brand.hasLogo ? (
                        order.length < 8 ? (
                          <Button
                            variant="secondary"
                            size="sm"
                            onClick={() => addPrimary(brand)}
                          >
                            Tambah ke utama
                          </Button>
                        ) : (
                          <span className="bm-available">Siap dipilih</span>
                        )
                      ) : (
                        <Button
                          variant="secondary"
                          size="sm"
                          onClick={() => openForm(brand)}
                        >
                          {!brand.hasLogo ? "Lengkapi logo" : "Edit brand"}
                        </Button>
                      )}
                    </div>
                  ))}
              </div>
            </div>
            <div className="bm-order-save">
              <span className={dirty ? "bm-unsaved" : "bm-muted"} role="status">
                {dirty ? "Ada perubahan belum disimpan" : "Urutan tersimpan"}
              </span>
              <div>
                <Button
                  variant="secondary"
                  disabled={!dirty || orderBusy}
                  onClick={() => setOrder([...saved])}
                >
                  Batalkan
                </Button>
                <Button
                  disabled={!dirty || orderBusy}
                  onClick={() => void persistOrder()}
                >
                  Simpan urutan
                </Button>
              </div>
            </div>
          </div>
        )}
      </section>
      <AdminDialog
        open={replaceId !== null}
        title={`Ganti brand posisi ${order.indexOf(replaceId || "") + 1}`}
        onClose={() => setReplaceId(null)}
        className="bm-picker-dialog"
      >
        <p className="bm-picker-description">
          Menggantikan {brands.find((brand) => brand.id === replaceId)?.name}.
          Brand sebelumnya tetap tersedia di daftar semua brand.
        </p>
        <label className="bm-search">
          <Icon name="search" />
          <input
            data-dialog-autofocus
            aria-label="Cari pengganti brand"
            placeholder="Cari brand pengganti…"
            value={replacementQuery}
            onChange={(event) => setReplacementQuery(event.target.value)}
          />
        </label>
        <div className="bm-picker-list">
          {brands
            .filter(
              (brand) =>
                !order.includes(brand.id) &&
                brand.name
                  .toLowerCase()
                  .includes(replacementQuery.toLowerCase())
            )
            .sort((a, b) => a.name.localeCompare(b.name, "id"))
            .map((brand) => (
              <button
                type="button"
                key={brand.id}
                disabled={!brand.active || !brand.hasLogo}
                onClick={() => {
                  setOrder((previous) =>
                    previous.map((id) => (id === replaceId ? brand.id : id))
                  );
                  setAnnouncement(`${brand.name} dipilih sebagai brand utama.`);
                  setReplaceId(null);
                }}
              >
                <Logo brand={brand} />
                <span>
                  <strong>{brand.name}</strong>
                  <small>
                    {!brand.active
                      ? "Nonaktif"
                      : !brand.hasLogo
                      ? "Lengkapi logo terlebih dahulu"
                      : `${brand.products} produk`}
                  </small>
                </span>
                {brand.active && brand.hasLogo && (
                  <span className="bm-picker-action">Pilih</span>
                )}
              </button>
            ))}
          {!brands.some(
            (brand) =>
              !order.includes(brand.id) &&
              brand.name.toLowerCase().includes(replacementQuery.toLowerCase())
          ) && <p className="bm-picker-description">Brand tidak ditemukan.</p>}
        </div>
      </AdminDialog>
      <span className="sr-only" role="status" aria-live="polite">
        {announcement}
      </span>
      {ghost && (
        <div
          ref={overlay}
          className="bm-drag-overlay"
          style={{
            left: ghost.x,
            top: ghost.y,
            width: ghost.width,
            height: ghost.height,
          }}
        >
          <Logo brand={ghost.brand} />
          <strong>{ghost.brand.name}</strong>
        </div>
      )}
      <AdminDialog
        open={Boolean(form)}
        title={form?.id ? "Edit brand" : "Tambah brand"}
        side
        busy={busy}
        onClose={() => setForm(null)}
        className="bm-editor-dialog"
        footer={
          <>
            <Button
              disabled={busy}
              variant="secondary"
              onClick={() => setForm(null)}
            >
              Batal
            </Button>
            <Button disabled={busy} type="submit" form="brand-mockup-form">
              {form?.id ? "Simpan perubahan" : "Tambah brand"}
            </Button>
          </>
        }
      >
        {form && (
          <form
            id="brand-mockup-form"
            className="bm-editor"
            onSubmit={saveForm}
          >
            <section>
              <h3>Logo brand</h3>
              <div className="bm-upload">
                <Logo brand={form} />
                <div>
                  <Button
                    disabled={busy}
                    variant="secondary"
                    type="button"
                    onClick={() => upload.current?.click()}
                  >
                    {form.hasLogo ? "Ganti logo" : "Unggah logo"}
                  </Button>
                  {form.hasLogo && (
                    <button
                      type="button"
                      className="bm-text-button"
                      disabled={busy}
                      onClick={() =>
                        setForm({ ...form, hasLogo: false, logoUrl: null })
                      }
                    >
                      Hapus logo
                    </button>
                  )}
                </div>
              </div>
            </section>
            <section>
              <h3>Informasi brand</h3>
              <label>
                Nama brand <span className="bm-required">*</span>
                <input
                  data-dialog-autofocus
                  disabled={busy}
                  value={form.name}
                  onChange={(event) => {
                    setForm({ ...form, name: event.target.value });
                    setError("");
                  }}
                  placeholder="Contoh: Royal Canin"
                  required
                  maxLength={80}
                />
              </label>
              <label className="bm-check">
                <input
                  type="checkbox"
                  disabled={busy}
                  checked={form.active}
                  onChange={(event) =>
                    setForm({ ...form, active: event.target.checked })
                  }
                />
                <span>
                  Aktif di aplikasi
                  <small>Brand tersedia untuk pelanggan.</small>
                </span>
              </label>
            </section>
            <input
              ref={upload}
              type="file"
              accept="image/png,image/jpeg,image/webp,image/gif"
              className="sr-only"
              aria-label="Pilih logo brand"
              onChange={async (event) => {
                const input = event.currentTarget;
                const file = event.target.files?.[0];
                if (!file) return;
                setBusy(true);
                setError("");
                try {
                  const url = await uploadAdminImage(file, {
                    fields: { kind: "brand-logo" },
                    preserveFormat: true,
                  });
                  setForm((p) => p && { ...p, hasLogo: true, logoUrl: url });
                } catch (e) {
                  setError(e instanceof Error ? e.message : "Upload gagal.");
                } finally {
                  setBusy(false);
                  input.value = "";
                }
              }}
            />
            <details className="bm-advanced">
              <summary>Pengaturan lanjutan</summary>
              <label>
                Slug
                <input value={form.slug || slugify(form.name)} readOnly />
              </label>
              {form.id && (
                <Button
                  type="button"
                  variant="secondary"
                  onClick={() => setDeleteOpen(true)}
                >
                  Hapus brand
                </Button>
              )}
            </details>
            {error && (
              <p className="bm-error" role="alert">
                {error}
              </p>
            )}
            <div className="bm-app-preview">
              <span>PRATINJAU BRAND</span>
              <div>
                <Logo brand={form} />
                <strong>{form.name || "Nama brand"}</strong>
                <span>›</span>
              </div>
            </div>
          </form>
        )}
      </AdminDialog>
      <AdminDialog
        open={deleteOpen}
        busy={busy}
        title="Hapus brand?"
        onClose={() => setDeleteOpen(false)}
        footer={
          <>
            <Button
              disabled={busy}
              variant="secondary"
              onClick={() => setDeleteOpen(false)}
            >
              Batal
            </Button>
            <Button
              disabled={busy}
              onClick={async () => {
                if (!form?.id || busy) return;
                setBusy(true);
                try {
                  const id = form.id;
                  await deleteBrandAction(id);
                  setBrands((p) => p.filter((b) => b.id !== id));
                  setOrder((p) => p.filter((b) => b !== id));
                  setSaved((p) => p.filter((b) => b !== id));
                  setDeleteOpen(false);
                  setForm(null);
                  show("Brand berhasil dihapus.");
                } catch {
                  setError("Gagal menghapus brand. Coba kembali.");
                  setDeleteOpen(false);
                } finally {
                  setBusy(false);
                }
              }}
            >
              {busy ? "Menghapus…" : "Hapus brand"}
            </Button>
          </>
        }
      >
        <p>
          Hapus {form?.name}? {form?.products} produk akan kehilangan label
          brand. Produk tetap tersimpan.
        </p>
      </AdminDialog>
      <AdminDialog
        open={leaveOpen}
        busy={orderBusy}
        title="Simpan perubahan urutan?"
        onClose={() => setLeaveOpen(false)}
        footer={
          <>
            <Button
              variant="secondary"
              disabled={orderBusy}
              onClick={() => {
                setOrder([...saved]);
                setLeaveOpen(false);
                setTab("all");
              }}
            >
              Buang perubahan
            </Button>
            <Button
              disabled={orderBusy}
              onClick={async () => {
                if (await persistOrder()) {
                  setLeaveOpen(false);
                  setTab("all");
                }
              }}
            >
              Simpan dan lanjut
            </Button>
          </>
        }
      >
        <p>Urutan brand belum disimpan.</p>
      </AdminDialog>
    </AdminPage>
  );
}
