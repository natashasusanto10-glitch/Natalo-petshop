/**
 * GET /api/banners
 *
 * Return hero banner slides untuk Home screen Flutter / mobile app.
 * Source: data/heroSlides.ts (sama dengan yang dipakai PWA HeroBanner).
 *
 * Filter activeFrom/activeUntil di server supaya client (Flutter) tidak
 * perlu compute time window — kirim aja yang relevan sekarang.
 *
 * Image URL relatif (/banners/*.jpg) — Flutter resolve via baseUrl PWA.
 */
import { NextResponse } from "next/server";
import { heroSlides } from "@/data/heroSlides";
import { filterActiveSlides } from "@/lib/filterActiveSlides";

export const revalidate = 300;

export async function GET() {
  const active = filterActiveSlides(heroSlides);

  // Normalize: hanya kirim field yg Flutter perlu (image, href, alt).
  // Hide field internal seperti icon/cta object yg cuma web pakai.
  const banners = active.map((slide) => {
    if (slide.type === "image") {
      return {
        id: slide.id,
        image: slide.image,
        imageAlt: slide.imageAlt,
        href: slide.href ?? null,
      };
    }
    // Content slide → render sebagai content card di mobile (rare).
    return {
      id: slide.id,
      type: "content" as const,
      badge: slide.badge,
      headline: [
        slide.headlineBefore,
        slide.headlineHighlight,
        slide.headlineAfter,
      ]
        .filter(Boolean)
        .join(" "),
      subtitle: slide.subtitle,
      ctaText: slide.cta.text,
      href: slide.cta.href,
    };
  });

  return NextResponse.json(
    { banners },
    {
      headers: {
        "Cache-Control": "public, s-maxage=300, stale-while-revalidate=3600",
      },
    },
  );
}
