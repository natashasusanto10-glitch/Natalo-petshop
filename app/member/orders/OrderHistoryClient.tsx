"use client";

import Image from "next/image";
import Link from "next/link";
import { useMemo, useState, type KeyboardEvent } from "react";
import {
  FiAlertCircle,
  FiArrowLeft,
  FiCheckCircle,
  FiChevronDown,
  FiClock,
  FiFileText,
  FiHelpCircle,
  FiMapPin,
  FiMoreVertical,
  FiPackage,
  FiRefreshCw,
  FiSearch,
  FiShoppingBag,
  FiTruck,
  FiXCircle,
} from "react-icons/fi";
import { ReorderButton } from "@/components/ReorderButton";
import { formatRupiah } from "@/lib/format";

type OrderGroup = "all" | "unpaid" | "processing" | "shipped" | "completed" | "cancelled";
type SortKey = "newest" | "oldest" | "total-desc";

type OrderHistoryItem = {
  id: string;
  name: string;
  quantity: number;
  price: number;
  productId: string;
  imageUrl: string | null;
  categoryName: string | null;
};

type OrderHistoryOrder = {
  id: string;
  orderNumber: string;
  createdAt: string;
  status: string;
  paymentStatus: string;
  total: number;
  subtotal: number;
  paymentUrl: string | null;
  biteshipTrackingUrl: string | null;
  orderType: string;
  pickupMapsUrl: string;
  items: OrderHistoryItem[];
};

type Props = {
  orders: OrderHistoryOrder[];
};

const STATUS_TABS: { key: OrderGroup; label: string }[] = [
  { key: "all", label: "Semua" },
  { key: "unpaid", label: "Belum Bayar" },
  { key: "processing", label: "Diproses" },
  { key: "shipped", label: "Dikirim" },
  { key: "completed", label: "Selesai" },
  { key: "cancelled", label: "Dibatalkan" },
];

const STATUS_META = {
  unpaid: {
    label: "Belum Bayar",
    icon: FiAlertCircle,
    className: "bg-orange-50 text-orange-700",
  },
  processing: {
    label: "Diproses",
    icon: FiClock,
    className: "bg-blue-50 text-blue-700",
  },
  shipped: {
    label: "Dikirim",
    icon: FiTruck,
    className: "bg-blue-50 text-blue-700",
  },
  completed: {
    label: "Selesai",
    icon: FiCheckCircle,
    className: "bg-emerald-50 text-emerald-700",
  },
  cancelled: {
    label: "Dibatalkan",
    icon: FiXCircle,
    className: "bg-rose-50 text-rose-600",
  },
} satisfies Record<Exclude<OrderGroup, "all">, { label: string; icon: typeof FiClock; className: string }>;

function getOrderGroup(order: { status: string; paymentStatus: string }): Exclude<OrderGroup, "all"> {
  if (
    order.status === "CANCELLED" ||
    order.status === "REFUNDED" ||
    order.paymentStatus === "FAILED" ||
    order.paymentStatus === "EXPIRED" ||
    order.paymentStatus === "REFUNDED"
  ) {
    return "cancelled";
  }

  if (order.status === "DELIVERED") return "completed";
  if (order.status === "SHIPPED") return "shipped";

  if (order.paymentStatus === "PAID" || order.status === "PAID" || order.status === "PROCESSING") {
    return "processing";
  }

  return "unpaid";
}

function formatOrderDate(value: string) {
  const parts = new Intl.DateTimeFormat("id-ID", {
    day: "numeric",
    month: "long",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
    timeZone: "Asia/Jakarta",
  })
    .formatToParts(new Date(value));
  const get = (type: Intl.DateTimeFormatPartTypes) =>
    parts.find((part) => part.type === type)?.value ?? "";

  return `${get("day")} ${get("month")} ${get("year")} · ${get("hour")}:${get("minute")}`;
}

function normalizeSearch(value: string) {
  return value.toLowerCase().trim();
}

