# Natalo Petshop App - Product Infinite Scroll & Navigation Update

## 1. Tujuan Project

Project ini bertujuan untuk memperbaiki experience pengguna pada aplikasi Natalo Petshop dengan fokus awal pada halaman produk.

Fitur utama yang akan dikerjakan:

- Memindahkan keranjang dari bottom navigation ke header
- Mengganti posisi avatar akun di header dengan icon keranjang
- Mengganti menu keranjang di bottom navigation menjadi menu Feed
- Membuat bottom navigation lebih clean dan native feel
- Membuat halaman produk menggunakan infinite scroll
- Menyiapkan struktur agar nanti bisa dilanjutkan ke halaman Beranda / Feed

---

## 2. Scope Pengerjaan Tahap Awal

Tahap pertama hanya fokus ke halaman produk.

### Yang dikerjakan sekarang

- Header baru
- Icon notifikasi
- Icon keranjang di header
- Bottom navigation baru
- Menu Feed di bottom nav
- Halaman produk
- Infinite scroll produk
- Search produk
- Filter kategori produk
- Loading state
- Empty state
- End of list state

### Yang belum dikerjakan di tahap ini

- Infinite scroll beranda
- Feed video
- Autoplay video
- Admin upload video
- User upload video
- Komentar dan like
- Promo feed
- Produk campuran di feed

---

## 3. Struktur Navigasi Baru

### Header Baru

Header atas akan berisi:

```txt
Logo Natalo | Notification Icon | Cart Icon
Search Bar
Info Strip
```

Contoh:

```txt
[Natalo Logo]                         [Bell] [Bag]
[Search: Cari di Natalo Petshop...]
[Area Medan] - [Produk Original 100%] - [Konsultasi via Chat]
```

### Bottom Navigation Baru

Bottom navigation akan menjadi:

```txt
Beranda | Produk | Feed | Akun
```

Menu lama:

```txt
Beranda | Produk | Keranjang | Akun
```

Diganti menjadi:

```txt
Beranda | Produk | Feed | Akun
```

---

## 4. Alasan Perubahan UX

### Keranjang Dipindah ke Header

Keranjang lebih cocok berada di header karena fungsinya sebagai shortcut transaksi.

User biasanya membuka keranjang setelah:

- Melihat produk
- Menambahkan produk
- Mengecek jumlah item
- Ingin checkout

Karena itu, posisi keranjang di kanan atas lebih natural untuk aplikasi e-commerce.

### Feed Masuk Bottom Navigation

Feed akan menjadi fitur utama aplikasi Natalo ke depannya.

Feed nantinya dapat berisi:

- Video dari admin
- Video dari user
- Konten komunitas
- Promo
- Produk yang dipromosikan
- Edukasi pet care

Karena Feed adalah fitur utama, maka lebih tepat ditempatkan di bottom navigation.

---

## 5. Icon Recommendation

Gunakan icon yang clean, outline, dan terasa native.

Recommended library:

```bash
npm install react-icons
```

Gunakan icon dari Ionicons:

```jsx
import {
  IoHomeOutline,
  IoHome,
  IoGridOutline,
  IoGrid,
  IoPlayCircleOutline,
  IoPlayCircle,
  IoPersonOutline,
  IoPerson,
  IoNotificationsOutline,
  IoBagOutline,
  IoBag,
} from "react-icons/io5"
```

### Icon Mapping

| Menu | Inactive Icon | Active Icon |
| --- | --- | --- |
| Beranda | `IoHomeOutline` | `IoHome` |
| Produk | `IoGridOutline` | `IoGrid` |
| Feed | `IoPlayCircleOutline` | `IoPlayCircle` |
| Akun | `IoPersonOutline` | `IoPerson` |
| Notifikasi | `IoNotificationsOutline` | - |
| Keranjang | `IoBagOutline` | `IoBag` |

---

## 6. Design Direction

### Style utama

- Background putih / light gray
- Rounded besar
- Soft shadow
- Icon outline
- Active state warna biru
- Badge merah untuk jumlah notifikasi dan keranjang
- Bottom nav floating rounded
- Tampilan bersih, tidak ramai

### Warna rekomendasi

- Primary Blue: `#2563EB`
- Light Blue: `#EFF6FF`
- Text Dark: `#0F172A`
- Text Gray: `#64748B`
- Border: `#E2E8F0`
- Badge Red: `#EF4444`
- Background: `#F8FAFC`

---

## 7. Struktur Folder

Rekomendasi struktur folder Next.js:

