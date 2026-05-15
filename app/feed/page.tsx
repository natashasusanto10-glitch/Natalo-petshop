import type { Metadata } from "next";
import { PageStatusBar } from "@/components/PageStatusBar";
import { FeedClient } from "@/components/feed/FeedClient";

export const metadata: Metadata = {
  title: "Feed",
  description:
    "Feed Natalo Petshop — video produk, promo, edukasi pet care, dan konten komunitas pet lover.",
};

// Catatan: page ini sengaja simple — semua fetching + state ada di FeedClient
// supaya tab switch instant tanpa SSR roundtrip. Feed items cuma update saat
// ada admin posting / promo baru, jadi tidak butuh SSR caching layer.
export default function FeedPage() {
  return (
    <main className="h-[100dvh] overflow-hidden bg-black">
      <PageStatusBar
        iconColor="light"
        themeColor="#000000"
        nativeBackgroundColor="#00000000"
        overlaysWebView
      />
      <FeedClient />
    </main>
  );
}