function itemDescription(order: OrderHistoryOrder) {
  const count = order.items.reduce((sum, item) => sum + item.quantity, 0);
  return `${count} barang`;
}

function ProductThumbnail({ item }: { item: OrderHistoryItem }) {
  if (item.imageUrl) {
    return (
      <div className="relative h-12 w-12 shrink-0 overflow-hidden rounded-xl bg-white ring-1 ring-black/5">
        <Image
          src={item.imageUrl}
          alt={item.name}
          fill
          sizes="48px"
          className="object-cover"
        />
      </div>
    );
  }

  return (
    <div className="grid h-12 w-12 shrink-0 place-items-center rounded-xl bg-slate-100 text-slate-500 ring-1 ring-black/5">
      <FiPackage className="h-5 w-5" aria-hidden="true" />
    </div>
  );
}

function StatusPill({ group }: { group: Exclude<OrderGroup, "all"> }) {
  const meta = STATUS_META[group];
  const Icon = meta.icon;

  return (
    <span className={`inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-[11.5px] font-semibold ${meta.className}`}>
      <Icon className="h-3.5 w-3.5" aria-hidden="true" />
      {meta.label}
    </span>
  );
}

function OrderSearchBar({
  value,
  onChange,
}: {
  value: string;
  onChange: (value: string) => void;
}) {
  return (
    <label className="relative block">
      <span className="sr-only">Cari riwayat pesanan</span>
      <FiSearch className="absolute left-4 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" aria-hidden="true" />
      <input
        value={value}
        onChange={(event) => onChange(event.target.value)}
        placeholder="Cari produk atau no. pesanan..."
        className="h-12 w-full rounded-2xl border border-slate-100 bg-white pl-11 pr-4 text-[13px] font-semibold text-slate-900 shadow-[0_8px_24px_-16px_rgba(15,23,42,0.30)] outline-none transition placeholder:text-slate-400 focus:border-blue-200 focus:ring-4 focus:ring-blue-100"
      />
    </label>
  );
}

function OrderFilterChips({
  activeStatus,
  counts,
  onChange,
}: {
  activeStatus: OrderGroup;
  counts: Record<OrderGroup, number>;
  onChange: (status: OrderGroup) => void;
}) {
  return (
    <div className="-mx-4 flex gap-2 overflow-x-auto px-4 py-1 [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
      {STATUS_TABS.map((tab) => {
        const active = tab.key === activeStatus;
        return (
          <button
            key={tab.key}
            type="button"
            onClick={() => onChange(tab.key)}
            aria-pressed={active}
            className={`min-h-11 shrink-0 rounded-full px-3.5 py-2 text-sm font-black transition ${
              active
                ? "bg-slate-900 text-white shadow-sm"
                : "bg-white text-slate-600 ring-1 ring-slate-200 active:bg-slate-50"
            }`}
          >
            {tab.label} <span className={active ? "text-white/80" : "text-slate-400"}>{counts[tab.key]}</span>
          </button>
        );
      })}
    </div>
  );
}

function OrderSortControl({
  value,
  onChange,
}: {
  value: SortKey;
  onChange: (value: SortKey) => void;
}) {
  return (
    <label className="relative inline-flex items-center">
      <span className="sr-only">Urutkan pesanan</span>
      <select
        value={value}
        onChange={(event) => onChange(event.target.value as SortKey)}
        className="h-10 appearance-none rounded-full border border-slate-200 bg-white py-0 pl-4 pr-9 text-xs font-black text-slate-600 outline-none focus:border-blue-200 focus:ring-4 focus:ring-blue-100"
      >
        <option value="newest">Terbaru</option>
        <option value="oldest">Terlama</option>
        <option value="total-desc">Total terbesar</option>
      </select>
      <FiChevronDown className="pointer-events-none absolute right-3 h-4 w-4 text-slate-400" aria-hidden="true" />
    </label>
  );
}

