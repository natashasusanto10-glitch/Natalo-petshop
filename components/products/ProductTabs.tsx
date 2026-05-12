"use client";

import Image from "next/image";
import { useEffect, useMemo, useState } from "react";
import { PrefetchOnView } from "@/components/PrefetchOnView";
import { IMAGE_BLUR_GRAY } from "@/lib/image-placeholder";

type RelatedProduct = {
  id: string;
  slug: string;
  name: string;
  price: number;
  discountPrice: number | null;
  imageUrl: string | null;
};

type Props = {
  description: string;
  related: RelatedProduct[];
};

function stripMarkdown(input: string) {
  return input
    .replace(/^#{1,6}\s+/gm, "")
    .replace(/\*\*(.*?)\*\*/g, "$1")
    .replace(/\*(.*?)\*/g, "$1")
    .replace(/^---+$/gm, "")
    .replace(/\s+/g, " ")
    .trim();
}

function renderInline(text: string) {
  const parts = text.split(/(\*\*.*?\*\*|\*.*?\*)/g).filter(Boolean);
  return parts.map((part, index) => {
    if (part.startsWith("**") && part.endsWith("**")) {
      return <strong key={index}>{part.slice(2, -2)}</strong>;
    }
    if (part.startsWith("*") && part.endsWith("*")) {
      return <em key={index}>{part.slice(1, -1)}</em>;
    }
    return <span key={index}>{part}</span>;
  });
}

function MarkdownBody({ body }: { body: string }) {
  const blocks = body
    .split(/\n{2,}/)
    .map((block) => block.trim())
    .filter(Boolean);

  return (
    <div className="space-y-3 text-sm leading-6 text-gray-700">
      {blocks.map((block, index) => {
        if (/^---+$/.test(block)) {
          return <hr key={index} className="border-gray-100" />;
        }
        if (/^#{1,6}\s+/.test(block)) {
          const text = block.replace(/^#{1,6}\s+/, "");
          return (
            <p key={index} className="mt-2 text-sm font-extrabold text-gray-900">
              {renderInline(text)}
            </p>
          );
        }
        const lines = block.split("\n").map((l) => l.trim()).filter(Boolean);
        if (lines.every((line) => line.startsWith("- "))) {
          return (
            <ul key={index} className="list-disc space-y-1 pl-5">
              {lines.map((line, lineIndex) => (
                <li key={lineIndex}>{renderInline(line.slice(2))}</li>
              ))}
            </ul>
          );
        }
        return <p key={index}>{renderInline(block)}</p>;
      })}
    </div>
  );
}

function formatRupiahShort(n: number) {
  return `Rp${new Intl.NumberFormat("id-ID").format(n)}`;
}

function RelatedGrid({ related }: { related: RelatedProduct[] }) {
  if (related.length === 0) {
    return (
      <p className="py-8 text-center text-sm text-gray-500">
        Belum ada rekomendasi untuk produk ini.
      </p>
    );
  }
  return (
    <div className="grid grid-cols-2 gap-3 md:grid-cols-3 md:gap-4">
      {related.map((p) => {
        const price = p.discountPrice && p.discountPrice < p.price ? p.discountPrice : p.price;
        return (
          <PrefetchOnView
            key={p.id}
            href={`/products/${p.slug}`}
            className="group flex flex-col overflow-hidden rounded-xl border border-gray-100 bg-white transition-transform duration-100 active:scale-95 active:bg-gray-50"
          >
            <div className="relative aspect-square w-full bg-gray-100">
              {p.imageUrl ? (
                <Image
                  src={p.imageUrl}
                  alt={p.name}
                  fill
                  sizes="(min-width: 768px) 33vw, 50vw"
                  placeholder="blur"
                  blurDataURL={IMAGE_BLUR_GRAY}
                  className="object-cover"
                />
              ) : (
                <div className="flex h-full items-center justify-center text-2xl font-black text-gray-200">
                  NP
                </div>
              )}
            </div>
            <div className="flex flex-col gap-1 px-2.5 py-2">
              <p className="line-clamp-2 text-xs font-semibold leading-snug text-gray-900">
                {p.name}
              </p>
              <p className="text-sm font-black text-natalo-600">
                {formatRupiahShort(price)}
              </p>
            </div>
          </PrefetchOnView>
        );
      })}
    </div>
  );
}

export function ProductTabs({ description, related }: Props) {
  const [activeTab, setActiveTab] = useState<"deskripsi" | "rekomendasi">("deskripsi");
  const [expanded, setExpanded] = useState(false);
  const summary = useMemo(() => stripMarkdown(description), [description]);
  const isLong = summary.length > 280;

  function getStickyOffset() {
    const header = document.querySelector(".product-detail-header");
    const tabs = document.querySelector(".product-tabs");
    const headerHeight = header?.getBoundingClientRect().height ?? 56;
    const tabsHeight = tabs?.getBoundingClientRect().height ?? 48;
    return headerHeight + tabsHeight;
  }

  function scrollToSection(sectionId: "deskripsi" | "rekomendasi") {
    const target = document.getElementById(`product-section-${sectionId}`);
    if (!target) return;

    setActiveTab(sectionId);
    const top = target.getBoundingClientRect().top + window.scrollY - getStickyOffset();
    window.scrollTo({ top, behavior: "smooth" });
  }

  useEffect(() => {
    const descriptionSection = document.getElementById("product-section-deskripsi");
    const recommendationSection = document.getElementById("product-section-rekomendasi");
    if (!descriptionSection || !recommendationSection) return;
    let ticking = false;

    const updateActiveSection = () => {
      const offset = getStickyOffset() + 16;
      const recommendationTop = recommendationSection.getBoundingClientRect().top;
      setActiveTab(recommendationTop <= offset ? "rekomendasi" : "deskripsi");
    };

    const onScroll = () => {
      if (ticking) return;
      ticking = true;
      window.requestAnimationFrame(() => {
        updateActiveSection();
        ticking = false;
      });
    };

    const makeObserver = () => {
      const topOffset = getStickyOffset() + 8;
      const observer = new IntersectionObserver(
        (entries) => {
          const visible = entries
            .filter((entry) => entry.isIntersecting)
            .sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top);
          const current = visible[0]?.target.id;
          if (current === "product-section-rekomendasi") {
            setActiveTab("rekomendasi");
          } else if (current === "product-section-deskripsi") {
            setActiveTab("deskripsi");
          }
          updateActiveSection();
        },
        {
          root: null,
          rootMargin: `-${topOffset}px 0px -55% 0px`,
          threshold: [0.01, 0.2, 0.5],
        },
      );

      observer.observe(descriptionSection);
      observer.observe(recommendationSection);
      return observer;
    };

    let observer = makeObserver();
    const refreshObserver = () => {
      observer.disconnect();
      observer = makeObserver();
      updateActiveSection();
    };
    updateActiveSection();
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", refreshObserver);
    return () => {
      observer.disconnect();
      window.removeEventListener("scroll", onScroll);
      window.removeEventListener("resize", refreshObserver);
    };
  }, []);

  return (
    <div className="bg-white">
      {/* Tab strip */}
      <div className="product-tabs">
        <div className="product-tabs-inner">
        <TabButton
          label="Deskripsi"
          active={activeTab === "deskripsi"}
          onClick={() => scrollToSection("deskripsi")}
        />
        <TabButton
          label="Rekomendasi"
          active={activeTab === "rekomendasi"}
          onClick={() => scrollToSection("rekomendasi")}
        />
        </div>
      </div>

      <div className="px-4 py-4 md:px-6 md:py-6">
        <section id="product-section-deskripsi" className="product-tab-section">
          <>
            {expanded || !isLong ? (
              <MarkdownBody body={description} />
            ) : (
              <p className="text-sm leading-6 text-gray-700">
                {summary.slice(0, 260).trim()}
                <span className="text-gray-400">…</span>
              </p>
            )}
            {isLong && (
              <button
                type="button"
                onClick={() => setExpanded((v) => !v)}
                className="mt-3 text-sm font-extrabold text-natalo-600 active:opacity-70"
              >
                {expanded ? "Tutup" : "Baca Selengkapnya"}
              </button>
            )}
          </>
        </section>

        <section id="product-section-rekomendasi" className="product-tab-section mt-8 border-t border-gray-100 pt-5 md:mt-10 md:pt-6">
          <h2 className="mb-3 text-base font-black text-gray-900 md:text-lg">
            Rekomendasi Produk
          </h2>
          <RelatedGrid related={related} />
        </section>
      </div>
    </div>
  );
}

function TabButton({
  label,
  active,
  onClick,
}: {
  label: string;
  active: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`product-tab ${active ? "active" : ""}`}
      aria-current={active ? "true" : undefined}
    >
      {label}
    </button>
  );
}
