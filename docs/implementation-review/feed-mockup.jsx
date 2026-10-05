import React, { useEffect, useRef, useState } from "react";
import {
  FiPlus,
  FiSearch,
  FiPlay,
  FiEye,
  FiHeart,
  FiMessageCircle,
  FiShare2,
  FiShoppingBag,
  FiMoreHorizontal,
  FiCheck,
  FiUploadCloud,
  FiArrowLeft,
  FiX,
} from "react-icons/fi";
import { AdminDialog } from "../../components/admin/ui/AdminDialog";

const art = (name, color) =>
  `data:image/svg+xml,${encodeURIComponent(
    `<svg xmlns="http://www.w3.org/2000/svg" width="540" height="900" viewBox="0 0 540 900"><defs><linearGradient id="g" x2="1" y2="1"><stop stop-color="${color}"/><stop offset="1" stop-color="#183652"/></linearGradient></defs><rect width="540" height="900" fill="url(#g)"/><circle cx="370" cy="250" r="220" fill="white" opacity=".08"/><circle cx="130" cy="470" r="150" fill="white" opacity=".05"/><rect x="125" y="230" width="290" height="370" rx="28" fill="#fff8e9"/><path d="M125 280h290v75H125z" fill="#173d62"/><text x="270" y="330" text-anchor="middle" fill="white" font-family="Arial" font-size="32" font-weight="bold">NATALO</text><text x="270" y="425" text-anchor="middle" fill="#173d62" font-family="Arial" font-size="24">${name}</text><text x="270" y="465" text-anchor="middle" fill="#64748b" font-family="Arial" font-size="17">Daily care • Happy pets</text><circle cx="270" cy="530" r="35" fill="${color}"/></svg>`
  )}`;
