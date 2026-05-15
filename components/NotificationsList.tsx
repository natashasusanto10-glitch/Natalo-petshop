"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useMemo, useState } from "react";
import {
  IoArrowBack,
  IoCheckmarkCircle,
  IoChevronForward,
  IoMegaphoneOutline,
  IoNotificationsOutline,
  IoPricetagOutline,
} from "react-icons/io5";
import { NotificationReviewSheet } from "@/components/NotificationReviewSheet";

type NotificationType = "order" | "promo" | "announcement";
type TabId = "all" | "order" | "promo" | "announcement";

type Notification = {
  id: string;
  title: string;
  body: string;
  url: string | null;
  segment: string;
  type?: string;
  ctaLabel?: string | null;
  createdAt: string;
  read: boolean;
  reviewSummary?: {
    totalItems: number;
    reviewedItems: number;
    allReviewed: boolean;
  } | null;
};

type FetchResponse = {
  ok: boolean;
  loggedIn: boolean;
  unreadCount: number;
  items: Notification[];
  error?: string;
};

const TABS: Array<{ id: TabId; label: string }> = [
  { id: "all", label: "Semua" },
  { id: "order", label: "Pesanan" },
  { id: "promo", label: "Promo" },
  { id: "announcement", label: "Pengumuman" },
];

