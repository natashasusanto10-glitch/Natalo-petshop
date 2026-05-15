import type { Metadata } from "next";
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
    <main className="h-[100dvh] -mb-[calc(var(--natalo-bottom-nav-height)+env(safe-area-inset-bottom))] overflow-hidden bg-black">
      <FeedClient />
    </main>
  );
}