function OrderCard({ order }: { order: OrderHistoryOrder }) {
  const [menuOpen, setMenuOpen] = useState(false);
  const group = getOrderGroup(order);
  const primaryItem = order.items[0] ?? {
    id: `${order.id}-empty`,
    name: "Pesanan Natalo Petshop",
    quantity: 0,
    price: 0,
    productId: "",
    imageUrl: null,
    categoryName: null,
  };
  const detailHref = `/pesanan/${order.orderNumber}`;
  const isSelfPickup = order.orderType === "SELF_PICKUP";
  const helpHref = `/bantuan?order=${encodeURIComponent(order.orderNumber)}`;

  function openDetail() {
    window.location.href = detailHref;
  }

  function handleKeyDown(event: KeyboardEvent<HTMLElement>) {
    if (event.target !== event.currentTarget) return;
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      openDetail();
    }
  }

  async function copyOrderNumber() {
    await navigator.clipboard?.writeText(order.orderNumber);
    setMenuOpen(false);
  }

  return (
    <article
      role="link"
      tabIndex={0}
      onClick={openDetail}
      onKeyDown={handleKeyDown}
      aria-label={`Lihat detail pesanan ${order.orderNumber}`}
      className="cursor-pointer rounded-[24px] bg-white px-5 py-4 shadow-[0_4px_20px_-8px_rgba(15,23,42,0.08)] ring-1 ring-slate-100 transition active:scale-[0.995] active:bg-blue-50/30"
    >
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0 flex-1 pt-1">
          <p className="truncate text-sm font-bold leading-5 text-slate-600">
            {formatOrderDate(order.createdAt)}
          </p>
        </div>
        <div className="relative flex shrink-0 items-center gap-2">
          <StatusPill group={group} />
          <button
            type="button"
            onClick={(event) => {
              event.stopPropagation();
              setMenuOpen((open) => !open);
            }}
            aria-label="Aksi pesanan"
            className="grid h-9 w-9 place-items-center rounded-full text-slate-500 transition active:bg-slate-100"
          >
            <FiMoreVertical className="h-4 w-4" aria-hidden="true" />
          </button>
          {menuOpen && (
            <div
              onClick={(event) => event.stopPropagation()}
              className="absolute right-0 top-10 z-20 w-56 overflow-hidden rounded-2xl border border-slate-100 bg-white py-1 shadow-[0_18px_45px_-18px_rgba(15,23,42,0.35)]"
            >
              <Link
                href={detailHref}
                className="flex items-center gap-2 px-4 py-2.5 text-sm font-bold text-slate-700 hover:bg-slate-50"
              >
                <FiFileText className="h-4 w-4" aria-hidden="true" />
                Lihat detail pesanan
              </Link>
              {isSelfPickup && (
                <a
                  href={order.pickupMapsUrl}
                  target="_blank"
                  rel="noreferrer"
                  className="flex items-center gap-2 px-4 py-2.5 text-sm font-bold text-slate-700 hover:bg-slate-50"
                >
                  <FiMapPin className="h-4 w-4" aria-hidden="true" />
                  Buka Google Maps
                </a>
              )}
              <button
                type="button"
                onClick={() => void copyOrderNumber()}
                className="flex w-full items-center gap-2 px-4 py-2.5 text-left text-sm font-bold text-slate-700 hover:bg-slate-50"
              >
                <FiFileText className="h-4 w-4" aria-hidden="true" />
                Salin nomor pesanan
              </button>
              <Link
                href={helpHref}
                className="flex items-center gap-2 px-4 py-2.5 text-sm font-bold text-slate-700 hover:bg-slate-50"
              >
                <FiHelpCircle className="h-4 w-4" aria-hidden="true" />
                Bantuan pesanan
              </Link>
            </div>
          )}
        </div>
      </div>

      <div className="mt-4 flex gap-3.5">
        <ProductThumbnail item={primaryItem} />

        <div className="min-w-0 flex-1">
          <h2 className="line-clamp-2 text-[13.5px] font-semibold leading-snug text-slate-900">
            {primaryItem.name}
          </h2>
          <p className="mt-1 text-xs font-semibold text-slate-500">
            {itemDescription(order)}
          </p>
        </div>
      </div>

      <div className="mt-4 border-t border-dashed border-slate-200 pt-4">
        <div className="flex items-end justify-between gap-3">
          <div className="min-w-0">
            <p className="text-[10px] font-black uppercase tracking-wide text-slate-400">
              Total Belanja
            </p>
            <p className="mt-0.5 truncate text-base font-black leading-tight text-slate-950">
              {formatRupiah(order.total)}
            </p>
          </div>
          <div onClick={(event) => event.stopPropagation()} className="shrink-0">
            <ReorderButton
              orderId={order.id}
              className="min-h-10 justify-center border-0 bg-gradient-to-br from-blue-600 to-blue-700 px-4 py-0 text-[12.5px] font-semibold text-white shadow-[0_4px_12px_-2px_rgba(37,99,235,0.25)] hover:bg-blue-700 hover:text-white"
            >
              <FiRefreshCw className="h-3.5 w-3.5" aria-hidden="true" />
              Beli Lagi
            </ReorderButton>
          </div>
        </div>
      </div>
    </article>
  );
}

