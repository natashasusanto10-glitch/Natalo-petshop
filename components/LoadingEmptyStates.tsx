"use client";

import Link from "next/link";

function Skeleton({
  width = "100%",
  height = 16,
  radius = 6,
  className = "",
}: {
  width?: number | string;
  height?: number | string;
  radius?: number;
  className?: string;
}) {
  return (
    <div
      className={`animate-pulse bg-zinc-100 ${className}`}
      style={{ width, height, borderRadius: radius }}
    />
  );
}

export function ProductCardSkeleton() {
  return (
    <div className="overflow-hidden rounded-xl border border-zinc-100 bg-white">
      <Skeleton height={160} radius={0} />
      <div className="p-3">
        <Skeleton className="mb-2" height={13} width="90%" />
        <Skeleton className="mb-3" height={13} width="60%" />
        <Skeleton className="mb-3" height={18} width="45%" />
        <Skeleton height={32} radius={8} />
      </div>
    </div>
  );
}

export function ProductGridSkeleton({ n = 8 }: { n?: number }) {
  return (
    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      {Array.from({ length: n }).map((_, index) => (
        <ProductCardSkeleton key={index} />
      ))}
    </div>
  );
}

export function TableRowSkeleton({
  cols = 4,
  rows = 6,
}: {
  cols?: number;
  rows?: number;
}) {
  return (
    <>
      {Array.from({ length: rows }).map((_, rowIndex) => (
        <tr key={rowIndex}>
          {Array.from({ length: cols }).map((_, colIndex) => (
            <td className="px-3.5 py-3" key={colIndex}>
              <Skeleton
                height={13}
                width={colIndex === 0 ? "60%" : colIndex === 1 ? "80%" : "40%"}
              />
            </td>
          ))}
        </tr>
      ))}
    </>
  );
}

function EmptyBase({
  emoji,
  title,
  desc,
  action,
}: {
  emoji: string;
  title: string;
  desc: string;
  action?: React.ReactNode;
}) {
  return (
    <div className="flex flex-col items-center justify-center px-6 py-14 text-center">
      <div className="mb-3 text-5xl opacity-75" aria-hidden="true">
        {emoji}
      </div>
      <h3 className="mb-1.5 text-base font-medium text-zinc-950">{title}</h3>
      <p className="max-w-xs text-sm leading-6 text-zinc-500">{desc}</p>
      {action && <div className="mt-5">{action}</div>}
    </div>
  );
}

export function EmptySearch({
  query = "",
  onReset,
}: {
  query?: string;
  onReset?: () => void;
}) {
  return (
    <EmptyBase
      emoji="🔍"
      title={query ? `Tidak ada hasil untuk "${query}"` : "Tidak ada produk ditemukan"}
      desc="Coba kata kunci yang berbeda, periksa ejaan, atau cari dengan kata yang lebih umum."
      action={
        <div className="flex flex-wrap justify-center gap-2">
          {onReset && (
            <button
              className="rounded-lg bg-[#D85A30] px-5 py-2.5 text-sm font-medium text-white transition hover:bg-[#c64d27]"
              onClick={onReset}
              type="button"
            >
              Reset semua filter
            </button>
          )}
          {["Makanan kucing", "Obat anjing", "Filter aquarium"].map((suggestion) => (
            <button
              className="rounded-full border border-zinc-200 bg-white px-3.5 py-1.5 text-xs text-zinc-700 transition hover:border-zinc-300 hover:bg-zinc-50"
              key={suggestion}
              onClick={() => {
                window.location.href = `/search?q=${encodeURIComponent(suggestion)}`;
              }}
              type="button"
            >
              {suggestion}
            </button>
          ))}
        </div>
      }
    />
  );
}

export function EmptyCategory({ category = "kategori ini" }: { category?: string }) {
  return (
    <EmptyBase
      emoji="📦"
      title={`Belum ada produk di ${category}`}
      desc="Produk di kategori ini sedang kami siapkan. Cek kembali nanti ya!"
      action={<PrimaryLink href="/products">Lihat semua produk</PrimaryLink>}
    />
  );
}

export function EmptyCart() {
  return (
    <EmptyBase
      emoji="🛒"
      title="Keranjang kamu masih kosong"
      desc="Yuk mulai belanja! Ada banyak produk hewan peliharaan yang menunggu."
      action={<PrimaryLink href="/products">Mulai Belanja</PrimaryLink>}
    />
  );
}

export function EmptyOrders({
  filtered = false,
}: {
  filtered?: boolean;
}) {
  return (
    <EmptyBase
      emoji="📋"
      title={filtered ? "Tidak ada pesanan" : "Belum ada pesanan"}
      desc={
        filtered
          ? "Coba ganti filter status pesanan di atas."
          : "Pesanan kamu akan muncul di sini setelah kamu berhasil checkout."
      }
      action={<PrimaryLink href="/products">Belanja sekarang</PrimaryLink>}
    />
  );
}

export function EmptyWishlist() {
  return (
    <EmptyBase
      emoji="🤍"
      title="Wishlist masih kosong"
      desc="Simpan produk favorit kamu di sini agar mudah ditemukan nanti."
      action={<PrimaryLink href="/products">Jelajahi produk</PrimaryLink>}
    />
  );
}

export function EmptyAdminOrders() {
  return (
    <EmptyBase
      emoji="📬"
      title="Belum ada order masuk"
      desc="Order dari pembeli akan muncul di sini secara real-time."
    />
  );
}

export function PageLoader() {
  return (
    <div className="flex min-h-[60vh] flex-col items-center justify-center gap-3">
      <div className="animate-spin text-3xl" aria-hidden="true">
        🐾
      </div>
      <div className="text-sm text-zinc-500">Memuat...</div>
    </div>
  );
}

function PrimaryLink({
  children,
  href,
}: {
  children: React.ReactNode;
  href: string;
}) {
  return (
    <Link
      className="inline-flex rounded-lg bg-[#D85A30] px-5 py-2.5 text-sm font-medium text-white transition hover:bg-[#c64d27]"
      href={href}
    >
      {children}
    </Link>
  );
}