```txt
app/
  products/
    page.jsx

  feed/
    page.jsx

  account/
    page.jsx

  api/
    products/
      route.js

components/
  layout/
    Header.jsx
    BottomNav.jsx

  product/
    ProductCard.jsx
    ProductGrid.jsx

hooks/
  useInfiniteProducts.js
```

---

## 8. Header Component

File:

```txt
components/layout/Header.jsx
```

```jsx
"use client"

import { IoBagOutline, IoNotificationsOutline } from "react-icons/io5"

export default function Header() {
  return (
    <header className="sticky top-0 z-40 bg-white px-4 pb-3 pt-4 shadow-sm">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <img
            src="/logo-natalo.png"
            alt="Natalo Petshop"
            className="h-12 w-auto"
          />
        </div>

        <div className="flex items-center gap-3">
          <button className="relative flex h-11 w-11 items-center justify-center rounded-full bg-white text-slate-600 shadow-sm">
            <IoNotificationsOutline size={24} />

            <span className="absolute -right-1 -top-1 flex h-5 min-w-5 items-center justify-center rounded-full bg-red-500 px-1 text-xs font-bold text-white">
              3
            </span>
          </button>

          <button className="relative flex h-11 w-11 items-center justify-center rounded-full bg-white text-slate-700 shadow-sm">
            <IoBagOutline size={25} />

            <span className="absolute -right-1 -top-1 flex h-5 min-w-5 items-center justify-center rounded-full bg-red-500 px-1 text-xs font-bold text-white">
              2
            </span>
          </button>
        </div>
      </div>

      <div className="mt-4">
        <input
          type="text"
          placeholder="Cari di Natalo Petshop..."
          className="w-full rounded-full border border-slate-100 bg-white px-5 py-3 text-sm text-slate-700 shadow-sm outline-none placeholder:text-slate-400 focus:border-blue-500"
        />
      </div>

      <div className="mt-3 flex items-center gap-3 overflow-x-auto border-y border-slate-100 py-2 text-xs text-slate-600">
        <span className="whitespace-nowrap">Area Medan</span>
        <span className="text-blue-300">-</span>
        <span className="whitespace-nowrap">Produk Original 100%</span>
        <span className="text-blue-300">-</span>
        <span className="whitespace-nowrap">Konsultasi via Chat</span>
      </div>
    </header>
  )
}
```

---

## 9. Bottom Navigation Component

File:

```txt
components/layout/BottomNav.jsx
```

```jsx
"use client"

import Link from "next/link"
import { usePathname } from "next/navigation"
import {
  IoHome,
  IoHomeOutline,
  IoGrid,
  IoGridOutline,
  IoPlayCircle,
  IoPlayCircleOutline,
  IoPerson,
  IoPersonOutline,
} from "react-icons/io5"

const navItems = [
  {
    label: "Beranda",
    href: "/",
    icon: IoHomeOutline,
    activeIcon: IoHome,
  },
  {
    label: "Produk",
    href: "/products",
    icon: IoGridOutline,
    activeIcon: IoGrid,
  },
  {
    label: "Feed",
    href: "/feed",
    icon: IoPlayCircleOutline,
    activeIcon: IoPlayCircle,
  },
  {
    label: "Akun",
    href: "/account",
    icon: IoPersonOutline,
    activeIcon: IoPerson,
  },
]

export default function BottomNav() {
  const pathname = usePathname()

  return (
    <nav className="fixed bottom-4 left-1/2 z-50 w-[92%] max-w-md -translate-x-1/2 rounded-[32px] border border-slate-100 bg-white/95 px-3 py-2 shadow-xl backdrop-blur">
      <div className="grid grid-cols-4">
        {navItems.map((item) => {
          const isActive =
            item.href === "/"
              ? pathname === "/"
              : pathname.startsWith(item.href)

          const Icon = isActive ? item.activeIcon : item.icon

          return (
            <Link
              key={item.href}
              href={item.href}
              className={`flex flex-col items-center justify-center rounded-3xl py-2 text-xs font-medium transition ${
                isActive
                  ? "bg-blue-50 text-blue-600"
                  : "text-slate-400"
              }`}
            >
              <Icon size={25} />
              <span className="mt-1">{item.label}</span>
            </Link>
          )
        })}
      </div>
    </nav>
  )
}
```

---

## 10. Product Infinite Scroll

### Target fitur

Halaman produk harus memiliki:

- Grid produk
- 2 kolom di mobile
- 3 kolom di tablet
- 4 kolom di desktop
- Search produk
- Filter kategori
- Infinite scroll
- Loading state
- Empty state
- Semua produk sudah ditampilkan

---

## 11. Product Card

File:

```txt
components/product/ProductCard.jsx
```

