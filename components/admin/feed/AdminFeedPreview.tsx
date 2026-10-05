"use client";

import Image from "next/image";
import { useEffect, useRef, useState } from "react";
import {
  FiCheck,
  FiHeart,
  FiMessageCircle,
  FiPackage,
  FiShare2,
  FiShoppingBag,
  FiPlay,
} from "react-icons/fi";
import { AdminDialog } from "@/components/admin/ui/AdminDialog";
import { formatRupiah } from "@/lib/format";

export type FeedPreviewProduct = {
  id: string;
  name: string;
  imageUrl?: string | null;
  price?: number;
  promoPrice?: number | null;
};
export function AdminFeedPreview({
  title,
  description,
  thumbnailUrl,
  videoUrl,
  products = [],
  author = "Natalo Petshop",
  official = true,
  likeCount = 0,
  commentCount = 0,
}: {
  title: string;
  description: string | null;
  thumbnailUrl: string | null;
  videoUrl?: string | null;
  products?: FeedPreviewProduct[];
  author?: string;
  official?: boolean;
  likeCount?: number;
  commentCount?: number;
}) {
  const [productsOpen, setProductsOpen] = useState(false);
  return (
    <>
      <div className="af-phone">
        <div className="af-phone-top">
          <strong>Feed</strong>
          <span>Natalo</span>
        </div>
        <div className="af-preview-screen">
          {videoUrl ? (
            <PreviewVideo
              source={videoUrl}
              poster={thumbnailUrl}
              title={title}
            />
          ) : thumbnailUrl ? (
            <Image
              src={thumbnailUrl}
              alt={`Sampul ${title || "postingan"}`}
              fill
              sizes="300px"
              className="object-cover"
              unoptimized={thumbnailUrl.startsWith("blob:")}
            />
          ) : (
            <div className="af-preview-placeholder">
              <FiPackage />
              <span>Media postingan</span>
            </div>
          )}
          <div className="af-social" aria-label="Ringkasan interaksi">
            <span>
              <FiHeart aria-hidden />
              {likeCount.toLocaleString("id-ID")}
            </span>
            <span>
              <FiMessageCircle aria-hidden />
              {commentCount.toLocaleString("id-ID")}
            </span>
            <span>
              <FiShare2 aria-hidden />
              Bagikan
            </span>
          </div>
          <div className="af-preview-caption">
            {products.length > 0 && (
              <button
                type="button"
                className="af-product-pill"
                onClick={() => setProductsOpen(true)}
              >
                <FiShoppingBag aria-hidden />
                <span>{products.length} produk terkait</span>
                <span aria-hidden>›</span>
              </button>
            )}
            <div className="af-preview-author">
              <span className="af-avatar">{author.slice(0, 1)}</span>
              <strong>{author}</strong>
              {official && (
                <span className="af-official">
                  <FiCheck aria-hidden />
                  Official
                </span>
              )}
            </div>
            <p>{description?.trim() || title.trim()}</p>
          </div>
        </div>
        <div className="af-phone-bottom">
          Feed <span>Komunitas</span>
        </div>
      </div>
      <AdminDialog
        open={productsOpen}
        title="Produk terkait"
        onClose={() => setProductsOpen(false)}
      >
        {products.map((product) => (
          <div className="af-preview-product" key={product.id}>
            {product.imageUrl ? (
              <Image
                src={product.imageUrl}
                width={48}
                height={64}
                alt=""
                className="object-cover"
              />
            ) : (
              <FiPackage aria-hidden />
            )}
            <div>
              <strong>{product.name}</strong>
              {product.price != null && (
                <p>{formatRupiah(product.promoPrice ?? product.price)}</p>
              )}
            </div>
          </div>
        ))}
      </AdminDialog>
    </>
  );
}

/** Preview starts on demand and releases HLS buffers when the dialog closes. */
function PreviewVideo({
  source,
  poster,
  title,
}: {
  source: string;
  poster: string | null;
  title: string;
}) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const hlsRef = useRef<import("hls.js").default | null>(null);
  const generation = useRef(0);
  const [started, setStarted] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    const video = videoRef.current;
    setStarted(false);
    setBusy(false);
    setError(null);
    return () => {
      generation.current += 1;
      video?.pause();
      hlsRef.current?.destroy();
      hlsRef.current = null;
    };
  }, [source]);
  async function play() {
    const video = videoRef.current;
    if (!video || busy) return;
    const token = generation.current;
    setBusy(true);
    setError(null);
    const fail = () => {
      if (token === generation.current) {
        video.pause();
        const failedHls = hlsRef.current;
        hlsRef.current = null;
        failedHls?.destroy();
        setError(
          "Video belum dapat diputar. Coba kembali atau periksa status pemrosesan."
        );
        setBusy(false);
        setStarted(false);
      }
    };
    const begin = () => {
      void video
        .play()
        .then(() => {
          if (token === generation.current) {
            setBusy(false);
            setStarted(true);
          }
        })
        .catch(fail);
    };
    try {
      if (
        /\.m3u8(?:\?|$)/i.test(source) &&
        !video.canPlayType("application/vnd.apple.mpegurl")
      ) {
        hlsRef.current?.destroy();
        hlsRef.current = null;
        const { default: Hls } = await import("hls.js");
        if (token !== generation.current) return;
        if (!Hls.isSupported()) {
          fail();
          return;
        }
        const hls = new Hls({
          maxBufferLength: 10,
          maxMaxBufferLength: 30,
          capLevelToPlayerSize: true,
        });
        hlsRef.current = hls;
        hls.on(Hls.Events.MANIFEST_PARSED, begin);
        hls.on(Hls.Events.ERROR, (_event, data) => {
          if (data.fatal) fail();
        });
        hls.loadSource(source);
        hls.attachMedia(video);
      } else {
        video.src = source;
        begin();
      }
    } catch {
      fail();
    }
  }
  return (
    <>
      <video
        ref={videoRef}
        poster={poster || undefined}
        controls={started}
        playsInline
        preload="none"
        aria-label={`Video ${title}`}
        onError={() => {
          setError("Video belum dapat diputar. Coba kembali.");
          setBusy(false);
          setStarted(false);
        }}
      />
      {!started && (
        <button
          className="af-preview-play"
          type="button"
          onClick={() => void play()}
          disabled={busy}
          aria-label={busy ? "Menyiapkan video" : "Putar video"}
        >
          <FiPlay aria-hidden />
          {busy && <span>Menyiapkan…</span>}
        </button>
      )}
      {error && (
        <p className="af-video-error" role="alert">
          {error}
        </p>
      )}
    </>
  );
}
