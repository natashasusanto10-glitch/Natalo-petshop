import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";

import {
  buildProductShareMetadata,
  buildPublicShareProduct,
  buildUnavailableProductShareMetadata,
  getPublicShareProduct,
} from "@/lib/share/product-share-data";
import {
  buildProfileShareMetadata,
  buildPublicProfilePageViewModel,
  buildPublicShareProfile,
  buildUnavailableProfileShareMetadata,
  getPublicShareProfile,
  sanitizePublicProfileBio,
} from "@/lib/share/profile-share-data";
import { buildProductShareCardModel, renderProductShareCard } from "@/lib/share/og/product-card";
import { buildProfileShareCardModel, renderProfileShareCard } from "@/lib/share/og/profile-card";
import { OFFICIAL_BRAND_NAME } from "@/lib/social/brand-user";

const siteUrl = "https://www.natalopetshop.com";

test("product share preview uses effective price, stock label, canonical URL, and versioned OG image", () => {
  const product = buildPublicShareProduct({
    id: "product-1",
    slug: "makanan kucing",
    name: "Makanan Kucing Premium",
    price: 125000,
    discountPrice: 99000,
    stock: 3,
    imageUrl: "https://vz-natalo.b-cdn.net/products/makanan.png?token=temporary",
  });

  assert.ok(product);
  if (!product) return;
  assert.equal(product.slug, "makanan kucing");
  assert.equal(product.effectivePrice, 99000);
  assert.equal(product.originalPrice, 125000);
  assert.equal(product.discountPercent, 21);
  assert.equal(product.stockLabel, "Stok terbatas");
  assert.ok(product.shareVersion);

  const metadata = buildProductShareMetadata(product, siteUrl);
  assert.equal(metadata.alternates?.canonical, `${siteUrl}/products/makanan%20kucing`);
  assert.equal(metadata.openGraph?.url, `${siteUrl}/products/makanan%20kucing`);
  const image = Array.isArray(metadata.openGraph?.images) ? metadata.openGraph.images[0] : null;
  assert.equal(
    typeof image === "string" ? image : image instanceof URL ? image.toString() : image?.url,
    `${siteUrl}/api/share/og/product/makanan%20kucing?v=${product.shareVersion}`,
  );
  assert.match(String(metadata.description).replace(/\s/g, " "), /Rp 99\.000 - Stok terbatas/);
});

test("official profile share preview keeps the brand identity, normalized username, and official logo", () => {
  const profile = buildPublicShareProfile({
    id: "admin-1",
    username: "NataloPetshop",
    name: "Private Administrator",
    role: "ADMIN",
    profilePhotoUrl: "https://image.ufs.sh/private-admin.jpg",
    bio: "Private bio",
    followersCount: 12,
    followingCount: 4,
    postCount: 8,
  });

  assert.ok(profile);
  if (!profile) return;
  assert.equal(profile.displayName, OFFICIAL_BRAND_NAME);
  assert.equal(profile.username, "natalopetshop");
  assert.equal(profile.avatarUrl, "/logo.png");
  assert.equal(profile.isOfficial, true);
  assert.equal(profile.bio, null);
  assert.notEqual(profile.displayName, "Private Administrator");
  assert.notEqual(profile.avatarUrl, "https://image.ufs.sh/private-admin.jpg");

  const metadata = buildProfileShareMetadata(profile, siteUrl);
  assert.equal(metadata.alternates?.canonical, `${siteUrl}/u/natalopetshop`);
  assert.equal(metadata.openGraph?.url, `${siteUrl}/u/natalopetshop`);
  assert.equal(metadata.title, `${OFFICIAL_BRAND_NAME} (@natalopetshop) di Natalo`);
  const image = Array.isArray(metadata.openGraph?.images) ? metadata.openGraph.images[0] : null;
  assert.equal(
    typeof image === "string" ? image : image instanceof URL ? image.toString() : image?.url,
    `${siteUrl}/api/share/og/profile/natalopetshop?v=${profile.shareVersion}`,
  );

  const page = buildPublicProfilePageViewModel(profile);
  assert.equal(page.displayName, OFFICIAL_BRAND_NAME);
  assert.equal(page.avatarUrl, "/logo.png");
  assert.equal(page.bio, null);
  assert.doesNotMatch(JSON.stringify(page), /Private Administrator|Private bio|private-admin\.jpg/);
});

test("profile bio strips control characters and missing resources resolve to no preview", () => {
  assert.equal(
    sanitizePublicProfileBio("  Kucing\u0000 sehat\n dan aktif\u007f  "),
    "Kucing sehat dan aktif",
  );
  assert.equal(buildPublicShareProfile(null), null);
  assert.equal(buildPublicShareProduct(null), null);
});

