import type { Metadata } from "next";
import { Suspense } from "react";
import { PageStatusBar } from "@/components/PageStatusBar";
import { FeedClient } from "@/components/feed/FeedClient";

export const metadata: Metadata = {
  title: "Feed",
  description:
    "Feed Natalo Petshop — video produk, promo, edukasi pet care, dan konten komunitas pet lover.",
  alternates: { canonical: "/feed" },
};

// Catatan: page ini sengaja simple — semua fetching + state ada di FeedClient
// supaya tab switch instant tanpa SSR roundtrip. Feed items cuma update saat
// ada admin posting / promo baru, jadi tidak butuh SSR caching layer.
//
// FeedClient pakai useSearchParams() (untuk Shop the Look ?product=<slug>
// filter). Next.js App Router butuh useSearchParams di-wrap dalam Suspense
// boundary saat prerendering — fallback bisa null karena entire FeedClient
// di-load client-side anyway.
export default function FeedPage() {
  return (
    <main className="h-[100dvh] overflow-hidden bg-black">
      <PageStatusBar
        iconColor="light"
        themeColor="#000000"
        nativeBackgroundColor="#00000000"
        overlaysWebView
      />
      {/* h1 sr-only — feed immersive tanpa heading terlihat; screen reader
          & crawler tetap dapat konteks halaman. */}
      <h1 className="sr-only">Feed Natalo Petshop</h1>
      <Suspense fallback={null}>
        <FeedClient />
      </Suspense>
    </main>
  );
}
