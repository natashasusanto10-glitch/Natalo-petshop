"use client";

import Image from "next/image";
import { useMemo, useState } from "react";
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
  const [tab, setTab] = useState<"deskripsi" | "rekomendasi">("deskripsi");
  const [expanded, setExpanded] = useState(false);
  const summary = useMemo(() => stripMarkdown(description), [description]);
  const isLong = summary.length > 280;

  return (
    <div className="bg-white">
      {/* Tab strip */}
      <div className="relative flex border-b border-gray-100">
        <TabButton
          label="Deskripsi"
          active={tab === "deskripsi"}
          onClick={() => setTab("deskripsi")}
        />
        <TabButton
          label="Rekomendasi"
          active={tab === "rekomendasi"}
          onClick={() => setTab("rekomendasi")}
        />
      </div>

      <div className="px-4 py-4 md:px-6 md:py-6">
        {tab === "deskripsi" ? (
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
        ) : (
          <RelatedGrid related={related} />
        )}
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
      className={`relative flex-1 py-3 text-sm font-extrabold transition ${
        active ? "text-natalo-600" : "text-gray-400"
      }`}
      aria-pressed={active}
    >
      {label}
      <span
        aria-hidden
        className={`absolute inset-x-6 -bottom-px h-[3px] rounded-full transition-all ${
          active ? "bg-natalo-600" : "bg-transparent"
        }`}
      />
    </button>
  );
}