function formatRelativeTime(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime();
  const minutes = Math.floor(diff / 60_000);
  if (minutes < 1) return "baru saja";
  if (minutes < 60) return `${minutes} menit lalu`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours} jam lalu`;
  const days = Math.floor(hours / 24);
  if (days === 1) return "kemarin";
  if (days < 7) return `${days} hari lalu`;
  return new Date(iso).toLocaleDateString("id-ID", {
    day: "numeric",
    month: "short",
    year: "numeric",
  });
}

function notificationType(item: Notification): NotificationType {
  if (item.type === "promo") return "promo";
  if (item.type === "order") return "order";
  return "announcement";
}

function isReviewPrompt(item: Notification) {
  const text = `${item.title} ${item.body}`.toLowerCase();
  return notificationType(item) === "order" && (text.includes("sampai") || text.includes("selesai"));
}

function extractOrderNumber(item: Notification) {
  const match = `${item.title} ${item.body} ${item.url ?? ""}`.match(/ORD-[A-Z0-9-]+/i);
  return match?.[0] ?? null;
}

function EmptyState({ tab }: { tab: TabId }) {
  const copy =
    tab === "order"
      ? "Update pesanan otomatis akan muncul di sini."
      : tab === "promo"
        ? "Promo resmi dari admin Natalo Petshop akan muncul di sini."
        : tab === "announcement"
          ? "Pengumuman resmi dari admin Natalo Petshop akan muncul di sini."
          : "Update pesanan, promo, dan pengumuman akan muncul di sini.";

  return (
    <div className="rounded-2xl border border-slate-200 bg-white px-6 py-12 text-center shadow-sm">
      <IoNotificationsOutline className="mx-auto h-12 w-12 text-slate-300" aria-hidden="true" />
      <p className="mt-3 text-sm font-bold text-slate-800">Belum ada notifikasi</p>
      <p className="mt-1 text-sm text-slate-500">{copy}</p>
    </div>
  );
}

function IconBadge({ type }: { type: NotificationType }) {
  if (type === "order") {
    return (
      <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-emerald-50 text-emerald-600">
        <IoCheckmarkCircle className="h-6 w-6" aria-hidden="true" />
      </span>
    );
  }

  if (type === "promo") {
    return (
      <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-blue-50 text-blue-600">
        <IoPricetagOutline className="h-5 w-5" aria-hidden="true" />
      </span>
    );
  }

  return (
    <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-violet-50 text-violet-600">
      <IoMegaphoneOutline className="h-5 w-5" aria-hidden="true" />
    </span>
  );
}

function RatingStrip({
  onOpen,
  disabled,
  allReviewed,
}: {
  onOpen: () => void;
  disabled?: boolean;
  allReviewed?: boolean;
}) {
  return (
    <button
      type="button"
      onClick={onOpen}
      disabled={disabled}
      className="mt-4 block w-full rounded-xl bg-emerald-50 px-3 py-3 text-left transition active:scale-[0.99] active:bg-emerald-100 disabled:opacity-60"
      aria-label={allReviewed ? "Semua produk sudah direview" : "Beri rating dan ulasan"}
    >
      <div className="flex items-center gap-1" aria-hidden="true">
        {[1, 2, 3, 4, 5].map((value) => (
          <span
            key={value}
            className={`text-2xl leading-none ${allReviewed ? "text-amber-400" : "text-slate-300"}`}
          >
            {allReviewed ? "\u2605" : "\u2606"}
          </span>
        ))}
      </div>
      <p className="mt-2 text-xs font-semibold text-emerald-900">
        {allReviewed
          ? "Semua produk di pesanan ini sudah direview"
          : "Bantu beri rating & ulasan untuk produk yang kamu beli"}
      </p>
    </button>
  );
}

function NotificationCard({
  item,
  onRead,
  onRefresh,
}: {
  item: Notification;
  onRead: (item: Notification) => void;
  onRefresh: () => void;
}) {
  const type = notificationType(item);
  const reviewPrompt = isReviewPrompt(item);
  const orderNumber = extractOrderNumber(item);
  const allReviewed = Boolean(item.reviewSummary?.allReviewed);
  const [reviewSheetOpen, setReviewSheetOpen] = useState(false);
  const ctaLabel =
    type === "announcement"
      ? "Lihat Detail"
      : item.ctaLabel ??
        (reviewPrompt ? "Lihat Pesanan" : type === "order" ? "Lihat Pesanan" : type === "promo" ? "Lihat Promo" : "Lihat Detail");
  const href =
    type === "announcement"
      ? `/notifications/${item.id}`
      : reviewPrompt
        ? item.url ?? (orderNumber ? `/pesanan/${encodeURIComponent(orderNumber)}` : null)
        : item.url;
  const sourceLabel =
    type === "promo" ? "Promo dari Admin" : type === "announcement" ? "Pengumuman dari Admin" : orderNumber ? `Order ID: ${orderNumber}` : "Update Pesanan";
  const accent =
    type === "order"
      ? "bg-emerald-500"
      : type === "promo"
        ? "bg-gradient-to-b from-blue-500 via-emerald-500 to-orange-400"
        : "bg-violet-500";

  return (
    <article
      className={`relative overflow-hidden rounded-2xl border bg-white p-4 shadow-sm transition ${
        item.read ? "border-slate-200" : "border-blue-200 shadow-blue-100"
      }`}
    >
      <span className={`absolute inset-y-0 left-0 w-1.5 ${accent}`} aria-hidden="true" />
      <div className="flex items-start gap-3 pl-1.5">
        <IconBadge type={type} />
        <div className="min-w-0 flex-1">
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0">
              <p className="text-[15px] font-extrabold leading-snug text-slate-950">{item.title}</p>
              <p className="mt-1 text-xs font-bold text-slate-500">{sourceLabel}</p>
            </div>
            {!item.read && <span className="mt-1 h-2.5 w-2.5 shrink-0 rounded-full bg-blue-500" aria-label="Belum dibaca" />}
          </div>

          <p className="mt-2 text-sm leading-relaxed text-slate-600">{item.body}</p>
          {reviewPrompt && (
            <RatingStrip
              onOpen={() => {
                onRead(item);
                if (orderNumber) setReviewSheetOpen(true);
              }}
              disabled={!orderNumber}
              allReviewed={allReviewed}
            />
          )}

          <div className="mt-4 flex items-center justify-between gap-3">
            <span className="text-xs font-medium text-slate-400">{formatRelativeTime(item.createdAt)}</span>
          </div>

          {href ? (
            <Link
              href={href}
              onClick={() => onRead(item)}
              className={`mt-4 inline-flex w-full items-center justify-center gap-2 rounded-xl px-4 py-3 text-sm font-extrabold text-white transition active:scale-[0.99] ${
                type === "order" ? "bg-blue-600 hover:bg-blue-700" : type === "promo" ? "bg-blue-600 hover:bg-blue-700" : "bg-slate-900 hover:bg-slate-800"
              }`}
            >
              {ctaLabel}
              <IoChevronForward className="h-4 w-4" aria-hidden="true" />
            </Link>
          ) : (
            <button
              type="button"
              onClick={() => onRead(item)}
              className="mt-4 inline-flex w-full items-center justify-center rounded-xl border border-slate-200 px-4 py-3 text-sm font-extrabold text-slate-700 transition active:scale-[0.99]"
            >
              Mengerti
            </button>
          )}
        </div>
      </div>
      {reviewSheetOpen && orderNumber && (
        <NotificationReviewSheet
          orderNumber={orderNumber}
          onClose={() => setReviewSheetOpen(false)}
          onSubmitted={() => {
            onRefresh();
            window.dispatchEvent(new CustomEvent("notifications-updated"));
          }}
        />
      )}
    </article>
  );
}

export function NotificationsList() {
  const router = useRouter();
  const [activeTab, setActiveTab] = useState<TabId>("all");
  const [items, setItems] = useState<Notification[] | null>(null);
  const [loggedIn, setLoggedIn] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      const res = await fetch("/api/notifications/me", { cache: "no-store" });
      if (!res.ok) {
        setError(`Gagal load (HTTP ${res.status})`);
        return;
      }
      const data = (await res.json()) as FetchResponse;
      if (!data.ok) {
        setError(data.error ?? "Gagal load");
        return;
      }
      setError(null);
      setItems(data.items);
      setLoggedIn(data.loggedIn);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Network error");
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const filteredItems = useMemo(() => {
    if (!items) return null;
    if (activeTab === "all") return items;
    return items.filter((item) => notificationType(item) === activeTab);
  }, [activeTab, items]);

  async function handleRead(notif: Notification) {
    if (!loggedIn || notif.read) return;
    setItems((prev) =>
      prev ? prev.map((item) => (item.id === notif.id ? { ...item, read: true } : item)) : prev,
    );
    window.dispatchEvent(new CustomEvent("notification-read", { detail: { id: notif.id } }));
    void fetch(`/api/notifications/${notif.id}/read`, { method: "POST" }).catch(() => {});
  }

  function handleBack() {
    if (window.history.length > 1) {
      router.back();
      return;
    }
    router.push("/");
  }

  return (
    <div className="mx-auto min-h-screen w-full max-w-2xl bg-slate-50">
      <header className="sticky top-0 z-40 border-b border-slate-200 bg-white/95 px-4 pb-4 pt-[calc(0.75rem+env(safe-area-inset-top))] backdrop-blur">
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={handleBack}
            className="-ml-1 flex h-10 w-10 shrink-0 items-center justify-center rounded-full text-slate-800 transition active:bg-slate-100"
            aria-label="Kembali"
          >
            <IoArrowBack className="h-5 w-5" aria-hidden="true" />
          </button>
          <div className="min-w-0">
            <h1 className="text-xl font-black leading-tight text-slate-950">Notifikasi</h1>
            <p className="mt-1 text-sm leading-snug text-slate-500">
              Update pesanan, promo, dan pengumuman dari Natalo Petshop.
            </p>
          </div>
        </div>

        <nav className="mt-4 flex gap-6 overflow-x-auto border-b border-slate-100" aria-label="Kategori notifikasi">
          {TABS.map((tab) => {
            const active = activeTab === tab.id;
            return (
              <button
                key={tab.id}
                type="button"
                onClick={() => setActiveTab(tab.id)}
                className={`relative shrink-0 pb-3 text-sm font-extrabold transition ${
                  active ? "text-blue-600" : "text-slate-400"
                }`}
                aria-current={active ? "page" : undefined}
              >
                {tab.label}
                {active && <span className="absolute inset-x-0 -bottom-px h-1 rounded-full bg-blue-600" aria-hidden="true" />}
              </button>
            );
          })}
        </nav>
      </header>

      <section className="px-4 py-4">
        {error && (
          <div className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm font-semibold text-red-700">
            {error}
          </div>
        )}

        {!error && filteredItems === null && (
          <div className="space-y-3">
            {[1, 2, 3].map((i) => (
              <div key={i} className="h-32 animate-pulse rounded-2xl bg-white shadow-sm" />
            ))}
          </div>
        )}

        {!error && filteredItems?.length === 0 && <EmptyState tab={activeTab} />}

        {!error && filteredItems && filteredItems.length > 0 && (
          <ul className="nat-content-fade-in nat-content-fade-in--stagger space-y-3">
            {filteredItems.map((item) => (
              <li key={item.id}>
                <NotificationCard item={item} onRead={handleRead} onRefresh={() => void load()} />
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