```jsx
import Image from "next/image"

export default function ProductCard({ product }) {
  return (
    <div className="overflow-hidden rounded-2xl border border-slate-100 bg-white shadow-sm">
      <div className="relative aspect-square bg-slate-100">
        <Image
          src={product.image}
          alt={product.name}
          fill
          className="object-cover"
          sizes="(max-width: 768px) 50vw, 25vw"
        />
      </div>

      <div className="space-y-1 p-3">
        <h3 className="line-clamp-2 text-sm font-semibold text-slate-900">
          {product.name}
        </h3>

        <p className="text-sm font-bold text-blue-600">
          Rp {product.price.toLocaleString("id-ID")}
        </p>

        <p className="text-xs text-slate-500">
          Stok: {product.stock}
        </p>
      </div>
    </div>
  )
}
```

---

## 12. Infinite Product Hook

File:

```txt
hooks/useInfiniteProducts.js
```

```jsx
"use client"

import { useCallback, useEffect, useRef, useState } from "react"

export function useInfiniteProducts({ search, category }) {
  const [products, setProducts] = useState([])
  const [cursor, setCursor] = useState(null)
  const [hasMore, setHasMore] = useState(true)
  const [loading, setLoading] = useState(false)

  const loaderRef = useRef(null)

  const loadProducts = useCallback(
    async ({ reset = false } = {}) => {
      if (loading) return
      if (!hasMore && !reset) return

      setLoading(true)

      try {
        const params = new URLSearchParams()

        params.set("limit", "12")

        if (!reset && cursor) {
          params.set("cursor", cursor)
        }

        if (search) {
          params.set("search", search)
        }

        if (category && category !== "all") {
          params.set("category", category)
        }

        const res = await fetch(`/api/products?${params.toString()}`)
        const data = await res.json()

        if (reset) {
          setProducts(data.items)
        } else {
          setProducts((prev) => [...prev, ...data.items])
        }

        setCursor(data.nextCursor)
        setHasMore(data.hasMore)
      } catch (error) {
        console.error("Gagal mengambil produk:", error)
      } finally {
        setLoading(false)
      }
    },
    [cursor, search, category, loading, hasMore]
  )

  useEffect(() => {
    setProducts([])
    setCursor(null)
    setHasMore(true)

    loadProducts({ reset: true })
  }, [search, category])

  useEffect(() => {
    const observer = new IntersectionObserver(
      (entries) => {
        const target = entries[0]

        if (target.isIntersecting && hasMore && !loading) {
          loadProducts()
        }
      },
      {
        root: null,
        rootMargin: "300px",
        threshold: 0,
      }
    )

    const currentLoader = loaderRef.current

    if (currentLoader) {
      observer.observe(currentLoader)
    }

    return () => {
      if (currentLoader) {
        observer.unobserve(currentLoader)
      }
    }
  }, [loadProducts, hasMore, loading])

  return {
    products,
    loading,
    hasMore,
    loaderRef,
  }
}
```

---

## 13. Product Page

File:

```txt
app/products/page.jsx
```

```jsx
"use client"

import { useState } from "react"
import ProductCard from "@/components/product/ProductCard"
import { useInfiniteProducts } from "@/hooks/useInfiniteProducts"

const categories = [
  {
    label: "Semua",
    value: "all",
  },
  {
    label: "Kucing",
    value: "cat",
  },
  {
    label: "Anjing",
    value: "dog",
  },
  {
    label: "Aquarium",
    value: "aquarium",
  },
  {
    label: "Obat",
    value: "medicine",
  },
]

export default function ProductsPage() {
  const [search, setSearch] = useState("")
  const [category, setCategory] = useState("all")

  const { products, loading, hasMore, loaderRef } = useInfiniteProducts({
    search,
    category,
  })

  return (
    <main className="min-h-screen bg-slate-50 px-4 pb-28 pt-4">
      <div className="mx-auto max-w-6xl">
        <div className="sticky top-0 z-10 bg-slate-50 pb-4">
          <h1 className="mb-4 text-xl font-bold text-slate-900">
            Produk
          </h1>

          <input
            type="text"
            placeholder="Cari produk..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full rounded-xl border border-slate-100 bg-white px-4 py-3 text-sm outline-none focus:border-blue-500"
          />

          <div className="mt-3 flex gap-2 overflow-x-auto pb-1">
            {categories.map((item) => (
              <button
                key={item.value}
                onClick={() => setCategory(item.value)}
                className={`whitespace-nowrap rounded-full px-4 py-2 text-sm transition ${
                  category === item.value
                    ? "bg-blue-600 text-white"
                    : "border border-slate-100 bg-white text-slate-700"
                }`}
              >
                {item.label}
              </button>
            ))}
          </div>
        </div>

        <div className="grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-4">
          {products.map((product) => (
            <ProductCard key={product.id} product={product} />
          ))}
        </div>

        {loading && (
          <p className="py-6 text-center text-sm text-slate-500">
            Memuat produk...
          </p>
        )}

        {!loading && products.length === 0 && (
          <p className="py-10 text-center text-sm text-slate-500">
            Produk tidak ditemukan.
          </p>
        )}

        {!hasMore && products.length > 0 && (
          <p className="py-6 text-center text-sm text-slate-400">
            Semua produk sudah ditampilkan.
          </p>
        )}

        <div ref={loaderRef} className="h-10" />
      </div>
    </main>
  )
}
```

