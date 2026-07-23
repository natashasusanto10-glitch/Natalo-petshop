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
  const renderedAuthorImageUrl = input.renderedAuthorImageUrl === undefined
    ? card.authorImageUrl
    : input.renderedAuthorImageUrl;

  return (
    <div
      style={{
        background: "#0F2F63",
        color: "#FFFFFF",
        display: "flex",
        fontFamily: "Arial, sans-serif",
        height: "100%",
        padding: 48,
        width: "100%",
      }}
    >
      <div
        style={{
          alignItems: "center",
          background: "#E9F2FF",
          borderRadius: 24,
          display: "flex",
          flex: 6,
          justifyContent: "center",
          overflow: "hidden",
          position: "relative",
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
          <div style={{ color: "#1E5FBF", display: "flex", fontSize: 124, fontWeight: 800 }}>
            N
          </div>
        )}
        {card.showPlayBadge ? (
          <div
            style={{
              alignItems: "center",
              background: "rgba(15, 23, 42, 0.72)",
              borderRadius: 999,
              display: "flex",
              fontSize: 48,
              height: 112,
              justifyContent: "center",
              left: "50%",
              position: "absolute",
              top: "50%",
              transform: "translate(-50%, -50%)",
              width: 112,
            }}
          >
            ▶
          </div>
        ) : null}
        {card.durationLabel || card.carouselLabel ? (
          <div
            style={{
              background: "rgba(15, 23, 42, 0.78)",
              borderRadius: 12,
              bottom: 24,
              display: "flex",
              fontSize: 26,
              fontWeight: 700,
              padding: "10px 16px",
              position: "absolute",
              right: 24,
            }}
          >
            {card.durationLabel ?? card.carouselLabel}
          </div>
        ) : null}
      </div>
      <div
        style={{
          display: "flex",
          flex: 4,
          flexDirection: "column",
          justifyContent: "space-between",
          padding: "18px 12px 18px 44px",
        }}
      >
        <div style={{ alignItems: "center", display: "flex", gap: 16 }}>
          {renderedAuthorImageUrl ? (
            <img
              alt=""
              height={64}
              src={renderedAuthorImageUrl}
              style={{ borderRadius: 32, height: 64, objectFit: "cover", width: 64 }}
              width={64}
            />
          ) : (
            <div
              style={{
                alignItems: "center",
                background: "#1E7BFF",
                borderRadius: 32,
                display: "flex",
                fontSize: 30,
                fontWeight: 800,
                height: 64,
                justifyContent: "center",
                width: 64,
              }}
            >
              N
            </div>
          )}
          <div style={{ display: "flex", flexDirection: "column" }}>
            <div style={{ fontSize: 28, fontWeight: 700 }}>{card.authorLabel}</div>
            {card.isOfficial ? <div style={{ color: "#F6C650", fontSize: 20 }}>AKUN RESMI</div> : null}
          </div>
        </div>
        <div
          style={{
            display: "-webkit-box",
            fontSize: 38,
            fontWeight: 700,
            lineHeight: 1.22,
            overflow: "hidden",
            WebkitBoxOrient: "vertical",
            WebkitLineClamp: 3,
          }}
        >
          {card.description}
        </div>
        <div style={{ color: "#B9D4FF", display: "flex", fontSize: 22, fontWeight: 700 }}>
          natalopetshop.com
        </div>
      </div>
    </div>
  );
}