function OrderEmptyState({
  type,
}: {
  type: "all" | "filter" | "search";
}) {
  const copy = {
    all: {
      title: "Belum ada pesanan",
      subtitle: "Yuk mulai belanja kebutuhan hewan kesayanganmu.",
      showButton: true,
    },
    filter: {
      title: "Belum ada pesanan dengan status ini",
      subtitle: "Coba pilih status lain atau lihat semua pesanan.",
      showButton: false,
    },
    search: {
      title: "Pesanan tidak ditemukan",
      subtitle: "Coba cari nama produk yang pernah kamu beli atau nomor pesanan.",
      showButton: false,
    },
  }[type];

  return (
    <section className="rounded-[24px] bg-white px-6 py-10 text-center shadow-[0_4px_20px_-8px_rgba(15,23,42,0.08)] ring-1 ring-slate-100">
      <div className="mx-auto grid h-14 w-14 place-items-center rounded-2xl bg-blue-50 text-blue-700">
        <FiShoppingBag className="h-6 w-6" aria-hidden="true" />
      </div>
      <h2 className="mt-4 text-base font-black text-slate-950">{copy.title}</h2>
      <p className="mx-auto mt-1 max-w-xs text-sm font-semibold leading-6 text-slate-500">
        {copy.subtitle}
      </p>
      {copy.showButton && (
        <Link
          href="/products"
          className="mt-5 inline-flex min-h-11 items-center rounded-full bg-blue-600 px-5 text-sm font-black text-white transition active:scale-[0.98]"
        >
          Mulai Belanja
        </Link>
      )}
    </section>
  );
}

export function OrderErrorState() {
  return (
    <main className="min-h-screen bg-[#F6F7FB] px-4 py-8">
      <section className="mx-auto max-w-4xl rounded-[24px] bg-white px-6 py-10 text-center shadow-[0_4px_20px_-8px_rgba(15,23,42,0.08)] ring-1 ring-slate-100">
        <div className="mx-auto grid h-14 w-14 place-items-center rounded-2xl bg-rose-50 text-rose-600">
          <FiAlertCircle className="h-6 w-6" aria-hidden="true" />
        </div>
        <h1 className="mt-4 text-base font-black text-slate-950">Gagal memuat riwayat pesanan</h1>
        <p className="mx-auto mt-1 max-w-xs text-sm font-semibold leading-6 text-slate-500">
          Periksa koneksi internetmu lalu coba lagi.
        </p>
        <button
          type="button"
          onClick={() => window.location.reload()}
          className="mt-5 inline-flex min-h-11 items-center rounded-full bg-blue-600 px-5 text-sm font-black text-white transition active:scale-[0.98]"
        >
          Coba Lagi
        </button>
      </section>
    </main>
  );
}