test("public profile page view model preserves sanitized customer identity", () => {
  const profile = buildPublicShareProfile({
    id: "customer-1",
    username: "pet lover",
    name: "Pet Lover",
    role: "CUSTOMER",
    profilePhotoUrl: "https://vz-natalo.b-cdn.net/avatars/pet-lover.png?token=temporary",
    bio: "  Pecinta\n kucing  ",
    followersCount: 1,
    followingCount: 2,
    postCount: 3,
  });

  assert.ok(profile);
  if (!profile) return;
  assert.deepEqual(buildPublicProfilePageViewModel(profile), {
    id: "customer-1",
    username: "pet lover",
    displayName: "Pet Lover",
    avatarUrl: "https://vz-natalo.b-cdn.net/avatars/pet-lover.png",
    bio: "Pecinta kucing",
    isOfficial: false,
    postCount: 3,
  });
});

test("missing public records become null and unavailable metadata is noindex", async () => {
  assert.equal(await getPublicShareProduct("missing", async () => null), null);
  assert.equal(await getPublicShareProfile("missing", async () => null), null);
  assert.deepEqual(buildUnavailableProductShareMetadata().robots, { index: false, follow: false });
  assert.deepEqual(buildUnavailableProfileShareMetadata().robots, { index: false, follow: false });
});

test("product and profile cards use only safe rendered assets and retain local fallbacks", () => {
  const product = buildPublicShareProduct({
    id: "product-1",
    slug: "makanan-kucing",
    name: "Makanan Kucing Premium",
    price: 125000,
    discountPrice: 99000,
    stock: 10,
    imageUrl: "https://127.0.0.1/private.png",
  });
  assert.ok(product);
  if (!product) return;
  assert.equal(buildProductShareCardModel(product).imageUrl, null);
  assert.doesNotMatch(JSON.stringify(renderProductShareCard({ ...product, renderedImageUrl: null })), /127\.0\.0\.1/);

  const profile = buildPublicShareProfile({
    id: "user-1",
    username: "petlover",
    name: "Pet Lover",
    role: "CUSTOMER",
    profilePhotoUrl: "https://127.0.0.1/private.png",
    bio: null,
    followersCount: 1,
    followingCount: 2,
    postCount: 3,
  });
  assert.ok(profile);
  if (!profile) return;
  assert.equal(buildProfileShareCardModel(profile).avatarUrl, null);
  assert.doesNotMatch(JSON.stringify(renderProfileShareCard({ ...profile, renderedAvatarUrl: null })), /127\.0\.0\.1/);
});

test("share versions change only when public product or profile preview values change", () => {
  const standardProduct = buildPublicShareProduct({
    id: "product-1",
    slug: "makanan-kucing",
    name: "Makanan Kucing",
    price: 100000,
    discountPrice: null,
    stock: 10,
    imageUrl: "https://vz-natalo.b-cdn.net/products/makanan.png?temporary=one",
  });
  const discountedProduct = buildPublicShareProduct({
    id: "product-1",
    slug: "makanan-kucing",
    name: "Makanan Kucing",
    price: 100000,
    discountPrice: 90000,
    stock: 10,
    imageUrl: "https://vz-natalo.b-cdn.net/products/makanan.png?temporary=two",
  });
  assert.ok(standardProduct && discountedProduct);
  if (!standardProduct || !discountedProduct) return;
  assert.notEqual(standardProduct.shareVersion, discountedProduct.shareVersion);

  const profile = (followersCount: number) => buildPublicShareProfile({
    id: "user-1",
    username: "petlover",
    name: "Pet Lover",
    role: "CUSTOMER",
    profilePhotoUrl: null,
    bio: "Pecinta kucing",
    followersCount,
    followingCount: 2,
    postCount: 3,
  });
  const firstProfile = profile(1);
  const nextProfile = profile(2);
  assert.ok(firstProfile && nextProfile);
  if (!firstProfile || !nextProfile) return;
  assert.notEqual(firstProfile.shareVersion, nextProfile.shareVersion);
});

/**
 * Regresi kontras kartu OG.
 *
 * Bug asli: nama produk tidak diberi `color`, jadi mewarisi #10213D dari
 * elemen induk dan tampil di atas panel #0F2F63 — kontras 1,23:1, tak
 * terbaca. Satori tidak punya "warna default yang aman", jadi satu-satunya
 * cara mencegah ini terulang adalah mewajibkan SETIAP simpul berteks punya
 * warna eksplisit.
 */
type OgNode = { props?: { children?: unknown; style?: { color?: string } } };

function textNodesWithoutColor(node: unknown, path = "root"): string[] {
  if (!node || typeof node !== "object") return [];
  const el = node as OgNode;
  const children = el.props?.children;
  const found: string[] = [];

  const hasOwnText = Array.isArray(children)
    ? children.some((c) => typeof c === "string" && c.trim() !== "")
    : typeof children === "string" && children.trim() !== "";

  if (hasOwnText && !el.props?.style?.color) {
    const sample = Array.isArray(children) ? children.find((c) => typeof c === "string") : children;
    found.push(`${path}: "${String(sample).slice(0, 40)}"`);
  }

  const kids = Array.isArray(children) ? children : [children];
  kids.forEach((child, index) => {
    found.push(...textNodesWithoutColor(child, `${path}>${index}`));
  });
  return found;
}

