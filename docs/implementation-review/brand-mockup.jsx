import React, { useEffect, useRef, useState } from "react";
import {
  AdminPage,
  Button,
  Badge,
  useAdminToast,
} from "../../components/admin/ui";
import { AdminDialog } from "../../components/admin/ui/AdminDialog";
import {
  LayoutMotion,
  adminMotionAllowed,
} from "../../components/admin/ui/Motion";

const seed = [
  ["Royal Canin", 164, "#bc2635", true],
  ["Pro Plan", 42, "#343b48", true],
  ["Angels Pet", 57, "#b28b32", true],
  ["CIAO / INABA", 19, "#c53e40", true],
  ["Acana", 6, "#466443", true],
  ["Friskies", 21, "#b67b14", true],
  ["Happy Dog", 54, "#47638a", true],
  ["Happy Cat", 36, "#86558a", true],
  ["Kaniva", 11, "#718967", false],
  ["Animal & Co", 22, "#735c9a", true],
  ["Meong", 2, "#468383", false],
  ["Bioline", 2, "#638569", false],
].map(([name, products, color, hasLogo], index) => ({
  id: `brand-demo-${index}`,
  name,
  products,
  color,
  hasLogo,
  logoUrl: null,
  active: index !== 11,
}));
const slugify = (name) =>
  name
    .toLowerCase()
    .replace(/&/g, "and")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
const move = (list, from, to) => {
  const next = [...list];
  const [item] = next.splice(from, 1);
  next.splice(to, 0, item);
  return next;
};

