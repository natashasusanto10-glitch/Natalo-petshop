import React, { useState } from "react";
import {
  FiPlus,
  FiSearch,
  FiTrash2,
  FiArrowLeft,
  FiCheckCircle,
} from "react-icons/fi";
import { AdminPage, PageHeader, Button } from "../../components/admin/ui";
import { AdminDialog } from "../../components/admin/ui/AdminDialog";
const money = (n) => Math.round(n).toLocaleString("id-ID");
const art = (name, color) =>
  `data:image/svg+xml,${encodeURIComponent(
    `<svg xmlns="http://www.w3.org/2000/svg" width="120" height="150"><rect width="120" height="150" rx="12" fill="${color}"/><rect x="20" y="15" width="80" height="120" rx="8" fill="white"/><rect x="20" y="32" width="80" height="30" fill="#133b63"/><text x="60" y="52" text-anchor="middle" fill="white" font-family="Arial" font-size="13" font-weight="bold">MAJES</text><text x="60" y="87" text-anchor="middle" fill="#133b63" font-family="Arial" font-size="11">${name.replaceAll("&", "&amp;")}</text></svg>`
  )}`;
const catalog = [
  {
    id: "a",
    name: "Majes Dental Crisps 80 GR — Snack Biskuit Kucing",
    category: "Snack Kucing",
    image: art("DENTAL", "#e6f1ec"),
    variants: [
      {
        id: "a1",
        label: "Original · 80 GR",
        price: 34100,
        stock: 36,
        sku: "MJS-DNT-80",
      },
    ],
  },
  {
    id: "b",
    name: "MAJES High Protein Skin & Coat — Makanan Anjing Dewasa",
    category: "Makanan Anjing",
    image: art("SKIN & COAT", "#e9edf9"),
    variants: [
      { id: "b1", label: "7 KG", price: 578500, stock: 5, sku: "MJS-SC-7" },
      { id: "b2", label: "1,5 KG", price: 187500, stock: 23, sku: "MJS-SC-15" },
    ],
  },
  {
    id: "c",
    name: "MAJES Creamy Cat Treats — Skin & Coat / Digestive",
    category: "Snack Kucing",
    image: art("CREAMY", "#fff0da"),
    variants: [
      {
        id: "c1",
        label: "Skin & Coat · 5 pcs",
        price: 20000,
        stock: 48,
        sku: "MJS-CR-SC",
      },
      {
        id: "c2",
        label: "Digestive & Urinary · 5 pcs",
        price: 20000,
        stock: 32,
        sku: "MJS-CR-DU",
      },
    ],
  },
  {
    id: "d",
    name: "Majes Maxi Omega Oil — Suplemen Kucing & Anjing",
    category: "Obat & Suplemen",
    image: art("OMEGA OIL", "#e4f0fb"),
    variants: [
      { id: "d1", label: "1 strip", price: 8650, stock: 98, sku: "MJS-OMG-1" },
    ],
  },
  {
    id: "e",
    name: "Majes Wild Call Freeze Dried — Camilan Anjing",
    category: "Snack Anjing",
    image: art("WILD CALL", "#f2e7da"),
    variants: [
      { id: "e1", label: "50 GR", price: 42400, stock: 0, sku: "MJS-WC-50" },
    ],
  },
];
const initial = catalog
  .slice(0, 3)
  .flatMap((p) =>
    p.variants.map((v) => ({
      ...v,
      product: p.id,
      promo: Math.round(v.price * 0.9),
      active: true,
    }))
  );