test("kartu OG produk: setiap teks punya warna eksplisit (tidak mewarisi)", () => {
  const product = buildPublicShareProduct({
    id: "p-og",
    slug: "produk-nama-sangat-panjang",
    name: "Catto Plus Jelly Anti Hairball / Hair & Skin / Indoor / Immune Booster / Urinary Adult Pouch Wet Food 1 BOX isi (12pcs x 70gr) - Makanan Basah Saset Kucing Dewasa",
    price: 140000,
    discountPrice: 114000,
    stock: 5,
    imageUrl: "https://eift0f4dwz.ufs.sh/f/contoh.png",
  });
  assert.ok(product);
  if (!product) return;

  const withDiscount = renderProductShareCard({ ...product, renderedImageUrl: null });
  assert.deepEqual(textNodesWithoutColor(withDiscount), [], "ada teks tanpa warna eksplisit di kartu produk");

  const noDiscount = buildPublicShareProduct({
    id: "p-og-2", slug: "tanpa-diskon", name: "Produk tanpa diskon",
    price: 50000, discountPrice: null, stock: 2, imageUrl: null,
  });
  assert.ok(noDiscount);
  if (!noDiscount) return;
  assert.deepEqual(
    textNodesWithoutColor(renderProductShareCard({ ...noDiscount, renderedImageUrl: null })),
    [],
    "ada teks tanpa warna eksplisit saat produk tidak diskon",
  );
});

test("kartu OG produk: full-bleed tanpa hamparan apa pun (foto tak boleh tertutup)", () => {
  const product = buildPublicShareProduct({
    id: "p-og-3",
    slug: "nama-panjang",
    name: "Catto Plus Jelly Anti Hairball Urinary Adult Pouch Wet Food",
    price: 140000, discountPrice: 114000, stock: 5, imageUrl: null,
  });
  assert.ok(product);
  if (!product) return;

  const tree = JSON.stringify(renderProductShareCard({ ...product, renderedImageUrl: null }));
  // Semua teks ini muncul lagi di gambar = ada elemen yang menutupi foto.
  // Foto template katalog memakai KEEMPAT sudut untuk badge (varian,
  // Grain Free, No Pork, "1/6"), jadi tidak ada sudut aman — dibuktikan
  // lewat render mockup, bukan dugaan.
  assert.doesNotMatch(tree, /Catto Plus Jelly/, "nama produk tidak digambar");
  assert.doesNotMatch(tree, /Stok tersedia|Stok terbatas/, "label stok tidak digambar");
  assert.doesNotMatch(tree, /Natalo Petshop/, "chip merek dibuang — pita foto template sudah memuatnya");
  assert.doesNotMatch(tree, /HEMAT \d+%/, "badge diskon dibuang — menabrak badge bawaan foto");
  assert.doesNotMatch(tree, /Rp/, "chip harga dibuang — harga tampil di teks bawah kartu");
  // Padding WAJIB nol: tepi putih membuat foto mengecil, kebalikan tujuan.
  assert.doesNotMatch(tree, /"padding"/, "kartu harus full-bleed, tanpa padding");

  // Model tetap lengkap — dipakai metadata halaman, bukan gambar.
  const model = buildProductShareCardModel({ ...product, renderedImageUrl: null });
  assert.match(model.name, /Catto Plus Jelly/);
  assert.ok(model.stockLabel.length > 0);
  assert.match(model.priceLabel, /Rp/);
  assert.match(String(model.discountLabel), /HEMAT \d+%/);
});

test("kartu OG produk: ukuran render & og:image metadata WAJIB sinkron", () => {
  // Klien chat menata kartu memakai width/height yang DIDEKLARASIKAN di
  // metadata. Kalau gambar dirender persegi tapi metadata masih bilang
  // 1200x630, kartunya ditata dengan rasio salah — dan tidak ada error
  // apa pun yang muncul. Dua angka di dua berkas berbeda, mudah lupa.
  const routeSrc = readFileSync(
    new URL("../app/api/share/og/product/[slug]/route.ts", import.meta.url),
    "utf8",
  );
  const metaSrc = readFileSync(
    new URL("../lib/share/product-share-data.ts", import.meta.url),
    "utf8",
  );

  const route = routeSrc.match(/IMAGE_OPTIONS = \{ height: (\d+), width: (\d+) \}/);
  assert.ok(route, "IMAGE_OPTIONS tidak ditemukan di rute OG produk");
  const meta = metaSrc.match(/images: \[\{ url: image, width: (\d+), height: (\d+)/);
  assert.ok(meta, "og:image metadata produk tidak ditemukan");

  const [routeH, routeW] = [Number(route[1]), Number(route[2])];
  const [metaW, metaH] = [Number(meta[1]), Number(meta[2])];
  assert.equal(routeW, metaW, "lebar rute vs metadata berbeda");
  assert.equal(routeH, metaH, "tinggi rute vs metadata berbeda");
  assert.equal(routeW, routeH, "kartu produk harus PERSEGI — lihat catatan di route.ts");
});