function Icon({ name }) {
  const paths = {
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
function Logo({ brand }) {
  return (
    <span
      className={`bm-logo ${!brand.hasLogo ? "bm-logo-empty" : ""}`}
      style={{ "--brand-color": brand.color }}
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

export default function BrandMockup() {
  const { show } = useAdminToast();
  const [brands, setBrands] = useState(seed);
  const [tab, setTab] = useState("all");
  const [query, setQuery] = useState("");
  const [filter, setFilter] = useState("all");
  const [sort, setSort] = useState("name");
  const [order, setOrder] = useState(seed.slice(0, 8).map((item) => item.id));
  const [saved, setSaved] = useState(order);
  const [form, setForm] = useState(null);
  const [error, setError] = useState("");
  const [ghost, setGhost] = useState(null);
  const [announcement, setAnnouncement] = useState("");
  const [leaveOpen, setLeaveOpen] = useState(false);
  const [replaceId, setReplaceId] = useState(null);
  const [replacementQuery, setReplacementQuery] = useState("");
  const drag = useRef(null),
    upload = useRef(null),
    urls = useRef([]),
    overlay = useRef(null);
  useEffect(
    () => () => urls.current.forEach((url) => URL.revokeObjectURL(url)),
    []
  );
  const dirty = order.join("|") !== saved.join("|");
  const primary = order
    .map((id) => brands.find((brand) => brand.id === id))
    .filter(Boolean);
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

  function openForm(brand) {
    setError("");
    setForm(
      brand
        ? { ...brand }
        : {
            id: null,
            name: "",
            products: 0,
            color: "#58739b",
            hasLogo: false,
            logoUrl: null,
            active: true,
          }
    );
  }
  function saveForm(event) {
    event.preventDefault();
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
    const value = { ...form, name, id: form.id || `brand-demo-${Date.now()}` };
    setBrands((previous) =>
      form.id
        ? previous.map((brand) => (brand.id === form.id ? value : brand))
        : [...previous, value]
    );
    if (!value.active || !value.hasLogo) {
      setOrder((previous) => previous.filter((id) => id !== value.id));
      setSaved((previous) => previous.filter((id) => id !== value.id));
    }
    setForm(null);
    show("Brand tersimpan di mockup.");
  }
  function addPrimary(brand) {
    if (order.length >= 8) {
      show("Delapan posisi sudah terisi. Pilih Ganti brand pada posisi yang diinginkan.");
      return;
    }
    setOrder((previous) => [...previous, brand.id]);
    setAnnouncement(`${brand.name} ditambahkan ke urutan utama.`);
  }
  function keyboardMove(event, id) {
    if (event.key === "Escape" && drag.current) {
      event.preventDefault(); finishDrag(true); return;
    }
    if (drag.current) return;
    const keys = ["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"];
    if (!keys.includes(event.key)) return;
    event.preventDefault();
    const from = order.indexOf(id);
    const grid = event.currentTarget.closest(".bm-order-grid");
    const columns =
      getComputedStyle(grid).gridTemplateColumns.split(" ").length;
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
      `${brands.find((brand) => brand.id === id).name}, urutan ${to + 1}.`
    );
  }
  function startDrag(event, brand) {
    if (event.button !== 0) return;
    if (ghost && !drag.current) return;
    const rect = event.currentTarget
      .closest("[data-brand-id]")
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
  function dragMove(event) {
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
      ?.closest("[data-brand-id]");
    if (hit && hit.dataset.brandId !== current.id)
      setOrder((previous) => {
        const from = previous.indexOf(current.id),
          to = previous.indexOf(hit.dataset.brandId);
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
  function changeTab(next) {
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
          <span className="bm-demo">Mockup · data contoh</span>
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
            value: 18,
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
              } else show("Contoh antrean: 18 produk perlu konfirmasi brand.");
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
                  <span className="bm-product-count">
                    {brand.products} <span>produk</span>
                  </span>
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
                <p>Posisi 1–8 mengikuti susunan ini. Daftar semua brand di aplikasi tetap A–Z.</p>
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
                  <button type="button" className="bm-replace-button"
                    aria-label={`Ganti brand posisi ${index + 1}: ${brand.name}`}
                    onClick={() => { setReplaceId(brand.id); setReplacementQuery(""); }}>
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
              <p className="bm-other-description">Brand aktif tetap tersedia di daftar semua brand.</p>
              <div>
                {brands
                  .filter((brand) => !order.includes(brand.id))
                  .sort((a, b) => a.name.localeCompare(b.name, "id"))
                  .map((brand) => (
                    <div className="bm-other-row" key={brand.id}>
                      <Logo brand={brand} />
                      <strong>{brand.name}</strong>
                      {brand.active && brand.hasLogo ? (order.length < 8 ? (
                        <Button
                          variant="secondary"
                          size="sm"
                          onClick={() => addPrimary(brand)}
                        >
                          Tambah ke utama
                        </Button>
                      ) : <span className="bm-available">Siap dipilih</span>
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
                  disabled={!dirty}
                  onClick={() => setOrder([...saved])}
                >
                  Batalkan
                </Button>
                <Button
                  disabled={!dirty}
                  onClick={() => {
                    setSaved([...order]);
                    show("Urutan tersimpan di mockup.");
                  }}
                >
                  Simpan urutan
                </Button>
              </div>
            </div>
          </div>
        )}
      </section>
      <AdminDialog open={replaceId !== null} title={`Ganti brand posisi ${order.indexOf(replaceId) + 1}`}
        onClose={() => setReplaceId(null)} className="bm-picker-dialog">
        <p className="bm-picker-description">Menggantikan {brands.find((brand) => brand.id === replaceId)?.name}. Brand sebelumnya tetap tersedia di daftar semua brand.</p>
        <label className="bm-search">
          <Icon name="search" />
          <input data-dialog-autofocus aria-label="Cari pengganti brand" placeholder="Cari brand pengganti…"
            value={replacementQuery} onChange={(event) => setReplacementQuery(event.target.value)} />
        </label>
        <div className="bm-picker-list">
          {brands.filter((brand) => !order.includes(brand.id) && brand.name.toLowerCase().includes(replacementQuery.toLowerCase()))
            .sort((a, b) => a.name.localeCompare(b.name, "id")).map((brand) => (
              <button type="button" key={brand.id} disabled={!brand.active || !brand.hasLogo}
                onClick={() => {
                  setOrder((previous) => previous.map((id) => id === replaceId ? brand.id : id));
                  setAnnouncement(`${brand.name} dipilih sebagai brand utama.`);
                  setReplaceId(null);
                }}>
                <Logo brand={brand} /><span><strong>{brand.name}</strong><small>{!brand.active ? "Nonaktif" : !brand.hasLogo ? "Lengkapi logo terlebih dahulu" : `${brand.products} produk`}</small></span>
                {brand.active && brand.hasLogo && <span className="bm-picker-action">Pilih</span>}
              </button>
            ))}
          {!brands.some((brand) => !order.includes(brand.id) && brand.name.toLowerCase().includes(replacementQuery.toLowerCase())) && <p className="bm-picker-description">Brand tidak ditemukan.</p>}
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
        onClose={() => setForm(null)}
        className="bm-editor-dialog"
        footer={
          <>
            <Button variant="secondary" onClick={() => setForm(null)}>
              Batal
            </Button>
            <Button type="submit" form="brand-mockup-form">
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
                accept="image/png,image/jpeg,image/webp,image/svg+xml"
                className="sr-only"
                aria-label="Pilih logo brand"
                onChange={(event) => {
                  const file = event.target.files?.[0];
                  if (!file) return;
                  if (file.size > 5 * 1024 * 1024) {
                    setError("Logo maksimal 5 MB.");
                    return;
                  }
                  if (!file.type.startsWith("image/")) {
                    setError("Pilih file gambar.");
                    return;
                  }
                  const url = URL.createObjectURL(file);
                  urls.current.push(url);
                  setError("");
                  setForm({ ...form, hasLogo: true, logoUrl: url });
                  event.target.value = "";
                }}
              />
            <details className="bm-advanced">
              <summary>Pengaturan lanjutan</summary>
              <label>
                Slug
                <input value={slugify(form.name)} readOnly />
              </label>
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
        open={leaveOpen}
        title="Simpan perubahan urutan?"
        onClose={() => setLeaveOpen(false)}
        footer={
          <>
            <Button
              variant="secondary"
              onClick={() => {
                setOrder([...saved]);
                setLeaveOpen(false);
                setTab("all");
              }}
            >
              Buang perubahan
            </Button>
            <Button
              onClick={() => {
                setSaved([...order]);
                setLeaveOpen(false);
                setTab("all");
                show("Urutan tersimpan di mockup.");
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
