import assert from "node:assert/strict";
import test from "node:test";

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