---

## 14. API Dummy Product

File:

```txt
app/api/products/route.js
```

```js
const dummyProducts = Array.from({ length: 80 }).map((_, index) => {
  const categories = ["cat", "dog", "aquarium", "medicine"]

  return {
    id: String(index + 1),
    name: `Produk Natalo ${index + 1}`,
    price: 25000 + index * 1000,
    stock: 10 + index,
    category: categories[index % categories.length],
    image: "https://placehold.co/600x600/png",
  }
})

export async function GET(req) {
  const { searchParams } = new URL(req.url)

  const limit = Number(searchParams.get("limit")) || 12
  const cursor = searchParams.get("cursor")
  const search = searchParams.get("search") || ""
  const category = searchParams.get("category") || ""

  let filteredProducts = dummyProducts

  if (search) {
    filteredProducts = filteredProducts.filter((product) =>
      product.name.toLowerCase().includes(search.toLowerCase())
    )
  }

  if (category) {
    filteredProducts = filteredProducts.filter(
      (product) => product.category === category
    )
  }

  let startIndex = 0

  if (cursor) {
    const cursorIndex = filteredProducts.findIndex(
      (product) => product.id === cursor
    )

    startIndex = cursorIndex + 1
  }

  const items = filteredProducts.slice(startIndex, startIndex + limit)

  const lastItem = items[items.length - 1]

  const nextCursor = lastItem ? lastItem.id : null

  const hasMore = startIndex + limit < filteredProducts.length

  return Response.json({
    items,
    nextCursor,
    hasMore,
  })
}
```

---

## 15. Next Image Config

Karena dummy image menggunakan domain `placehold.co`, tambahkan konfigurasi berikut.

File:

```txt
next.config.js
```

```js
const nextConfig = {
  images: {
    remotePatterns: [
      {
        protocol: "https",
        hostname: "placehold.co",
      },
    ],
  },
}

export default nextConfig
```

---

## 16. Testing Checklist

### Header

- [ ] Logo tampil
- [ ] Icon notifikasi tampil
- [ ] Badge notifikasi tampil
- [ ] Icon keranjang tampil
- [ ] Badge keranjang tampil
- [ ] Avatar akun sudah tidak tampil di header
- [ ] Search bar tetap tampil rapi

### Bottom Navigation

- [ ] Menu Beranda tampil
- [ ] Menu Produk tampil
- [ ] Menu Feed tampil
- [ ] Menu Akun tampil
- [ ] Menu Keranjang sudah hilang dari bottom nav
- [ ] Active state berubah sesuai halaman
- [ ] Bottom nav tidak menutupi konten utama

### Produk

- [ ] Produk tampil 2 kolom di mobile
- [ ] Search produk berjalan
- [ ] Filter kategori berjalan
- [ ] Infinite scroll berjalan
- [ ] Loading state muncul
- [ ] Empty state muncul saat produk tidak ditemukan
- [ ] End state muncul saat produk habis
- [ ] Tidak ada produk double saat scroll

---

## 17. Development Order

Urutan pengerjaan yang disarankan:

1. Update icon library
2. Buat Header baru
3. Buat Bottom Navigation baru
4. Buat ProductCard
5. Buat API dummy products
6. Buat useInfiniteProducts hook
7. Buat Product Page
8. Test infinite scroll
9. Test search dan kategori
10. Sambungkan ke database asli

---

## 18. Next Step Setelah Produk Stabil

Setelah halaman produk stabil, lanjut ke tahap berikutnya:

### Beranda / Feed Infinite Scroll

Tahap lanjutan:

- Membuat halaman Feed
- Membuat struktur data feed
- Membuat konten video dari admin
- Membuat konten video dari user
- Membuat like dan comment
- Membuat konten promo
- Membuat produk muncul di feed
- Optimasi video autoplay
- Pause video saat tidak terlihat
- Lazy load video

---

Done. Ini sudah bisa kamu kasih ke developer sebagai **project brief + implementation guide**.