export default function PromoMockup() {
  const [items, setItems] = useState(initial),
    [selected, setSelected] = useState([]),
    [open, setOpen] = useState(false),
    [chosen, setChosen] = useState([]),
    [query, setQuery] = useState(""),
    [category, setCategory] = useState(""),
    [available, setAvailable] = useState(true),
    [bulk, setBulk] = useState("10"),
    [name, setName] = useState("DISKON MAJES"),
    [start, setStart] = useState("2026-10-05T12:30"),
    [end, setEnd] = useState("2026-10-31T23:59"),
    [notify, setNotify] = useState(false),
    [feedback, setFeedback] = useState(""),
    [error, setError] = useState("");
  const setItem = (id, patch) => {
    setItems((cur) => cur.map((i) => (i.id === id ? { ...i, ...patch } : i)));
    setFeedback("");
  };
  const toggle = (ids, set, current) =>
    set(
      current.includes(ids)
        ? current.filter((x) => x !== ids)
        : [...current, ids]
    );
  const removable = (id) => {
    setItems((cur) => cur.filter((i) => i.id !== id));
    setSelected((cur) => cur.filter((i) => i !== id));
  };
  const eligible = catalog
    .filter(
      (p) =>
        (!category || p.category === category) &&
        p.name.toLowerCase().includes(query.toLowerCase())
    )
    .map((p) => ({
      ...p,
      variants: p.variants.filter((v) => !available || v.stock > 0),
    }))
    .filter((p) => p.variants.length);
  const canPick = (v) => !items.some((i) => i.id === v.id);
  const visibleIds = eligible.flatMap((p) =>
    p.variants.filter(canPick).map((v) => v.id)
  );
  const add = () => {
    const extra = catalog.flatMap((p) =>
      p.variants
        .filter((v) => chosen.includes(v.id) && canPick(v))
        .map((v) => ({ ...v, product: p.id, promo: v.price, active: true }))
    );
    setItems((cur) => [...cur, ...extra]);
    setChosen([]);
    setOpen(false);
    setFeedback(
      `${extra.length} produk/variasi ditambahkan. Atur harga promo sebelum menyimpan.`
    );
  };
  const apply = () => {
    const amount = Number(bulk);
    if (!Number.isFinite(amount) || amount <= 0 || amount >= 100) {
      setError("Diskon harus lebih dari 0 dan kurang dari 100%.");
      return;
    }
    setError("");
    setItems((cur) =>
      cur.map((i) =>
        selected.includes(i.id)
          ? {
              ...i,
              promo: Math.max(1, Math.round(i.price * (1 - amount / 100))),
            }
          : i
      )
    );
    setFeedback(
      `Diskon ${amount}% diterapkan pada ${selected.length} pilihan.`
    );
  };
  const save = () => {
    setError("");
    if (!name.trim()) {
      setError("Isi nama promo toko.");
      return;
    }
    if (!start || !end || new Date(end) <= new Date(start)) {
      setError("Waktu selesai harus setelah waktu mulai.");
      return;
    }
    if ((new Date(end) - new Date(start)) / 86400000 > 90) {
      setError("Periode promo maksimal 90 hari.");
      return;
    }
    if (!items.length) {
      setError("Tambahkan produk terlebih dahulu.");
      return;
    }
    if (
      items.some(
        (i) =>
          i.active &&
          (!Number.isFinite(i.promo) || i.promo <= 0 || i.promo >= i.price)
      )
    ) {
      setError(
        "Harga promo produk aktif harus lebih dari 0 dan di bawah harga awal."
      );
      return;
    }
    setFeedback(
      "Simulasi tersimpan. Mockup ini tidak mengubah promo atau mengirim notifikasi."
    );
  };
  const priceInput = (i) => (
    <input
      aria-label={`Harga promo ${i.label}`}
      inputMode="numeric"
      value={i.promo ? money(i.promo) : ""}
      onChange={(e) =>
        setItem(i.id, { promo: Number(e.target.value.replace(/[^0-9]/g, "")) })
      }
    />
  );
  return (
    <AdminPage maxWidth="xl" className="pm">
      <a href="/admin/diskon" className="pm-back">
        <FiArrowLeft /> Promo Toko
      </a>
      <PageHeader
        title="Buat Promo Toko"
        subtitle="Atur periode dan harga spesial untuk produk pilihan."
      />
      <section className="pm-panel">
        <div className="pm-panel-title">
          <h2>Informasi dasar</h2>
          <span>Nama promo hanya terlihat oleh admin</span>
        </div>
        <div className="pm-fields">
          <label>
            Nama promo
            <input
              value={name}
              maxLength={150}
              onChange={(e) => setName(e.target.value)}
            />
          </label>
          <label>
            Mulai
            <input
              type="datetime-local"
              value={start}
              onChange={(e) => setStart(e.target.value)}
            />
          </label>
          <label>
            Berakhir
            <input
              type="datetime-local"
              value={end}
              onChange={(e) => setEnd(e.target.value)}
            />
          </label>
        </div>
        <div className="pm-period">
          <span>Durasi cepat</span>
          {[7, 30, 90].map((days) => (
            <button
              type="button"
              key={days}
              onClick={() => {
                const d = new Date(start);
                if (Number.isNaN(d.getTime())) return;
                d.setDate(d.getDate() + days);
                const local = new Date(
                  d.getTime() - d.getTimezoneOffset() * 60000
                )
                  .toISOString()
                  .slice(0, 16);
                setEnd(local);
              }}
            >
              {days} hari
            </button>
          ))}
          <span className="pm-muted">Maksimal 90 hari</span>
        </div>
      </section>
      <section className="pm-panel">
        <div className="pm-panel-title">
          <div>
            <h2>Produk dalam promo</h2>
            <p>
              {new Set(items.map((i) => i.product)).size} produk ·{" "}
              {items.length} pilihan produk/variasi
            </p>
          </div>
          <Button
            variant="secondary"
            onClick={() => {
              setChosen([]);
              setOpen(true);
            }}
          >
            <FiPlus /> Tambah produk
          </Button>
        </div>
        <div className="pm-bulk">
          <div>
            <strong>Perubahan massal</strong>
            <p>{selected.length} dipilih</p>
          </div>
          <label>
            Diskon (%)
            <input
              aria-label="Diskon massal"
              inputMode="decimal"
              value={bulk}
              onChange={(e) => setBulk(e.target.value.replace(/[^0-9.]/g, ""))}
            />
          </label>
          <Button
            variant="secondary"
            disabled={!selected.length}
            onClick={apply}
          >
            Terapkan
          </Button>
          <button
            type="button"
            className="pm-text"
            disabled={!selected.length}
            onClick={() => {
              setItems((cur) => cur.filter((i) => !selected.includes(i.id)));
              setSelected([]);
            }}
          >
            Hapus pilihan
          </button>
        </div>
        <div className="pm-table-head">
          <label>
            <input
              type="checkbox"
              aria-label="Pilih semua item promo"
              checked={
                items.length > 0 && items.every((i) => selected.includes(i.id))
              }
              onChange={(e) =>
                setSelected(e.target.checked ? items.map((i) => i.id) : [])
              }
            />{" "}
            Produk / variasi
          </label>
          <span>Harga awal</span>
          <span>Harga promo</span>
          <span>Diskon (%)</span>
          <span>Stok</span>
          <span>Aktif</span>
          <span />
        </div>
        <div className="pm-groups">
          {catalog
            .filter((p) => items.some((i) => i.product === p.id))
            .map((p) => (
              <article className="pm-group" key={p.id}>
                <header>
                  <img src={p.image} alt="" />
                  <div>
                    <strong>{p.name}</strong>
                    <p>{p.category}</p>
                  </div>
                  <button
                    type="button"
                    className="pm-text"
                    onClick={() => {
                      setItems((cur) => cur.filter((i) => i.product !== p.id));
                      setSelected((cur) =>
                        cur.filter((id) => !p.variants.some((v) => v.id === id))
                      );
                    }}
                  >
                    Hapus produk
                  </button>
                </header>
                {items
                  .filter((i) => i.product === p.id)
                  .map((i) => (
                    <div
                      className={`pm-row ${!i.active ? "pm-off" : ""}`}
                      key={i.id}
                    >
                      <label className="pm-variant">
                        <input
                          type="checkbox"
                          aria-label={`Pilih ${p.name} ${i.label}`}
                          checked={selected.includes(i.id)}
                          onChange={() => toggle(i.id, setSelected, selected)}
                        />
                        <span>
                          <strong>{i.label}</strong>
                          <small>{i.sku}</small>
                        </span>
                      </label>
                      <div className="pm-price-original">
                        <small>Harga awal</small>
                        {money(i.price)}
                      </div>
                      <div>
                        <small>Harga promo</small>
                        {priceInput(i)}
                        {i.active && (i.promo <= 0 || i.promo >= i.price) && (
                          <em>Di bawah {money(i.price)}</em>
                        )}
                      </div>
                      <div>
                        <small>Diskon (%)</small>
                        <input
                          aria-label={`Diskon ${i.label}`}
                          inputMode="decimal"
                          value={Math.max(
                            0,
                            Math.round((1 - i.promo / i.price) * 10000) / 100
                          )}
                          onChange={(e) => {
                            const n = Number(e.target.value);
                            if (n >= 0 && n < 100)
                              setItem(i.id, {
                                promo: Math.max(
                                  1,
                                  Math.round(i.price * (1 - n / 100))
                                ),
                              });
                          }}
                        />
                      </div>
                      <div className="pm-stock">
                        <small>Stok</small>
                        {i.stock}
                      </div>
                      <button
                        type="button"
                        role="switch"
                        aria-label={`Aktifkan ${p.name} ${i.label}`}
                        aria-checked={i.active}
                        className="pm-switch"
                        onClick={() => setItem(i.id, { active: !i.active })}
                      >
                        <span />
                      </button>
                      <button
                        type="button"
                        className="pm-icon"
                        aria-label={`Hapus ${p.name} ${i.label}`}
                        onClick={() => removable(i.id)}
                      >
                        <FiTrash2 />
                      </button>
                    </div>
                  ))}
              </article>
            ))}
          {!items.length && (
            <div className="pm-empty">
              Belum ada produk. Tambahkan produk untuk mulai mengatur diskon.
            </div>
          )}
        </div>
      </section>
      <section className="pm-notify">
        <label>
          <input
            type="checkbox"
            checked={notify}
            onChange={(e) => setNotify(e.target.checked)}
          />
          <span>
            <strong>Beri tahu pelanggan</strong>
            <p>Kirim notifikasi saat promo mulai aktif.</p>
          </span>
        </label>
      </section>
      {error && (
        <p role="alert" className="pm-error">
          {error}
        </p>
      )}
      {feedback && (
        <p role="status" className="pm-success">
          <FiCheckCircle />
          {feedback}
        </p>
      )}
      <footer className="pm-save">
        <span>{items.filter((i) => i.active).length} pilihan aktif</span>
        <Button
          variant="secondary"
          onClick={() => {
            setItems(initial);
            setSelected([]);
            setError("");
            setFeedback("Isian produk dikembalikan ke contoh awal.");
          }}
        >
          Atur ulang
        </Button>
        <Button onClick={save}>Simpan promo</Button>
      </footer>
      <AdminDialog
        className="pm-picker"
        open={open}
        title="Pilih produk"
        onClose={() => setOpen(false)}
        footer={
          <>
            <span className="pm-selection-count">{chosen.length} dipilih</span>
            <Button variant="secondary" onClick={() => setOpen(false)}>
              Batal
            </Button>
            <Button disabled={!chosen.length} onClick={add}>
              Tambahkan ({chosen.length})
            </Button>
          </>
        }
      >
        <div className="pm-pick-filters">
          <label>
            <span>Kategori</span>
            <select
              value={category}
              onChange={(e) => setCategory(e.target.value)}
            >
              <option value="">Semua kategori</option>
              {[...new Set(catalog.map((p) => p.category))].map((c) => (
                <option key={c}>{c}</option>
              ))}
            </select>
          </label>
          <label>
            <span>Cari produk</span>
            <div className="pm-search">
              <FiSearch />
              <input
                placeholder="Nama produk atau brand"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
              />
            </div>
          </label>
        </div>
        <div className="pm-pick-toolbar">
          <label>
            <input
              type="checkbox"
              checked={available}
              onChange={(e) => setAvailable(e.target.checked)}
            />{" "}
            Hanya produk dengan stok tersedia
          </label>
          <button
            type="button"
            className="pm-text"
            onClick={() => {
              setQuery("");
              setCategory("");
              setAvailable(true);
            }}
          >
            Atur ulang filter
          </button>
        </div>
        <div className="pm-pick-head">
          <label>
            <input
              type="checkbox"
              aria-label="Pilih semua produk yang tersedia di hasil"
              checked={
                visibleIds.length > 0 &&
                visibleIds.every((id) => chosen.includes(id))
              }
              disabled={!visibleIds.length}
              onChange={(e) =>
                setChosen(
                  e.target.checked
                    ? [...new Set([...chosen, ...visibleIds])]
                    : chosen.filter((id) => !visibleIds.includes(id))
                )
              }
            />{" "}
            Produk / variasi
          </label>
          <span>Harga awal</span>
          <span>Stok</span>
        </div>
        <div className="pm-pick-results">
          {eligible.map((p) => (
            <article key={p.id}>
              <header>
                <img src={p.image} alt="" />
                <div>
                  <strong>{p.name}</strong>
                  <p>
                    {p.category} · {p.variants.length} pilihan
                  </p>
                </div>
              </header>
              {p.variants.map((v) => (
                <label
                  className={`pm-pick-row ${!canPick(v) ? "pm-added" : ""}`}
                  key={v.id}
                >
                  <span>
                    <input
                      type="checkbox"
                      disabled={!canPick(v)}
                      checked={chosen.includes(v.id)}
                      onChange={() => toggle(v.id, setChosen, chosen)}
                    />
                    {v.label}
                    {!canPick(v) && <em>Sudah ditambahkan</em>}
                  </span>
                  <span>{money(v.price)}</span>
                  <span>{v.stock}</span>
                </label>
              ))}
            </article>
          ))}
          {!eligible.length && (
            <div className="pm-empty">
              Produk tidak ditemukan. Coba kata kunci atau kategori lain.
            </div>
          )}
        </div>
      </AdminDialog>
    </AdminPage>
  );
}