const products = [
  {
    id: 1,
    name: "Kaniva Salmon, Tuna & Rice 3 kg",
    price: 300000,
    image: art("KANIVA", "#598c98"),
  },
  {
    id: 2,
    name: "Animal & Co Chicken Treats",
    price: 17300,
    image: art("CHICKEN", "#bc9163"),
  },
  {
    id: 3,
    name: "Tisu Basah Hewan 80 Lembar",
    price: 12100,
    image: art("DAILY CARE", "#738d70"),
  },
];
const initial = [
  {
    id: 1,
    title: "Nutrisi lengkap untuk teman kecilmu",
    description:
      "Pilihan makanan harian untuk kucing aktif. Temukan produk favoritnya di Natalo.",
    kind: "Video produk",
    status: "Tayang",
    encoding: "Siap",
    author: "Natalo Petshop",
    official: true,
    products: [1],
    views: 2840,
    likes: 124,
    comments: 18,
    image: products[0].image,
    date: "5 Okt 2026",
  },
  {
    id: 2,
    title: "Camilan baru, momen bahagia",
    description: "Hadiah kecil setelah latihan hari ini.",
    kind: "Promo",
    status: "Tayang",
    encoding: "Siap",
    author: "Natalo Petshop",
    official: true,
    products: [2],
    views: 1620,
    likes: 86,
    comments: 9,
    image: products[1].image,
    date: "4 Okt 2026",
  },
  {
    id: 3,
    title: "Rutinitas perawatan harian",
    description: "Bersih dan nyaman setelah bermain.",
    kind: "Video produk",
    status: "Menunggu video",
    encoding: "Diproses",
    author: "Natalo Petshop",
    official: true,
    products: [3],
    views: 0,
    likes: 0,
    comments: 0,
    image: products[2].image,
    date: "5 Okt 2026",
  },
  {
    id: 4,
    title: "Saatnya bermain bersama Milo",
    description: "Milo selalu bersemangat saat waktunya bermain.",
    kind: "Foto / Carousel",
    status: "Tayang",
    encoding: "Siap",
    author: "Dinda & Milo",
    official: false,
    products: [],
    views: 432,
    likes: 42,
    comments: 7,
    image: art("MILO", "#8e9985"),
    date: "3 Okt 2026",
  },
  {
    id: 5,
    title: "Tips memilih camilan anjing",
    description: "Camilan untuk menemani latihan.",
    kind: "Video",
    status: "Menunggu video",
    encoding: "Gagal",
    author: "Natalo Petshop",
    official: true,
    products: [],
    views: 0,
    likes: 0,
    comments: 0,
    image: products[1].image,
    date: "3 Okt 2026",
  },
  {
    id: 6,
    title: "Promo akhir pekan",
    description: "Pilihan kebutuhan hewan kesayangan.",
    kind: "Promo",
    status: "Disembunyikan",
    encoding: "Siap",
    author: "Natalo Petshop",
    official: true,
    products: [2, 3],
    views: 980,
    likes: 51,
    comments: 5,
    image: products[2].image,
    date: "2 Okt 2026",
  },
];
const number = (n) => new Intl.NumberFormat("id-ID").format(n);
function Preview({ post, onProducts }) {
  return (
    <div className="fm-phone">
      <div className="fm-phone-top">
        <strong>Feed</strong>
        <span>Natalo</span>
      </div>
      <div className="fm-screen">
        <img src={post.image} alt="Sampul contoh Feed" />
        {post.kind !== "Foto / Carousel" && (
          <span className="fm-play" aria-hidden="true">
            <FiPlay />
          </span>
        )}
        <div className="fm-social">
          <span>
            <FiHeart />
            {number(post.likes || 0)}
          </span>
          <span>
            <FiMessageCircle />
            {number(post.comments || 0)}
          </span>
          <span>
            <FiShare2 />
            Bagikan
          </span>
        </div>
        <div className="fm-caption">
          {post.products.length > 0 && (
            <button className="fm-product-pill" onClick={onProducts}>
              <FiShoppingBag />
              <span>{post.products.length} produk terkait</span>
              <span>›</span>
            </button>
          )}
          <div className="fm-author">
            <span className="fm-avatar">N</span>
            <strong>{post.author}</strong>
            {post.official && (
              <span className="fm-official">
                <FiCheck />
                Official
              </span>
            )}
          </div>
          <p>{post.description || post.title || "Caption postingan"}</p>
        </div>
      </div>
      <div className="fm-phone-bottom">
        Feed <span>Komunitas</span>
      </div>
    </div>
  );
}
export default function FeedMockup() {
  const [posts, setPosts] = useState(initial),
    [query, setQuery] = useState(""),
    [filter, setFilter] = useState("Semua"),
    [format, setFormat] = useState("Semua format"),
    [selection, setSelection] = useState([]),
    [editor, setEditor] = useState(null),
    [preview, setPreview] = useState(null),
    [productSheet, setProductSheet] = useState(null),
    [confirm, setConfirm] = useState(null),
    [reason, setReason] = useState(""),
    [toast, setToast] = useState("");
  const [title, setTitle] = useState(""),
    [description, setDescription] = useState(""),
    [kind, setKind] = useState("Video produk"),
    [tagged, setTagged] = useState([1]),
    [media, setMedia] = useState(false),
    [processing, setProcessing] = useState(false),
    [notify, setNotify] = useState(false),
    [productQuery, setProductQuery] = useState(""),
    [error, setError] = useState(""),
    [promoPrices, setPromoPrices] = useState({}),
    [startsAt, setStartsAt] = useState(""),
    [endsAt, setEndsAt] = useState("");
  const timer = useRef(null),
    heading = useRef(null);
  useEffect(() => () => clearTimeout(timer.current), []);
  useEffect(() => {
    if (!toast) return;
    const id = setTimeout(() => setToast(""), 4000);
    return () => clearTimeout(id);
  }, [toast]);
  useEffect(() => {
    heading.current?.focus({ preventScroll: true });
  }, [editor]);
  function openEditor(post) {
    clearTimeout(timer.current);
    setEditor(post || { id: 0 });
    setTitle(post?.title || "");
    setDescription(post?.description || "");
    setKind(post?.kind || "Video produk");
    setTagged(post?.products || [1]);
    setMedia(Boolean(post));
    setNotify(false);
    setError("");
    setProcessing(false);
    setPromoPrices(post?.promoPrices || {});
    setStartsAt(post?.startsAt || "");
    setEndsAt(post?.endsAt || "");
  }
  const draft = {
    id: editor?.id,
    title,
    description,
    kind,
    products: kind === "Video" ? [] : tagged,
    image: editor?.image || products[0].image,
    author: "Natalo Petshop",
    official: true,
    likes: editor?.likes || 0,
    comments: editor?.comments || 0,
  };
  const rows = posts.filter(
    (p) =>
      (filter === "Semua"
        ? p.status !== "Sampah"
        : filter === "Perlu perhatian"
        ? p.encoding !== "Siap" && p.status !== "Sampah"
        : p.status === filter) &&
      (format === "Semua format" || p.kind === format) &&
      (
        p.title +
        " " +
        p.author +
        " " +
        p.products
          .map((id) => products.find((p) => p.id === id)?.name)
          .join(" ")
      )
        .toLowerCase()
        .includes(query.toLowerCase())
  );
  function changeStatus(ids, status) {
    setPosts((old) =>
      old.map((p) =>
        ids.includes(p.id)
          ? {
              ...p,
              status:
                status === "Tayang" && p.encoding !== "Siap"
                  ? "Menunggu video"
                  : status,
              moderationNote:
                status === "Disembunyikan" ? reason : p.moderationNote,
            }
          : p
      )
    );
    setSelection([]);
    setConfirm(null);
    setToast(
      status === "Sampah"
        ? "Postingan dipindahkan ke sampah."
        : status === "Disembunyikan"
        ? "Postingan disembunyikan."
        : "Postingan dipulihkan."
    );
  }
  function save() {
    if (!title.trim()) {
      setError("Isi judul postingan.");
      return;
    }
    if (!media) {
      setError("Pilih video contoh terlebih dahulu.");
      return;
    }
    if (kind !== "Video" && !tagged.length) {
      setError("Pilih setidaknya satu produk terkait.");
      return;
    }
    if (
      kind === "Promo" &&
      (!startsAt ||
        !endsAt ||
        endsAt <= startsAt ||
        tagged.some(
          (id) =>
            !promoPrices[id] ||
            Number(promoPrices[id]) >= products.find((p) => p.id === id).price
        ))
    ) {
      setError(
        "Isi harga promo di bawah harga normal dan periode akhir setelah waktu mulai."
      );
      return;
    }
    const item = {
      ...draft,
      id: editor.id || Date.now(),
      date: "5 Okt 2026",
      views: editor.id ? posts.find((p) => p.id === editor.id)?.views || 0 : 0,
      status: editor.id ? editor.status : "Menunggu video",
      encoding: editor.id ? editor.encoding : "Diproses",
      promoPrices,
      startsAt,
      endsAt,
    };
    setPosts((old) =>
      editor.id
        ? old.map((p) => (p.id === editor.id ? { ...p, ...item } : p))
        : [item, ...old]
    );
    setEditor(null);
    setToast("Simulasi tersimpan. Data produksi tidak berubah.");
  }
  function simulateMedia() {
    clearTimeout(timer.current);
    setMedia(false);
    setProcessing(true);
    timer.current = setTimeout(() => {
      setProcessing(false);
      setMedia(true);
      setToast("Video contoh siap untuk pratinjau.");
    }, 1600);
  }
  return (
    <main className="fm" aria-label="Mockup Feed">
      <div className="fm-demo">
        MOCKUP INTERAKTIF <span>Data contoh · Tidak terhubung ke produksi</span>
      </div>
      {!editor ? (
        <>
          <header className="fm-header">
            <div>
              <p className="fm-eyebrow">KONTEN & KOMUNITAS</p>
              <h1 ref={heading} tabIndex={-1}>
                Feed
              </h1>
              <p>Kelola cerita, produk, dan interaksi pelanggan.</p>
            </div>
            <button className="fm-primary" onClick={() => openEditor(null)}>
              <FiPlus />
              Tambah postingan
            </button>
          </header>
          <div className="fm-stats">
            {[
              [
                "Postingan tayang",
                posts.filter((p) => p.status === "Tayang").length,
                "Siap dilihat pelanggan",
              ],
              [
                "Dalam proses",
                posts.filter((p) => p.encoding === "Diproses").length,
                "Video sedang disiapkan",
              ],
              [
                "Gagal diproses",
                posts.filter((p) => p.encoding === "Gagal").length,
                "Pemrosesan video gagal",
              ],
              [
                "Total tayangan",
                number(posts.reduce((n, p) => n + p.views, 0)),
                "Akumulasi data contoh",
              ],
            ].map(([label, count, detail]) => (
              <div key={label}>
                <span>{label}</span>
                <strong>{count}</strong>
                <small>{detail}</small>
              </div>
            ))}
          </div>
          <section className="fm-panel">
            <div className="fm-toolbar">
              <label className="fm-search">
                <FiSearch />
                <input
                  aria-label="Cari postingan"
                  placeholder="Cari judul atau produk…"
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                />
              </label>
              <select
                aria-label="Format konten"
                value={format}
                onChange={(e) => {
                  setFormat(e.target.value);
                  setSelection([]);
                }}
              >
                {[
                  "Semua format",
                  "Video produk",
                  "Video",
                  "Promo",
                  "Foto / Carousel",
                ].map((s) => (
                  <option key={s}>{s}</option>
                ))}
              </select>
            </div>
            <div className="fm-tabs" aria-label="Status postingan">
              {["Semua", "Perlu perhatian", "Disembunyikan", "Sampah"].map(
                (s) => (
                  <button
                    key={s}
                    aria-pressed={filter === s}
                    onClick={() => {
                      setFilter(s);
                      setSelection([]);
                    }}
                  >
                    {s}
                    {s === "Perlu perhatian" && (
                      <span>
                        {
                          posts.filter(
                            (p) =>
                              p.encoding !== "Siap" && p.status !== "Sampah"
                          ).length
                        }
                      </span>
                    )}
                  </button>
                )
              )}
            </div>
            {selection.length > 0 && (
              <div className="fm-bulk">
                <strong>{selection.length} dipilih</strong>
                <button
                  onClick={() => {
                    setReason("");
                    setConfirm({
                      ids: selection,
                      status: filter === "Sampah" ? "Tayang" : "Disembunyikan",
                    });
                  }}
                >
                  {filter === "Sampah" ? "Pulihkan" : "Sembunyikan"}
                </button>
                <button
                  onClick={() =>
                    setConfirm({ ids: selection, status: "Sampah" })
                  }
                >
                  Pindah ke sampah
                </button>
                <button onClick={() => setSelection([])}>Batal</button>
              </div>
            )}
            <div className="fm-table-head">
              <input
                type="checkbox"
                aria-label="Pilih semua postingan yang terlihat"
                checked={
                  rows.length > 0 && rows.every((p) => selection.includes(p.id))
                }
                onChange={(e) =>
                  setSelection(e.target.checked ? rows.map((p) => p.id) : [])
                }
              />
              <span>Postingan</span>
              <span>Status</span>
              <span>Interaksi</span>
              <span>Aksi</span>
            </div>
            {rows.map((post) => (
              <article className="fm-row" key={post.id}>
                <input
                  type="checkbox"
                  aria-label={`Pilih ${post.title}`}
                  checked={selection.includes(post.id)}
                  onChange={(e) =>
                    setSelection(
                      e.target.checked
                        ? [...selection, post.id]
                        : selection.filter((id) => id !== post.id)
                    )
                  }
                />
                <div className="fm-content">
                  <button
                    className="fm-thumb"
                    aria-label={`Pratinjau ${post.title}`}
                    onClick={() => setPreview(post)}
                  >
                    <img src={post.image} alt="" />
                    {post.kind !== "Foto / Carousel" && <FiPlay />}
                  </button>
                  <div>
                    <small>{post.kind}</small>
                    <h2>{post.title}</h2>
                    <p>
                      {post.author} <span>· {post.date}</span>
                    </p>
                    {post.products.length > 0 && (
                      <div className="fm-tag">
                        <FiShoppingBag />
                        {post.products.length} produk terkait
                      </div>
                    )}
                  </div>
                </div>
                <div className="fm-status">
                  <span
                    className={`fm-badge ${
                      post.encoding === "Gagal"
                        ? "fm-danger"
                        : post.status === "Tayang"
                        ? "fm-success"
                        : ""
                    }`}
                  >
                    {post.status}
                  </span>
                  <small>
                    {post.encoding === "Gagal"
                      ? "Video gagal diproses"
                      : post.encoding === "Diproses"
                      ? "Video sedang diproses"
                      : post.status === "Tayang"
                      ? "Video / media siap"
                      : "Media siap"}
                  </small>
                </div>
                <div className="fm-metrics">
                  <strong>
                    <FiEye />
                    {number(post.views)}
                  </strong>
                  <small>
                    <FiHeart />
                    {post.likes}
                    <FiMessageCircle />
                    {post.comments}
                  </small>
                </div>
                <div className="fm-actions">
                  {post.official && post.status !== "Sampah" && (
                    <button onClick={() => openEditor(post)}>Edit</button>
                  )}
                  <button
                    aria-label={`Lihat ${post.title}`}
                    onClick={() => setPreview(post)}
                  >
                    <FiEye />
                  </button>
                  <details>
                    <summary aria-label={`Aksi lainnya ${post.title}`}>
                      <FiMoreHorizontal />
                    </summary>
                    <div>
                      {post.encoding === "Gagal" && (
                        <button
                          onClick={() => {
                            setPosts((old) =>
                              old.map((p) =>
                                p.id === post.id
                                  ? { ...p, encoding: "Diproses" }
                                  : p
                              )
                            );
                            setToast("Simulasi: pemrosesan diulang.");
                          }}
                        >
                          Coba proses kembali
                        </button>
                      )}
                      <button
                        onClick={() => {
                          setReason("");
                          setConfirm({
                            ids: [post.id],
                            status:
                              post.status === "Disembunyikan" ||
                              post.status === "Sampah"
                                ? "Tayang"
                                : "Disembunyikan",
                          });
                        }}
                      >
                        {post.status === "Disembunyikan"
                          ? "Tampilkan kembali"
                          : post.status === "Sampah"
                          ? "Pulihkan"
                          : "Sembunyikan"}
                      </button>
                      {post.status !== "Sampah" && (
                        <button
                          className="fm-delete"
                          onClick={() =>
                            setConfirm({ ids: [post.id], status: "Sampah" })
                          }
                        >
                          Pindah ke sampah
                        </button>
                      )}
                    </div>
                  </details>
                </div>
              </article>
            ))}
            {!rows.length && (
              <div className="fm-empty">
                <FiSearch />
                <h2>Tidak ada postingan ditemukan</h2>
                <p>Coba kata kunci lain atau ubah filter.</p>
                <button
                  onClick={() => {
                    setQuery("");
                    setFilter("Semua");
                    setFormat("Semua format");
                  }}
                >
                  Reset filter
                </button>
              </div>
            )}
            <footer className="fm-list-footer">
              {rows.length} postingan <span>Diurutkan dari data contoh</span>
            </footer>
          </section>
        </>
      ) : (
        <>
          <header className="fm-header">
            <div>
              <button
                className="fm-back"
                onClick={() => setConfirm({ leave: true })}
              >
                <FiArrowLeft />
                Semua postingan
              </button>
              <h1 ref={heading} tabIndex={-1}>
                {editor.id ? "Edit postingan" : "Tambah postingan"}
              </h1>
              <p>Siapkan konten dan lihat hasilnya sebelum ditayangkan.</p>
            </div>
            <button onClick={() => setPreview(draft)}>
              <FiEye />
              Pratinjau
            </button>
          </header>
          <div className="fm-editor">
            <div className="fm-form">
              <section className="fm-panel fm-section">
                <div className="fm-section-heading">
                  <span>01</span>
                  <h2>Media & konten</h2>
                </div>
                <label>
                  Jenis postingan
                  <select
                    value={kind}
                    disabled={Boolean(editor.id)}
                    onChange={(e) => setKind(e.target.value)}
                  >
                    {["Video produk", "Video", "Promo"].map((s) => (
                      <option key={s}>{s}</option>
                    ))}
                  </select>
                </label>
                <div className="fm-media">
                  <img src={draft.image} alt="Sampul video contoh" />
                  <div>
                    <strong>
                      {editor.id
                        ? "Video postingan"
                        : media
                        ? "Video contoh dipilih"
                        : "Video produk"}
                    </strong>
                    <p>
                      {processing
                        ? "Menyiapkan pratinjau…"
                        : editor.id
                        ? "Media dari postingan yang dipilih"
                        : media
                        ? "Sampul siap · 27 detik"
                        : "Gunakan video contoh untuk mencoba alurnya."}
                    </p>
                    {!editor.id && (
                      <button disabled={processing} onClick={simulateMedia}>
                        <FiUploadCloud />
                        {media ? "Ganti video contoh" : "Pilih video contoh"}
                      </button>
                    )}
                    {processing && (
                      <div className="fm-progress" role="status">
                        Menyiapkan media
                        <span />
                      </div>
                    )}
                  </div>
                </div>
                <label>
                  Judul postingan <span>*</span>
                  <input
                    value={title}
                    aria-required="true"
                    aria-invalid={Boolean(error && !title.trim())}
                    onChange={(e) => setTitle(e.target.value)}
                    maxLength={120}
                    placeholder="Tulis judul postingan"
                  />
                </label>
                <label>
                  Caption
                  <textarea
                    rows={4}
                    value={description}
                    onChange={(e) => setDescription(e.target.value)}
                    placeholder="Ceritakan manfaat atau momen di video…"
                  />
                </label>
              </section>
              {kind !== "Video" && (
                <section className="fm-panel fm-section">
                  <div className="fm-section-heading">
                    <span>02</span>
                    <h2>Produk terkait</h2>
                    <small>{tagged.length} / 5</small>
                  </div>
                  <label>
                    Cari produk
                    <input
                      value={productQuery}
                      onChange={(e) => setProductQuery(e.target.value)}
                      placeholder="Nama produk"
                    />
                  </label>
                  {products
                    .filter((p) =>
                      p.name.toLowerCase().includes(productQuery.toLowerCase())
                    )
                    .map((p) => (
                      <div className="fm-product-choice" key={p.id}>
                        <input
                          type="checkbox"
                          aria-label={`Tautkan ${p.name}`}
                          checked={tagged.includes(p.id)}
                          disabled={
                            !tagged.includes(p.id) && tagged.length >= 5
                          }
                          onChange={(e) =>
                            setTagged(
                              e.target.checked
                                ? [...tagged, p.id]
                                : tagged.filter((id) => id !== p.id)
                            )
                          }
                        />
                        <img src={p.image} alt="" />
                        <span>
                          <strong>{p.name}</strong>
                          <small>{number(p.price)}</small>
                        </span>
                        {kind === "Promo" && tagged.includes(p.id) && (
                          <input
                            aria-label={`Harga promo ${p.name}`}
                            inputMode="numeric"
                            placeholder="Harga promo"
                            value={
                              promoPrices[p.id]
                                ? number(Number(promoPrices[p.id]))
                                : ""
                            }
                            onChange={(e) => {
                              const value = e.target.value.replace(/\D/g, "");
                              setPromoPrices((old) => ({
                                ...old,
                                [p.id]: value,
                              }));
                            }}
                          />
                        )}
                      </div>
                    ))}
                  {kind === "Promo" && (
                    <div className="fm-dates">
                      <label>
                        Mulai promo
                        <input
                          type="datetime-local"
                          value={startsAt}
                          onChange={(e) => setStartsAt(e.target.value)}
                        />
                      </label>
                      <label>
                        Berakhir
                        <input
                          type="datetime-local"
                          value={endsAt}
                          onChange={(e) => setEndsAt(e.target.value)}
                        />
                      </label>
                    </div>
                  )}
                </section>
              )}
              {!editor.id && (
                <section className="fm-panel fm-section">
                  <div className="fm-section-heading">
                    <span>03</span>
                    <h2>Notifikasi pelanggan</h2>
                  </div>
                  <label className="fm-notify">
                    <input
                      type="checkbox"
                      checked={notify}
                      onChange={(e) => setNotify(e.target.checked)}
                    />
                    <span>
                      <strong>Kirim notifikasi saat postingan siap</strong>
                      <small>
                        Aktifkan hanya untuk konten yang perlu diumumkan.
                      </small>
                    </span>
                  </label>
                  {notify && (
                    <label className="fm-reveal">
                      Penerima
                      <select>
                        <option>Semua pelanggan</option>
                        <option>Member</option>
                        <option>Aktif dalam 30 hari</option>
                      </select>
                    </label>
                  )}
                </section>
              )}
              {error && (
                <p className="fm-error" role="alert">
                  {error}
                </p>
              )}
              <div className="fm-savebar">
                <button onClick={() => setConfirm({ leave: true })}>
                  Batal
                </button>
                <button
                  className="fm-primary"
                  disabled={processing}
                  onClick={save}
                >
                  {editor.id ? "Simpan perubahan" : "Tayangkan postingan"}
                </button>
              </div>
            </div>
            <aside className="fm-preview-aside">
              <div className="fm-preview-heading">
                <strong>Pratinjau Feed</strong>
                <span>Tampilan pelanggan</span>
              </div>
              <Preview post={draft} onProducts={() => setProductSheet(draft)} />
              <p className="fm-preview-note">
                Susunan mengikuti Feed pelanggan. Media dan interaksi pada
                mockup menggunakan data contoh.
              </p>
            </aside>
          </div>
        </>
      )}
      <AdminDialog
        open={Boolean(preview)}
        title="Pratinjau Feed"
        onClose={() => setPreview(null)}
        className="fm-preview-dialog"
      >
        {preview && (
          <Preview post={preview} onProducts={() => setProductSheet(preview)} />
        )}
      </AdminDialog>
      <AdminDialog
        open={Boolean(productSheet)}
        title="Produk di postingan"
        onClose={() => setProductSheet(null)}
      >
        {productSheet?.products.map((id) => {
          const p = products.find((p) => p.id === id);
          return (
            <div className="fm-sheet-product" key={id}>
              <img src={p.image} alt="" />
              <div>
                <strong>{p.name}</strong>
                <p>{number(p.price)}</p>
              </div>
            </div>
          );
        })}
      </AdminDialog>
      <AdminDialog
        open={Boolean(confirm)}
        title={
          confirm?.leave
            ? "Tinggalkan form?"
            : confirm?.status === "Sampah"
            ? "Pindahkan ke sampah?"
            : confirm?.status === "Disembunyikan"
            ? "Sembunyikan postingan?"
            : "Pulihkan postingan?"
        }
        onClose={() => setConfirm(null)}
        footer={
          <>
            <button className="fm-dialog-btn" onClick={() => setConfirm(null)}>
              Batal
            </button>
            <button
              className="fm-dialog-btn fm-primary"
              onClick={() => {
                if (confirm.leave) {
                  clearTimeout(timer.current);
                  setEditor(null);
                  setConfirm(null);
                } else changeStatus(confirm.ids, confirm.status);
              }}
            >
              {confirm?.leave
                ? "Tinggalkan"
                : confirm?.status === "Sampah"
                ? "Pindah ke sampah"
                : "Konfirmasi"}
            </button>
          </>
        }
      >
        {confirm?.leave ? (
          <p>Perubahan pada form ini belum disimpan.</p>
        ) : (
          <>
            <p>
              {confirm?.status === "Sampah"
                ? "Postingan dapat dipulihkan dari tab Sampah."
                : confirm?.status === "Disembunyikan"
                ? "Postingan tidak tampil kepada pelanggan dan tetap tersimpan."
                : "Postingan akan ditampilkan kembali setelah media siap."}
            </p>
            {confirm?.status === "Disembunyikan" && (
              <label className="fm-dialog-label">
                Alasan (opsional)
                <textarea
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  rows={3}
                />
              </label>
            )}
          </>
        )}
      </AdminDialog>
      {toast && (
        <div className="fm-toast" role="status">
          <FiCheck />
          <span>{toast}</span>
          <button aria-label="Tutup pemberitahuan" onClick={() => setToast("")}>
            <FiX />
          </button>
        </div>
      )}
    </main>
  );
}
