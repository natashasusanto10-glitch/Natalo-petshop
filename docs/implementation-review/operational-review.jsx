import { CategoriesView } from "../../components/admin/views/CategoriesView";
import { StockView } from "../../components/admin/views/StockView";
import React from "react";
import { DashboardView } from "../../components/admin/views/DashboardView";
import { OrdersView } from "../../components/admin/views/OrdersView";
import { CustomersView } from "../../components/admin/views/CustomersView";
import { ReportsView } from "../../components/admin/views/ReportsView";
import { SettingsView } from "../../components/admin/views/SettingsView";
import { PromotionsView } from "../../components/admin/views/PromotionsView";
import { BannerManagerClient } from "../../components/admin/BannerManagerClient";
import { LaunchPopupManagerClient } from "../../components/admin/LaunchPopupManagerClient";
import { AdminFeedClient } from "../../components/admin/feed/AdminFeedClient";
import { AdminFeedCreateClient } from "../../components/admin/feed/AdminFeedCreateClient";
import { AdminEditFeedPostClient } from "../../components/admin/feed/AdminEditFeedPostClient";
import { AdminReportsClient } from "../../components/admin/feed/AdminReportsClient";
import { PromoTokoForm } from "../../components/admin/PromoTokoForm";
import { FlashSaleNewForm } from "../../components/admin/FlashSaleNewForm";
import { BroadcastForm } from "../../app/admin/(protected)/broadcast/BroadcastForm";
import {
  AdminPage,
  PageHeader,
  Button,
  EmptyState,
} from "../../components/admin/ui";
const now = new Date("2026-10-04T10:00:00+07:00");
const img = `data:image/svg+xml,${encodeURIComponent(
  '<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="560"><rect width="1280" height="560" fill="#e8efff"/><circle cx="1060" cy="200" r="200" fill="#d2e0ff"/><text x="70" y="245" font-family="Arial" font-size="64" font-weight="bold" fill="#234b90">Natalo Petshop</text><text x="70" y="320" font-family="Arial" font-size="35" fill="#4c648e">Kebutuhan hewan kesayangan</text></svg>'
)}`;
const opts = [
  { slug: "makanan-kucing", name: "Makanan Kucing" },
  { slug: "kandang", name: "Kandang & Carrier" },
  { slug: "obat-suplemen", name: "Obat & Suplemen" },
];
const product = {
  id: "review-single",
  slug: "tisu-basah",
  name: "Tisu Basah Hewan Isi 80 Lembar",
  price: 12100,
  stock: 200,
  imageUrl: img,
  hasVariants: false,
  variants: [],
};
const orders = [
  "PENDING",
  "PAID",
  "PROCESSING",
  "READY_FOR_PICKUP",
  "SHIPPED",
  "DELIVERED",
].map((status, i) => ({
  id: `order-${i}`,
  orderNumber: `NTL-20261004-${String(i + 1).padStart(4, "0")}`,
  customerName: ["Dewi Lestari", "Andi Pratama", "Rina Wijaya"][i % 3],
  customerPhone: "081234567890",
  createdAt: now,
  total: 257500 + i * 12000,
  status,
  paymentStatus: i === 0 ? "PENDING" : "PAID",
  paymentProofStatus: i === 0 ? "PENDING_REVIEW" : "NOT_UPLOADED",
  orderType: i === 3 ? "SELF_PICKUP" : "DELIVERY",
  cancellationRequestStatus: null,
  items: [{ quantity: i + 1, product: { imageUrl: img } }],
}));
const customers = orders.slice(0, 3).map((o, i) => ({
  id: `customer-${i}`,
  name: o.customerName,
  email: `pelanggan${i + 1}@example.com`,
  phone: o.customerPhone,
  createdAt: now,
  _count: { orders: i * 3 + 1 },
}));
const stats = [
  {
    label: "Penjualan hari ini",
    value: "Rp 4.850.000",
    helper: "Pesanan lunas hari ini",
    href: "/admin/orders?pay=PAID",
    variant: "accent",
  },
  {
    label: "Order baru",
    value: 12,
    helper: "Belum diproses",
    href: "/admin/orders?status=PENDING",
    variant: "warning",
  },
  {
    label: "Menunggu pembayaran",
    value: 5,
    helper: "Belum lunas",
    href: "/admin/orders?pay=WAITING",
    variant: "warning",
  },
  {
    label: "Sudah dibayar",
    value: 8,
    helper: "Siap dikemas",
    href: "/admin/orders?status=PAID",
    variant: "success",
  },
  ...Array.from({ length: 8 }, (_, i) => ({
    label: [
      "Diproses",
      "Dikirim",
      "Selesai",
      "Stok menipis",
      "Produk habis",
      "Varian habis",
      "Voucher aktif",
      "Voucher segera berakhir",
    ][i],
    value: [7, 18, 126, 8, 2, 3, 6, 1][i],
    helper: "Ringkasan toko",
    href: i < 3 ? "/admin/orders" : "/admin/stock",
    variant: "default",
  })),
].map((s) => ({ ...s, iconPath: "M4 5h16v15H4zM8 9h8M8 13h5" }));
function frame(title, content) {
  return (
    <AdminPage maxWidth="lg" className="admin-operational-page">
      <PageHeader title={title} subtitle="Data contoh untuk review lokal" />
      <div className="mt-6">{content}</div>
    </AdminPage>
  );
}
export function operationalFixtureFetch(path, options) {
  const method = options.method || "GET";
  if (path.startsWith("/api/admin/feed/posts") && method === "GET")
    return Response.json({
      items: [
        {
          id: "post-demo",
          status: "ACTIVE",
          encodingStatus: "ready",
          kind: "PHOTO_CAROUSEL",
          tab: "FEED",
          title: "Tips memilih makanan kucing",
          description:
            "Sesuaikan kebutuhan nutrisi dengan usia dan aktivitas hewan.",
          videoUrl: null,
          thumbnailUrl: img,
          firstMediaUrl: img,
          mediaCount: 3,
          videoDurationSec: null,
          product: null,
          promo: null,
          likeCount: 12,
          commentCount: 2,
          viewCount: 180,
          author: { id: "demo", name: "Natalo Petshop", role: "ADMIN" },
          moderatedBy: null,
          moderatedAt: null,
          moderationNote: null,
          publishedAt: now.toISOString(),
          createdAt: now.toISOString(),
        },
      ],
      nextCursor: null,
      counts: { total: 1, deleted: 0, photo: 1, video: 0 },
    });
  if (path.startsWith("/api/admin/feed/reports") && method === "GET")
    return Response.json({
      reports: [],
      nextCursor: null,
      filter: "pending",
      counts: { pending: 0, resolved: 0, dismissed: 0 },
    });
  if (path.includes("eligible-products") && method === "GET") {
    if (location.search.includes("review-failure"))
      return Response.json(
        { error: "Simulasi gagal memuat produk" },
        { status: 503 }
      );
    const search =
      new URL(path, location.origin).searchParams.get("q")?.toLowerCase() || "";
    return Response.json({
      products: product.name.toLowerCase().includes(search) ? [product] : [],
    });
  }
  if (
    path.startsWith("/api/admin/banners") ||
    path.startsWith("/api/admin/launch-popup")
  ) {
    if (location.search.includes("review-failure"))
      return Response.json(
        { error: "Simulasi gagal jaringan. Coba kembali." },
        { status: 503 }
      );
    const body = options.body ? JSON.parse(options.body) : {};
    return Response.json({ ok: true, banner: body, popup: body });
  }
  return null;
}
export function operationalPage(path) {
  const query = new URLSearchParams(location.search);
  const emptyDashboard = query.has("review-empty");
  if (path === "/admin/dashboard")
    return (
      <DashboardView
        greeting="Selamat sore"
        adminName="Admin demo"
        now={now}
        paidUnshippedCount={emptyDashboard ? 0 : 8}
        stats={[
          {
            ...stats[0],
            value: "Rp 3.842.500",
            iconPath: "M3 3v18h18M7 15l4-4 3 3 5-5",
            href: "/admin/orders?date=TODAY&pay=PAID",
            helper: "dibanding total kemarin",
            trend: { value: -13.4 },
          },
          {
            ...stats[1],
            label: "Pesanan hari ini",
            iconPath:
              "M9 5H7a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2h-2M9 3h6v4H9z",
            href: "/admin/orders?date=TODAY",
            value: 28,
            helper: "Pesanan yang masuk hari ini (WIB)",
            variant: "default",
          },
          {
            ...stats[3],
            label: "Perlu dikemas",
            iconPath:
              "M3 7l9-4 9 4v10l-9 4-9-4V7Zm0 0 9 4 9-4M12 11v10M7 5l9 4",
            href: "/admin/orders?status=NEED_PACKING",
            value: 8,
            helper: "Pembayaran sudah terverifikasi",
            variant: "default",
          },
          {
            ...stats[7],
            label: "Stok menipis",
            iconPath: "M12 9v4M12 17h.01M3 12 12 3l9 9-9 9-9-9Z",
            href: "/admin/stock?filter=menipis",
            value: 12,
            helper: "Stok 1–5",
            variant: "default",
          },
          ...stats.slice(1, 7),
          ...stats.slice(8),
        ].map((stat) =>
          emptyDashboard
            ? {
                ...stat,
                trend: undefined,
                helper:
                  stat.label === "Penjualan hari ini"
                    ? "Pesanan lunas hari ini (WIB)"
                    : stat.helper,
                value: stat.label === "Penjualan hari ini" ? "Rp 0" : 0,
              }
            : stat
        )}
        verificationCount={emptyDashboard ? 0 : 3}
        pickupCount={emptyDashboard ? 0 : 6}
        revenue={
          emptyDashboard
            ? {
                daily: [
                  "28 Sep",
                  "29 Sep",
                  "30 Sep",
                  "1 Okt",
                  "2 Okt",
                  "3 Okt",
                  "4 Okt",
                ].map((label) => ({ label, total: 0 })),
                hourly: [{ label: "00.00", total: 0 }],
                todayTotal: 0,
                yesterdayTotal: 0,
                weekTotal: 0,
                previousWeekTotal: 0,
              }
            : {
                daily: [
                  2800000, 3400000, 3000000, 4100000, 3100000, 4437500, 3842500,
                ].map((total, index) => ({
                  label: [
                    "28 Sep",
                    "29 Sep",
                    "30 Sep",
                    "1 Okt",
                    "2 Okt",
                    "3 Okt",
                    "4 Okt",
                  ][index],
                  total,
                })),
                hourly: [
                  0, 0, 0, 0, 0, 0, 350000, 920000, 1580000, 2300000, 3842500,
                ].map((total, index) => ({
                  label: `${String(index).padStart(2, "0")}.00`,
                  total,
                })),
                todayTotal: 3842500,
                yesterdayTotal: 4437500,
                weekTotal: 24680000,
                previousWeekTotal: 22767528,
              }
        }
        actionOrders={emptyDashboard ? [] : orders}
        lowStockProducts={[
          { id: product.id, name: product.name, stock: 4, price: 12100 },
        ]}
        outOfStockProducts={[]}
        outOfStockVariants={[]}
        expiringVouchers={[
          {
            id: "voucher-demo",
            code: "NATALOHEMAT",
            expiresAt: new Date(now.getTime() + 86400000 * 3),
            usedCount: 12,
            maxUsage: 100,
          },
        ]}
      />
    );
  if (path === "/admin/orders") {
    const status = query.get("status") || "ALL",
      pay = query.get("pay") || "ALL",
      type = query.get("type") || "ALL",
      search = query.get("q") || "",
      proof = query.get("proof") === "PENDING_REVIEW",
      todayOnly = query.get("date") === "TODAY";
    const filtered = orders.filter(
      (o) =>
        (!proof || o.paymentProofStatus === "PENDING_REVIEW") &&
        (status === "ALL" ||
          (status === "NEED_PACKING"
            ? o.paymentStatus === "PAID" &&
              ["PENDING", "PAID", "PROCESSING"].includes(o.status)
            : o.status === status)) &&
        (pay === "ALL" ||
          (pay === "WAITING"
            ? ["PENDING", "UNPAID"].includes(o.paymentStatus)
            : o.paymentStatus === pay)) &&
        (type === "ALL" || o.orderType === type) &&
        (!search ||
          [o.customerName, o.orderNumber, o.customerPhone]
            .join(" ")
            .toLowerCase()
            .includes(search.toLowerCase()))
    );
    const buildUrl = (overrides) => {
      const values = {
        status,
        pay,
        type,
        q: search,
        date: todayOnly ? "TODAY" : "",
        proof:
          proof && !overrides.status && !overrides.pay && !overrides.type
            ? "PENDING_REVIEW"
            : "",
        ...overrides,
      };
      const sp = new URLSearchParams(
        Object.entries(values).filter(([, v]) => v && v !== "ALL")
      );
      return `/admin/orders?${sp}`;
    };
    return (
      <OrdersView
        workflowCounts={{ verification: 1, packing: 2, pickup: 1, total: 6 }}
        orders={filtered}
        pendingProofReview={proof}
        todayOnly={todayOnly}
        total={filtered.length}
        search={search}
        page={1}
        totalPages={1}
        tabs={[
          { key: "ALL", label: "Semua", count: 6 },
          { key: "NEED_PACKING", label: "Siap packing", count: 2 },
          ...orders.map((o) => ({
            key: o.status,
            label: {
              PENDING: "Order baru",
              PAID: "Sudah dibayar",
              PROCESSING: "Diproses",
              READY_FOR_PICKUP: "Siap diambil",
              SHIPPED: "Dikirim",
              DELIVERED: "Selesai",
            }[o.status],
            count: 1,
          })),
        ]}
        activeStatus={status}
        activePay={pay}
        activeType={type}
        buildUrl={buildUrl}
      />
    );
  }
  if (path === "/admin/stock") {
    const tab = query.get("tab") === "varian" ? "varian" : "produk",
      filter = ["habis", "menipis"].includes(query.get("filter"))
        ? query.get("filter")
        : "semua";
    const rows = [
      {
        id: product.id,
        name: product.name,
        stock: 4,
        category: { name: "Aksesoris & Perlengkapan" },
      },
      {
        id: "review-variant",
        name: "Snack Hewan Chicken & Beef",
        stock: 0,
        category: { name: "Makanan Anjing" },
      },
    ].filter(
      (p) =>
        filter === "semua" || (filter === "habis" ? p.stock === 0 : p.stock > 0)
    );
    const variants = rows.map((p) => ({
      id: p.id,
      sku: "SKU-001",
      stock: p.stock,
      product: { id: p.id, name: p.name },
      options: [{ option: { value: "Chicken" } }],
    }));
    return (
      <StockView
        productTotal={2}
        productLow={1}
        productOut={1}
        variantLow={1}
        variantOut={1}
        listedTotal={rows.length}
        tab={tab}
        filter={filter}
        page={1}
        totalPages={1}
        pageBeyondEnd={false}
        isEmpty={!rows.length}
        products={rows}
        variants={variants}
        buildUrl={(changes) =>
          `/admin/stock?${new URLSearchParams({ tab, filter, ...changes })}`
        }
      />
    );
  }
  if (path === "/admin/categories")
    return (
      <CategoriesView
        categories={opts.map((category, i) => ({
          ...category,
          id: `category-${i}`,
          _count: { products: 3 + i },
        }))}
        deleteCategory={async () => {
          throw new Error("Review lokal: hapus dinonaktifkan.");
        }}
      />
    );
  if (path === "/admin/customers") {
    const search = query.get("q") || "";
    const page = Math.max(1, Number(query.get("page")) || 1);
    const rows = customers.filter((customer) =>
      [customer.name, customer.email, customer.phone]
        .join(" ")
        .toLowerCase()
        .includes(search.toLowerCase())
    );
    return (
      <CustomersView
        customers={rows.slice((page - 1) * 2, page * 2)}
        total={rows.length}
        search={search}
        page={page}
        totalPages={Math.ceil(rows.length / 2)}
        pageHref={(nextPage) =>
          `/admin/customers?${new URLSearchParams({
            page: String(nextPage),
            ...(search ? { q: search } : {}),
          })}`
        }
      />
    );
  }
  if (path === "/admin/reports")
    return (
      <ReportsView
        monthName="Oktober 2026"
        thisMonthRevenue={18450000}
        lastMonthRevenue={15600000}
        revenueGrowth={18}
        ordersThisMonth={64}
        ordersLastMonth={53}
        topProducts={[
          { name: "Royal Canin Indoor Adult 2 kg", _sum: { quantity: 124 } },
          { name: product.name, _sum: { quantity: 96 } },
        ]}
        statusMap={{
          PENDING: 12,
          PAID: 8,
          PROCESSING: 7,
          READY_FOR_PICKUP: 4,
          SHIPPED: 18,
          DELIVERED: 126,
          CANCELLED: 3,
          REFUNDED: 1,
        }}
      />
    );
  if (path === "/admin/settings")
    return (
      <SettingsView
        brand="Natalo Petshop"
        siteUrl="https://natalopetshop.com"
      />
    );
  if (path === "/admin/diskon")
    return (
      <PromotionsView
        voucherActive={6}
        voucherTotal={18}
        promoTokoActive={3}
        promoTokoTotal={7}
        flashSaleActive={2}
        flashSaleTotal={5}
        performaPeriode={{
          start: new Date(now.getTime() - 86400000 * 7),
          end: now,
        }}
        performaMetrics={{
          current: {
            penjualan: 5480000,
            pesanan: 28,
            jumlahTerjual: 42,
            pembeli: 23,
          },
          previous: {
            penjualan: 4520000,
            pesanan: 22,
            jumlahTerjual: 31,
            pembeli: 19,
          },
          deltaPercent: {
            penjualan: 21,
            pesanan: 27,
            jumlahTerjual: 35,
            pembeli: 21,
          },
        }}
      />
    );
  if (path === "/admin/banners")
    return frame(
      "Banner beranda",
      <BannerManagerClient
        initialBanners={[1, 2].map((n) => ({
          id: `banner-${n}`,
          imageUrl: img,
          imageAlt: `Banner Natalo ${n}`,
          linkType: "category",
          linkValue: "makanan-kucing",
          isActive: true,
          position: n - 1,
        }))}
        categories={opts}
        brands={[]}
      />
    );
  if (path === "/admin/launch-popup")
    return frame(
      "Popup promo",
      <LaunchPopupManagerClient
        initialPopups={[
          {
            id: "popup-1",
            imageUrl: img,
            imageAlt: "Promo Natalo",
            linkType: "promo",
            linkValue: null,
            audience: "all",
            startsAt: null,
            endsAt: null,
            isActive: true,
          },
        ]}
        categories={opts}
        brands={[]}
      />
    );
  if (path === "/admin/broadcast")
    return frame("Broadcast notifikasi", <BroadcastForm />);
  if (path === "/admin/feed")
    return (
      <AdminPage maxWidth="lg" className="admin-operational-page">
        <AdminFeedClient />
      </AdminPage>
    );
  if (path === "/admin/feed/new")
    return (
      <AdminPage maxWidth="lg" className="admin-operational-page">
        <AdminFeedCreateClient />
      </AdminPage>
    );
  if (path === "/admin/feed/post-demo/edit")
    return frame(
      "Edit konten",
      <AdminEditFeedPostClient
        postId="post-demo"
        initialTitle="Tips memilih makanan kucing"
        initialDescription="Sesuaikan kebutuhan nutrisi."
        initialProducts={[]}
        thumbnailUrl={img}
        videoDurationSec={null}
        kind="VIDEO_ONLY"
        tab="FEED"
      />
    );
  if (path === "/admin/feed/reports")
    return (
      <AdminPage maxWidth="lg" className="admin-operational-page">
        <AdminReportsClient />
      </AdminPage>
    );
  if (path === "/admin/diskon/promo-toko/new") return <PromoTokoForm />;
  if (path === "/admin/diskon/flash-sale/new")
    return (
      <FlashSaleNewForm
        products={[product]}
        action={async () => {
          throw new Error("Review lokal: perubahan server dinonaktifkan.");
        }}
      />
    );
  if (!path.startsWith("/admin/products"))
    return frame(
      "Review halaman",
      <EmptyState
        title="Halaman ini belum tersedia dalam viewer lokal"
        description="Viewer hanya menampilkan halaman yang memiliki data contoh. Kode halaman asli tetap tersedia dalam aplikasi."
        action={{ label: "Kembali ke ringkasan", href: "/admin/dashboard" }}
      />
    );
  return null;
}
