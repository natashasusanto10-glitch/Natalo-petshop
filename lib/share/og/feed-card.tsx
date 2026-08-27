import type { PublicShareFeedPost } from "@/lib/share/feed-share-data";
import { safeOgImageUrl } from "../og-image-security";

const FALLBACK_DESCRIPTION = "Lihat postingan terbaru di Natalo.";

export type FeedShareCardInput = Omit<PublicShareFeedPost, "durationSec" | "mediaCount"> & {
  durationSec?: number | null;
  mediaCount?: number;
  renderedAuthorImageUrl?: string | null;
  renderedMediaUrl?: string | null;
};

export type FeedShareCardModel = {
  authorLabel: string;
  authorImageUrl: string | null;
  carouselLabel: string | null;
  description: string;
  durationLabel: string | null;
  isOfficial: boolean;
  mediaUrl: string | null;
  showPlayBadge: boolean;
};

function cleanText(value: string | null | undefined, maxLength: number) {
  const clean = (value ?? "")
    .replace(/[\u0000-\u001F\u007F]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  return clean.length > maxLength ? `${clean.slice(0, maxLength - 1).trimEnd()}…` : clean;
}

function isVideoKind(kind: string) {
  return kind === "VIDEO_ONLY" || kind === "VIDEO_PRODUCT" || kind === "COMMUNITY";
}

function formatDuration(durationSec: number | null | undefined) {
  if (!durationSec || durationSec < 0) return null;
  const totalSeconds = Math.round(durationSec);
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = String(totalSeconds % 60).padStart(2, "0");
  return `${minutes}:${seconds}`;
}

export function buildFeedShareCardModel(input: FeedShareCardInput): FeedShareCardModel {
  const isVideo = isVideoKind(input.kind);
  const mediaCount = input.mediaCount ?? 1;
  return {
    authorLabel: cleanText(input.author.displayName, 72) || "Natalo Petshop",
    authorImageUrl: safeOgImageUrl(input.author.photoUrl),
    carouselLabel: input.kind === "PHOTO_CAROUSEL" && mediaCount > 1 ? `1/${mediaCount}` : null,
    description: cleanText(input.description, 140) || FALLBACK_DESCRIPTION,
    durationLabel: isVideo ? formatDuration(input.durationSec) : null,
    isOfficial: input.author.isOfficial,
    mediaUrl: safeOgImageUrl(input.posterUrl),
    showPlayBadge: isVideo,
  };
}

export function renderFeedShareCard(input: FeedShareCardInput) {
  const card = buildFeedShareCardModel(input);
  // `null` is intentional: the route already tried a bounded fetch and must
  // render local fallback rather than allowing ImageResponse to fetch again.
  const renderedMediaUrl = input.renderedMediaUrl === undefined
    ? card.mediaUrl
    : input.renderedMediaUrl;

  // Full-bleed, seperti kartu produk (lihat commit f11770a6): thumbnail
  // memenuhi seluruh kanvas persegi. Panel biru + nama akun + caption yang
  // dulu digambar DI DALAM gambar dihapus — thumbnail video 9:16 di kanvas
  // 1200x630 cuma kebagian ~35% lebar kartu dan tampil kecil di chat.
  // Caption kini dibawa metadata halaman (judul link, di bawah gambar) —
  // digambar juga di sini berarti teks yang sama tampil dua kali.
  //
  // objectFit COVER, beda dengan kartu produk yang contain: thumbnail feed
  // adalah frame video 9:16 tanpa teks/badge template di tepinya, jadi
  // crop atas-bawah aman; contain justru menghadirkan dua bidang kosong
  // lebar di kiri-kanan — masalah yang mau dihilangkan.
  return (
    <div
      style={{
        background: "#0F2F63",
        color: "#FFFFFF",
        display: "flex",
        fontFamily: "Arial, sans-serif",
        height: "100%",
        position: "relative",
        width: "100%",
      }}
    >
      {renderedMediaUrl ? (
        <img
          alt=""
          height="100%"
          src={renderedMediaUrl}
          style={{ height: "100%", objectFit: "cover", width: "100%" }}
          width="100%"
        />
      ) : (
        // Fallback tanpa media: monogram di bidang biru penuh — kartu
        // tidak boleh kosong saat poster gagal diambil.
        <div
          style={{
            alignItems: "center",
            background: "#E9F2FF",
            color: "#1E5FBF",
            display: "flex",
            fontSize: 280,
            fontWeight: 800,
            height: "100%",
            justifyContent: "center",
            width: "100%",
          }}
        >
          N
        </div>
      )}
      {/* Badge hanya kalau ada thumbnail. Di layout full-bleed, fallback
          monogram memakai seluruh kanvas — badge ▶ akan mendarat tepat di
          atas huruf "N" dan terlihat seperti kartu rusak (terbukti saat
          render lokal). Tanpa media, tidak ada apa pun untuk "diputar". */}
      {card.showPlayBadge && renderedMediaUrl ? (
        <div
          style={{
            alignItems: "center",
            background: "rgba(15, 23, 42, 0.72)",
            borderRadius: 999,
            display: "flex",
            fontSize: 64,
            height: 160,
            justifyContent: "center",
            left: "50%",
            position: "absolute",
            top: "50%",
            transform: "translate(-50%, -50%)",
            width: 160,
          }}
        >
          ▶
        </div>
      ) : null}
      {(card.durationLabel || card.carouselLabel) && renderedMediaUrl ? (
        <div
          style={{
            background: "rgba(15, 23, 42, 0.78)",
            borderRadius: 16,
            bottom: 40,
            display: "flex",
            fontSize: 36,
            fontWeight: 700,
            padding: "12px 22px",
            position: "absolute",
            right: 40,
          }}
        >
          {card.durationLabel ?? card.carouselLabel}
        </div>
      ) : null}
    </div>
  );
}
