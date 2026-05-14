import type { Metadata } from "next";
import Link from "next/link";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { orderDetailInclude, serializeOrderDetail } from "@/lib/order-detail";
import { OrderDetailView } from "@/components/OrderDetailView";

export const metadata: Metadata = {
  title: "Detail Pesanan",
  description:
    "Lihat detail pembayaran, pengiriman, dan status pesanan Natalo Petshop.",
  robots: { index: false, follow: false },
};

type Props = {
  params: Promise<{ orderNumber: string }>;
  searchParams: Promise<{ token?: string; created?: string }>;
};

export default async function OrderDetailPage({ params, searchParams }: Props) {
  const [{ orderNumber }, query, session] = await Promise.all([
    params,
    searchParams,
    getSession("CUSTOMER"),
  ]);

  const order = await prisma.order.findUnique({
    where: { orderNumber: decodeURIComponent(orderNumber) },
    include: orderDetailInclude,
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

  return (
    <OrderDetailView
      initialOrder={serializeOrderDetail(order)}
      token={query.token ?? null}
      canReview={isOwner}
      showCreatedSuccess={query.created === "1"}
    />
  );
}
