import type { Metadata } from "next";
import Link from "next/link";
import { getSession } from "@/lib/auth";
import { formatRupiah } from "@/lib/format";
import { buildOrderDetailPath } from "@/lib/order-detail";
import { prisma } from "@/lib/prisma";
import { PageStatusBar } from "@/components/PageStatusBar";
import { OrderCreatedSuccessLottie } from "@/components/OrderCreatedSuccessLottie";

export const metadata: Metadata = {
  title: "Pesanan Telah Dibuat",
  description: "Konfirmasi pesanan berhasil dibuat di Natalo Petshop.",
  robots: { index: false, follow: false },
};

type Props = {
  params: Promise<{ orderNumber: string }>;
  searchParams: Promise<{ token?: string }>;
};

export default async function OrderCreatedSuccessPage({
  params,
  searchParams,
}: Props) {
  const [{ orderNumber }, query, session] = await Promise.all([
    params,
    searchParams,
    getSession("CUSTOMER"),
  ]);

  const order = await prisma.order.findUnique({
    where: { orderNumber: decodeURIComponent(orderNumber) },
    select: {
      orderNumber: true,
      userId: true,
      trackingToken: true,
      createdAt: true,
      total: true,
      paymentProvider: true,
    },
  });

  if (!order) {
    return (
      <div className="mx-auto max-w-xl px-4 py-16 text-center">
        <h1 className="text-2xl font-black text-gray-950">
          Pesanan tidak ditemukan
        </h1>
        <p className="mt-2 text-sm text-gray-600">
          Periksa kembali nomor pesanan atau gunakan fitur cek status pesanan.
        </p>
        <Link
          href="/order-status"
          className="mt-5 inline-flex rounded-full bg-blue-600 px-5 py-3 text-sm font-bold text-white"
        >
          Cek Status Pesanan
        </Link>
      </div>
    );
  }

  const isOwner = Boolean(session?.sub && order.userId === session.sub);
  const hasValidToken = Boolean(
    query.token && order.trackingToken && query.token === order.trackingToken
  );

  if (!isOwner && !hasValidToken) {
    return (
      <div className="mx-auto max-w-xl px-4 py-16 text-center">
        <h1 className="text-2xl font-black text-gray-950">
          Link pesanan perlu diverifikasi
        </h1>
        <p className="mt-2 text-sm text-gray-600">
          Untuk keamanan, pesanan guest hanya bisa dibuka lewat link tracking
          atau validasi nomor pesanan dengan email/nomor HP.
        </p>
        <div className="mt-5 flex flex-col justify-center gap-3 sm:flex-row">
          <Link
            href="/member/login"
            className="rounded-full border border-gray-200 px-5 py-3 text-sm font-bold text-gray-700"
          >
            Masuk Member
          </Link>
          <Link
            href={`/order-status?order=${encodeURIComponent(
              order.orderNumber
            )}`}
            className="rounded-full bg-blue-600 px-5 py-3 text-sm font-bold text-white"
          >
            Cek Status Pesanan
          </Link>
        </div>
      </div>
    );
  }

  const tanggal = new Date(order.createdAt).toLocaleString("id-ID", {
    day: "numeric",
    month: "long",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
  const paymentLabel =
    order.paymentProvider === "MANUAL" ? "Transfer Manual" : order.paymentProvider;
  const detailUrl = buildOrderDetailPath(
    order.orderNumber,
    hasValidToken ? query.token : null
  );

  return (
    <div className="min-h-dvh bg-gray-50 [padding-bottom:calc(1.25rem+env(safe-area-inset-bottom))] [padding-top:env(safe-area-inset-top)]">
      <PageStatusBar iconColor="dark" themeColor="#f8fafc" />
      <main className="mx-auto flex min-h-dvh max-w-2xl flex-col justify-center px-4 py-8">
        <section className="rounded-[2rem] border border-blue-100 bg-white p-5 text-center shadow-[0_18px_50px_rgba(21,101,216,0.10)] md:p-7">
          <OrderCreatedSuccessLottie />
          <h1 className="mt-2 text-2xl font-black tracking-tight text-gray-950 md:text-3xl">
            Pesanan telah dibuat!
          </h1>
          <p className="mx-auto mt-2 max-w-md text-sm font-semibold leading-6 text-gray-600">
            Terima kasih, pesananmu sedang kami proses.
          </p>

          <div className="mx-auto mt-5 max-w-xl rounded-3xl border border-blue-100 bg-blue-50/60 p-4 text-left text-sm">
            <div className="grid gap-3 sm:grid-cols-2">
              <div>
                <p className="text-xs font-bold uppercase tracking-widest text-blue-500">
                  No. Pesanan
                </p>
                <p className="mt-1 font-black text-gray-950">
                  {order.orderNumber}
                </p>
              </div>
              <div>
                <p className="text-xs font-bold uppercase tracking-widest text-blue-500">
                  Tanggal
                </p>
                <p className="mt-1 font-black text-gray-950">{tanggal}</p>
              </div>
              <div>
                <p className="text-xs font-bold uppercase tracking-widest text-blue-500">
                  Metode Pembayaran
                </p>
                <p className="mt-1 font-black text-gray-950">{paymentLabel}</p>
              </div>
              <div>
                <p className="text-xs font-bold uppercase tracking-widest text-blue-500">
                  Total Pembayaran
                </p>
                <p className="mt-1 font-black text-gray-950">
                  {formatRupiah(order.total)}
                </p>
              </div>
            </div>
          </div>

          <div className="mt-5 grid gap-3 sm:grid-cols-2">
            <Link
              href={detailUrl}
              className="rounded-full bg-blue-600 px-5 py-3 text-sm font-black text-white shadow-sm hover:bg-blue-700"
            >
              Lihat Detail Pesanan
            </Link>
            <Link
              href="/"
              className="rounded-full border border-blue-200 bg-white px-5 py-3 text-sm font-black text-blue-700 hover:bg-blue-50"
            >
              Kembali ke Beranda
            </Link>
          </div>
        </section>
      </main>
    </div>
  );
}
