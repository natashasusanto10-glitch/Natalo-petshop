import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";

import { buildFeedShareCardModel, renderFeedShareCard } from "@/lib/share/og/feed-card";
import { safeOgImageUrl } from "@/lib/share/og-image-security";

const basePost = {
  id: "post-1",
  shareVersion: "preview-v1",
  title: "Feed test",
  description: "Foto baru untuk si meong yang aktif dan sehat.",
  kind: "VIDEO_ONLY",
  posterUrl: "https://vz-natalo.b-cdn.net/post-1/thumbnail.jpg",
  author: {
    displayName: "Natalo Petshop",
    photoUrl: "https://www.natalopetshop.com/brand/logo.png",
    username: "natalopetshop",
    isOfficial: true,
  },
};

test("builds a video card with a safe poster, play signal, and official author", () => {
  const previousBunnyHost = process.env.BUNNY_CDN_HOSTNAME;
  process.env.BUNNY_CDN_HOSTNAME = "vz-natalo.b-cdn.net";

  try {
    const card = buildFeedShareCardModel({ ...basePost, durationSec: 65 });

    assert.equal(card.mediaUrl, basePost.posterUrl);
    assert.equal(card.showPlayBadge, true);
    assert.equal(card.durationLabel, "1:05");
    assert.equal(card.authorLabel, "Natalo Petshop");
    assert.equal(card.isOfficial, true);
    assert.equal(card.carouselLabel, null);
  } finally {
    if (previousBunnyHost === undefined) delete process.env.BUNNY_CDN_HOSTNAME;
    else process.env.BUNNY_CDN_HOSTNAME = previousBunnyHost;
  }
});

test("falls back safely for missing or unsafe poster and labels a carousel", () => {
  const card = buildFeedShareCardModel({
    ...basePost,
    kind: "PHOTO_CAROUSEL",
    posterUrl: "https://127.0.0.1/secret.jpg",
    description: "",
    mediaCount: 3,
  });

  assert.equal(card.mediaUrl, null);
  assert.equal(card.showPlayBadge, false);
  assert.equal(card.durationLabel, null);
  assert.equal(card.carouselLabel, "1/3");
  assert.equal(card.description, "Lihat postingan terbaru di Natalo.");
});

test("kartu full-bleed tidak menggambar teks di atas thumbnail", () => {
  // Caption & nama author kini dibawa metadata halaman (judul link).
  // Kalau ada yang menggambarnya lagi di kartu, teks yang sama tampil
  // dua kali berturut-turut di pratinjau chat.
  const serialized = JSON.stringify(
    renderFeedShareCard({ ...basePost, renderedMediaUrl: "data:image/png;base64,x" }),
  );
  assert.doesNotMatch(serialized, /Foto baru untuk si meong/);
  assert.doesNotMatch(serialized, /Natalo Petshop/);
  assert.doesNotMatch(serialized, /AKUN RESMI/);
  assert.doesNotMatch(serialized, /natalopetshop\.com/);
  // Badge video tetap ada — penanda "ini video, tap untuk menonton".
  assert.match(serialized, /▶/);
});

test("keeps the local fallback when the route reports a failed remote fetch", () => {
  const card = renderFeedShareCard({
    ...basePost,
    renderedAuthorImageUrl: null,
    renderedMediaUrl: null,
  });

  const serialized = JSON.stringify(card);
  assert.doesNotMatch(serialized, /vz-natalo\.b-cdn\.net/);
  assert.doesNotMatch(serialized, /www\.natalopetshop\.com\/brand\/logo\.png/);
});

test("URL thumbnail bertoken Bunny lolos validasi host OG", () => {
  // Bunny memakai token authentication: thumbnail tanpa ?token=&expires=
  // dibalas 403 dan kartu jatuh ke monogram "N". Rute OG karena itu
  // menandatangani ulang sebelum mengambil. Kalau ada yang memperketat
  // safeOgImageUrl sampai menolak query string, thumbnail mati LAGI tanpa
  // error apa pun — test ini yang menahannya.
  const previousBunnyHost = process.env.BUNNY_CDN_HOSTNAME;
  process.env.BUNNY_CDN_HOSTNAME = "vz-natalo.b-cdn.net";
  try {
    const signed =
      "https://vz-natalo.b-cdn.net/abc/thumbnail.jpg?token=Eq57TGnn&expires=1787869996";
    assert.equal(safeOgImageUrl(signed), signed);
  } finally {
    if (previousBunnyHost === undefined) delete process.env.BUNNY_CDN_HOSTNAME;
    else process.env.BUNNY_CDN_HOSTNAME = previousBunnyHost;
  }
});

test("rute OG dan halaman share menandatangani poster sebelum dipakai", () => {
  // Penjaga sumber: melewatkan signBunnyUrl tidak menimbulkan error apa
  // pun — kartu diam-diam kehilangan gambar. Ini bug yang benar-benar
  // terjadi di produksi (27 Agu 2026).
  const routeSource = readFileSync(
    new URL("../app/api/share/og/feed/[id]/route.ts", import.meta.url),
    "utf8",
  );
  assert.match(routeSource, /signBunnyUrl\(post\.posterUrl\)/);

  const pageSource = readFileSync(
    new URL("../app/feed/[id]/page.tsx", import.meta.url),
    "utf8",
  );
  assert.match(pageSource, /signBunnyUrl\(post\.posterUrl\)/);
  assert.doesNotMatch(pageSource, /src=\{post\.posterUrl\}/);
});