export function OrderHistoryClient({ orders }: Props) {
  const [activeStatus, setActiveStatus] = useState<OrderGroup>("all");
  const [query, setQuery] = useState("");
  const [sort, setSort] = useState<SortKey>("newest");

  const counts = useMemo(() => {
    const next: Record<OrderGroup, number> = {
      all: orders.length,
      unpaid: 0,
      processing: 0,
      shipped: 0,
      completed: 0,
      cancelled: 0,
    };

    orders.forEach((order) => {
      next[getOrderGroup(order)] += 1;
    });

    return next;
  }, [orders]);

  const visibleOrders = useMemo(() => {
    const normalizedQuery = normalizeSearch(query);
    return orders
      .filter((order) => activeStatus === "all" || getOrderGroup(order) === activeStatus)
      .filter((order) => {
        if (!normalizedQuery) return true;
        const orderNumberMatch = order.orderNumber.toLowerCase().includes(normalizedQuery);
        const itemNameMatch = order.items.some((item) =>
          item.name.toLowerCase().includes(normalizedQuery),
        );
        return orderNumberMatch || itemNameMatch;
      })
      .sort((a, b) => {
        if (sort === "oldest") return new Date(a.createdAt).getTime() - new Date(b.createdAt).getTime();
        if (sort === "total-desc") return b.total - a.total;
        return new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime();
      });
  }, [activeStatus, orders, query, sort]);

  const emptyType = orders.length === 0 ? "all" : query.trim() ? "search" : "filter";

  return (
    <main
      className="min-h-screen pb-[calc(96px+env(safe-area-inset-bottom))]"
      style={{
        background:
          "radial-gradient(1200px 600px at 10% -10%, #DBEAFE 0%, transparent 60%), radial-gradient(900px 500px at 100% 100%, #E0F2FE 0%, transparent 55%), #F6F7FB",
      }}
    >
      <header className="sticky top-0 z-50 border-b border-slate-200/70 bg-white/90 px-4 py-3 shadow-[0_8px_24px_-20px_rgba(15,23,42,0.4)] backdrop-blur [padding-top:calc(0.75rem+env(safe-area-inset-top))]">
        <div className="mx-auto flex max-w-4xl items-center gap-3">
          <Link
            href="/member"
            aria-label="Kembali ke akun"
            className="-ml-1 inline-flex min-h-11 shrink-0 items-center pr-1 text-slate-800 transition active:opacity-70"
          >
            <FiArrowLeft className="h-5 w-5" aria-hidden="true" />
          </Link>
          <div className="min-w-0">
            <h1 className="truncate text-xl font-black leading-tight text-slate-950">
              Riwayat Pesanan
            </h1>
            <p className="mt-0.5 truncate text-xs font-semibold text-slate-500">
              Lihat dan kelola semua pesananmu
            </p>
          </div>
        </div>
      </header>

      <div className="mx-auto max-w-4xl px-4 py-4 md:py-8">
        <section className="space-y-3">
          <OrderSearchBar value={query} onChange={setQuery} />
          <OrderFilterChips
            activeStatus={activeStatus}
            counts={counts}
            onChange={setActiveStatus}
          />
          <div className="flex items-center justify-between gap-3">
            <p className="text-xs font-bold text-slate-500">
              {visibleOrders.length} pesanan ditampilkan
            </p>
            <OrderSortControl value={sort} onChange={setSort} />
          </div>
        </section>

        <section className="mt-4 space-y-4">
          {visibleOrders.length > 0 ? (
            visibleOrders.map((order) => <OrderCard key={order.id} order={order} />)
          ) : (
            <OrderEmptyState type={emptyType} />
          )}
        </section>
      </div>
    </main>
  );
}
