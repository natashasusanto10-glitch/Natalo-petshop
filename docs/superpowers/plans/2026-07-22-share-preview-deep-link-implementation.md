# Share Preview dan Deep Link Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Membuat share Feed, produk, dan profil menghasilkan rich preview WhatsApp yang sesuai objek serta membuka layar native yang tepat pada Android dan iOS, termasuk cold start.

**Architecture:** Flutter membentuk satu canonical HTTPS URL melalui builder murni dan mengirimkannya ke system share sheet. Next.js menyediakan halaman publik, metadata dinamis, serta endpoint gambar OG eksplisit per tipe konten. Server menghasilkan `shareVersion` deterministik dari field publik agar preview dapat di-version tanpa URL unik per share. Android App Links dipertahankan; iOS AASA ditambah `/feed/*`; parser dan lifecycle deep link Flutter diperkeras dengan pending queue dan deduplikasi.

**Tech Stack:** Flutter/Dart, `share_plus`, `app_links`, Next.js App Router, TypeScript, Prisma, `next/og` `ImageResponse`, Node test runner + `tsx`, Flutter test.

## Global Constraints

- Kerjakan dari `main` yang sudah disinkronkan dengan `origin/main` di worktree terpisah; jangan menimpa perubahan lokal pengguna.
- Tidak ada migration Prisma untuk fitur ini.
- URL share production selalu memakai `ApiConfig.publicSiteUrl`, bukan `apiBaseUrl`.
- Canonical URL tidak membawa query; URL yang dikirim boleh membawa `?v=<shareVersion>`.
- `shareVersion` deterministik dari data publik, bukan timestamp saat user menekan Share.
- Share count Feed hanya bertambah setelah `ShareResultStatus.success`; dismissed/unavailable tidak menambah count.
- Jangan menambah `og:video` atau membagikan attachment media pada MVP.
- Jangan membuat generic image proxy. Remote image hanya boleh berasal dari HTTPS host CDN resmi yang lolos allowlist.
- Konten Feed nonaktif, pending, rejected, atau soft-deleted selalu 404/noindex dan tidak boleh muncul di OG image.
- Android Manifest dan iOS entitlements sudah memiliki kedua host production. Jangan mengubahnya tanpa bukti device association gagal.
- Web harus dideploy sebelum build mobile diuji agar crawler dan universal links mempunyai target production yang valid.

---

## Task 1: Kunci kontrak `shareVersion` di server dan API publik

**Files:**
- Create: `lib/share/share-version.ts`
- Create: `tests/share-version.test.ts`
- Modify: `lib/feed/queries.ts`
- Modify: `app/api/feed/posts/[id]/route.ts`
- Modify: `app/api/u/[username]/route.ts`
- Modify: `app/api/products/[slug]/route.ts`

- [ ] **Step 1: Tulis test gagal untuk token deterministik**

```ts
import assert from "node:assert/strict";
import test from "node:test";
import { buildShareVersion, stripEphemeralUrlQuery } from "../lib/share/share-version";

test("shareVersion stabil dan berubah ketika data preview berubah", () => {
  const first = buildShareVersion(["post-1", "caption", "https://cdn/x.jpg"]);
  assert.equal(first, buildShareVersion(["post-1", "caption", "https://cdn/x.jpg"]));
  assert.notEqual(first, buildShareVersion(["post-1", "caption baru", "https://cdn/x.jpg"]));
  assert.match(first, /^[a-zA-Z0-9_-]{12,16}$/);
});

test("signed query media tidak membuat versi berubah", () => {
  assert.equal(
    stripEphemeralUrlQuery("https://cdn.example/x.jpg?token=a&expires=1"),
    "https://cdn.example/x.jpg",
  );
});
```

- [ ] **Step 2: Jalankan test dan pastikan merah**

Run: `npx tsx --test tests/share-version.test.ts`

Expected: FAIL karena module `lib/share/share-version.ts` belum ada.

- [ ] **Step 3: Implementasikan helper versi**

```ts
import { createHash } from "node:crypto";

export function stripEphemeralUrlQuery(value: string | null | undefined) {
  if (!value) return "";
  try {
    const url = new URL(value);
    return `${url.origin}${url.pathname}`;
  } catch {
    return value.trim();
  }
}

export function buildShareVersion(parts: readonly unknown[]) {
  const normalized = parts.map((part) => String(part ?? "").trim()).join("\u001f");
  return createHash("sha256").update(normalized).digest("base64url").slice(0, 16);
}
```

- [ ] **Step 4: Tambahkan `shareVersion` ke seluruh payload yang dipakai Flutter**

Feed minimum input:

```ts
shareVersion: buildShareVersion([
  post.id,
  post.title,
  post.description,
  stripEphemeralUrlQuery(post.thumbnailUrl),
  post.videoDurationSec,
  authorDisplayName,
  stripEphemeralUrlQuery(authorPhoto),
  isOfficial,
]),
```

Produk minimum input:

```ts
shareVersion: buildShareVersion([
  product.slug,
  product.name,
  stripEphemeralUrlQuery(product.imageUrl),
  effectivePrice,
  product.price,
  product.stock,
]),
```

Profil minimum input harus mencakup username, brand-safe display name/avatar, bio publik, official flag, post/follower/following count. Item Feed pada response profil juga harus membawa versi Feed masing-masing.

- [ ] **Step 5: Jalankan test server terkait**

Run: `npx tsx --test tests/share-version.test.ts tests/brand-user.test.ts tests/feed-product-discount.test.ts`

Expected: PASS.

- [ ] **Step 6: Typecheck**

Run: `npx tsc --noEmit`

Expected: exit 0.

- [ ] **Step 7: Commit**

```bash
git add lib/share/share-version.ts tests/share-version.test.ts lib/feed/queries.ts app/api/feed/posts/[id]/route.ts app/api/u/[username]/route.ts app/api/products/[slug]/route.ts
git commit -m "feat(share): expose deterministic preview versions"
```

---

## Task 2: Tambahkan model share dan builder URL murni di Flutter

**Files:**
- Create: `flutter_app/lib/models/share_content.dart`
- Create: `flutter_app/lib/services/share_link_builder.dart`
- Create: `flutter_app/test/services/share_link_builder_test.dart`
- Modify: `flutter_app/lib/models/feed_post.dart`
- Modify: `flutter_app/lib/models/product.dart`
- Modify: `flutter_app/lib/models/public_profile.dart`
- Modify: `flutter_app/test/models/public_profile_test.dart`
- Modify: `flutter_app/test/models/feed_post_accessibility_test.dart`
- Modify: `flutter_app/test/services/product_service_raw_test.dart`

- [ ] **Step 1: Tulis test builder dan parser model yang gagal**

```dart
test('feed share uses production public host and optional version', () {
  final payload = ShareLinkBuilder(baseUrl: 'https://www.natalopetshop.com')
      .build(const FeedShareContent(
        postId: 'post/a',
        authorName: 'Natalo Petshop',
        caption: 'Caption',
        shareVersion: 'abc123',
      ));

  expect(payload.url.toString(),
      'https://www.natalopetshop.com/feed/post%2Fa?v=abc123');
  expect(payload.text, endsWith(payload.url.toString()));
  expect(payload.text, isNot(contains('Caption')));
});

test('empty shareVersion is omitted', () {
  final payload = builder.build(const ProfileShareContent(
    username: 'NataloPetshop',
    displayName: 'Natalo Petshop',
    shareVersion: '',
  ));
  expect(payload.url.query, isEmpty);
  expect(payload.url.path, '/u/natalopetshop');
});
```

Tambahkan assertion bahwa `FeedPost.fromJson`, `Product.fromJson`, dan `PublicProfile.fromJson` menerima `shareVersion`, tetap aman saat field hilang, dan round-trip cache Feed tidak menghapus token.

- [ ] **Step 2: Jalankan test dan pastikan merah**

Run dari `flutter_app`: `flutter test test/services/share_link_builder_test.dart test/models/public_profile_test.dart test/services/product_service_raw_test.dart`

Expected: FAIL karena class/field belum ada.

- [ ] **Step 3: Implementasikan sealed content dan payload**

```dart
sealed class ShareContent {
  const ShareContent({this.shareVersion});
  final String? shareVersion;
}

final class SharePayload {
  const SharePayload({required this.url, required this.text, this.subject});
  final Uri url;
  final String text;
  final String? subject;
}
```

Tambahkan `FeedShareContent`, `ProductShareContent`, dan `ProfileShareContent` sesuai spec. Constructor wajib menampung ID/slug/username dan copy pendek yang diperlukan.

- [ ] **Step 4: Implementasikan builder tanpa `BuildContext` atau network**

```dart
class ShareLinkBuilder {
  const ShareLinkBuilder({this.baseUrl = ApiConfig.publicSiteUrl});

  final String baseUrl;

  Uri _uri(List<String> segments, String? version) {
    final base = Uri.parse(baseUrl);
    final cleanVersion = version?.trim();
    return base.replace(
      pathSegments: [...base.pathSegments, ...segments],
      queryParameters:
          cleanVersion == null || cleanVersion.isEmpty ? null : {'v': cleanVersion},
    );
  }
}
```

Harga produk memakai formatter rupiah yang sudah ada atau helper murni lokal; jangan membuat formatter berbeda antar screen.

- [ ] **Step 5: Tambahkan `String? shareVersion` secara backward-compatible ke tiga model**

Feed harus ikut `copyWith()` dan `toJson()` agar versi tidak hilang di `FeedStore`/offline cache. Product dan PublicProfile harus mengikuti constructor/copyWith lokal tanpa mengubah equality atau field lain.

- [ ] **Step 6: Jalankan test terfokus**

Run: `flutter test test/services/share_link_builder_test.dart test/models/public_profile_test.dart test/services/product_service_raw_test.dart test/state/feed_store_share_test.dart`

Expected: PASS.

- [ ] **Step 7: Analyze**

Run: `flutter analyze lib/models/share_content.dart lib/services/share_link_builder.dart lib/models/feed_post.dart lib/models/product.dart lib/models/public_profile.dart`

Expected: no issues.

- [ ] **Step 8: Commit**

```bash
git add flutter_app/lib/models/share_content.dart flutter_app/lib/services/share_link_builder.dart flutter_app/lib/models/feed_post.dart flutter_app/lib/models/product.dart flutter_app/lib/models/public_profile.dart flutter_app/test
git commit -m "feat(share): add canonical Flutter share payloads"
```

---

## Task 3: Migrasikan semua permukaan share Flutter dan pertahankan count

**Files:**
- Create: `flutter_app/lib/services/share_sheet_launcher.dart`
- Create: `flutter_app/test/services/share_sheet_launcher_test.dart`
- Modify: `flutter_app/lib/services/app_analytics.dart`
- Modify: `flutter_app/lib/screens/feed_screen.dart`
- Modify: `flutter_app/lib/features/feed/widgets/feed_video_post_view.dart`
- Modify: `flutter_app/lib/screens/member_post_detail_screen.dart`
- Modify: `flutter_app/lib/screens/product_detail_screen.dart`
- Modify: `flutter_app/lib/screens/member_posts_screen.dart`
- Modify: `flutter_app/lib/screens/public_profile_screen.dart`
- Modify: `flutter_app/test/state/feed_store_share_test.dart`

- [ ] **Step 1: Tulis test gagal untuk hasil share dan idempotensi callback lokal**

Gunakan interface kecil agar `share_plus` dapat dipalsukan:

```dart
abstract interface class PlatformShareGateway {
  Future<ShareResultStatus> share(SharePayload payload, {Rect? origin});
}

test('success invokes completion once, dismissed never does', () async {
  final gateway = FakeShareGateway([ShareResultStatus.success]);
  var completed = 0;
  await launcher.launch(payload, gateway: gateway, onCompleted: () async {
    completed++;
  });
  expect(completed, 1);
});
```

- [ ] **Step 2: Jalankan test dan pastikan merah**

Run: `flutter test test/services/share_sheet_launcher_test.dart`

Expected: FAIL karena launcher belum ada.

- [ ] **Step 3: Implementasikan launcher dan anchor iPad**

Launcher menerima `Rect? origin`, memanggil `Share.shareWithResult`, memetakan status, serta menjalankan callback sukses sekali. Helper UI boleh menghitung origin dari `RenderBox`, tetapi builder URL tetap murni.

```dart
Rect? shareOriginFor(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}
```

- [ ] **Step 4: Tambahkan event analytics aman**

Tambahkan wrapper untuk `share_sheet_opened`, `share_completed`, dan `share_dismissed` dengan property `content_type`, `content_id`, `os`, dan `result`. Jangan log caption, kontak, atau aplikasi tujuan.

- [ ] **Step 5: Migrasikan call site satu per satu**

Urutan:

1. `product_detail_screen.dart`
2. `member_posts_screen.dart`
3. `public_profile_screen.dart`
4. `member_post_detail_screen.dart`
5. `feed_screen.dart`
6. `feed_video_post_view.dart`

Aturan penting:

- Detail Postingan harus memakai `post.id`, bukan `post.slug`, untuk `/feed/<postId>`.
- Semua URL memakai builder dan `ApiConfig.publicSiteUrl`.
- Feed memanggil endpoint increment + `FeedStore` hanya setelah success.
- Setiap tombol meneruskan `sharePositionOrigin` yang valid jika tersedia.
- Copy pesan maksimal dua baris sebelum URL dan tidak menyalin caption penuh.

- [ ] **Step 6: Jalankan test launcher dan store**

Run: `flutter test test/services/share_sheet_launcher_test.dart test/state/feed_store_share_test.dart test/features/feed/widgets/feed_video_post_view_test.dart test/screens/member_post_detail_screen_caption_test.dart`

Expected: PASS.

- [ ] **Step 7: Cari implementasi share lama yang tersisa**

Run: `rg -n "Share\.share|Share\.shareWithResult|/feed/|/products/|/u/" flutter_app/lib/screens flutter_app/lib/features/feed`

Expected: pemanggilan platform share hanya melalui launcher; literal URL objek tidak lagi dibentuk di screen terkait.

- [ ] **Step 8: Commit**

```bash
git add flutter_app/lib/services/share_sheet_launcher.dart flutter_app/lib/services/app_analytics.dart flutter_app/lib/screens flutter_app/lib/features/feed flutter_app/test
git commit -m "refactor(share): unify product feed and profile actions"
```

---

## Task 4: Buat query publik dan halaman `/feed/[id]`

**Files:**
- Create: `lib/share/feed-share-data.ts`
- Create: `lib/share/share-metadata.ts`
- Create: `tests/share-feed-data.test.ts`
- Create: `tests/share-metadata.test.ts`
- Create: `app/feed/[id]/page.tsx`
- Modify: `app/feed/page.tsx`

- [ ] **Step 1: Tulis test gagal untuk visibilitas dan metadata Feed**

Pisahkan builder metadata dari Prisma agar dapat diuji tanpa database:

```ts
test("feed metadata uses canonical without v and versioned OG image", () => {
  const metadata = buildFeedShareMetadata(fakeFeed, SITE_URL);
  assert.equal(metadata.alternates?.canonical, `${SITE_URL}/feed/post-1`);
  assert.equal(metadata.openGraph?.url, `${SITE_URL}/feed/post-1`);
  assert.match(String(metadata.openGraph?.images?.[0]?.url),
    /api\/share\/og\/feed\/post-1\?v=/);
});
```

Test query contract harus memastikan `status: "ACTIVE"` dan `deletedAt: null` tidak dapat dihilangkan.

- [ ] **Step 2: Jalankan test dan pastikan merah**

Run: `npx tsx --test tests/share-feed-data.test.ts tests/share-metadata.test.ts`

Expected: FAIL.

- [ ] **Step 3: Implementasikan `getPublicShareFeedPost(id)`**

Helper server-only memilih field minimum, memakai `brandDisplayName`/`brandPhotoUrl`, menandatangani thumbnail hanya untuk response playback jika perlu, tetapi versi hash memakai URL canonical tanpa signed query.

Return `null` untuk post nonpublic. Jangan fallback ke query admin atau owner.

- [ ] **Step 4: Implementasikan metadata builder**

Semua field wajib spec harus ada: title, description 140 karakter, canonical, OG, Twitter large image, siteName, robots. OG image URL absolut menuju endpoint Task 5.

- [ ] **Step 5: Implementasikan halaman publik**

Halaman server component menampilkan poster/media pertama, identitas author, caption ringkas, CTA app/store, dan 404 dengan `notFound()` jika helper mengembalikan null. Jangan membaca session.

- [ ] **Step 6: Jalankan test dan typecheck**

Run: `npx tsx --test tests/share-feed-data.test.ts tests/share-metadata.test.ts`

Run: `npx tsc --noEmit`

Expected: PASS dan exit 0.

- [ ] **Step 7: Commit**

```bash
git add lib/share/feed-share-data.ts lib/share/share-metadata.ts tests/share-feed-data.test.ts tests/share-metadata.test.ts app/feed/[id]/page.tsx app/feed/page.tsx
git commit -m "feat(web): add public Feed share pages"
```

---

## Task 5: Implementasikan policy keamanan dan endpoint OG Feed

**Files:**
- Create: `lib/share/og-image-security.ts`
- Create: `lib/share/og/feed-card.tsx`
- Create: `app/api/share/og/feed/[id]/route.ts`
- Create: `tests/share-og-security.test.ts`
- Create: `tests/share-feed-card.test.ts`

- [ ] **Step 1: Tulis test allowlist yang gagal**

```ts
test("rejects deceptive, private, credential, and non-https URLs", () => {
  assert.equal(safeOgImageUrl("https://cdn.natalopetshop.com/x.jpg"),
    "https://cdn.natalopetshop.com/x.jpg");
  assert.equal(safeOgImageUrl("https://cdn.natalopetshop.com.evil.test/x"), null);
  assert.equal(safeOgImageUrl("https://127.0.0.1/x"), null);
  assert.equal(safeOgImageUrl("http://cdn.natalopetshop.com/x"), null);
  assert.equal(safeOgImageUrl("https://user:pass@cdn.natalopetshop.com/x"), null);
});
```

- [ ] **Step 2: Jalankan test dan pastikan merah**

Run: `npx tsx --test tests/share-og-security.test.ts`

Expected: FAIL.

- [ ] **Step 3: Implementasikan validator exact/suffix host**

Allowlist berasal dari host production, hostname Bunny yang dikonfigurasi, dan host storage upload yang memang digunakan repo. Normalisasi lowercase dan punycode melalui `URL`. Tolak IP literal, port eksplisit, credential, fragment, dan protocol selain HTTPS. Jangan menerima host berdasarkan `includes()`.

- [ ] **Step 4: Implementasikan card Feed sebagai fungsi murni JSX**

Card 1200x630 harus menangani video, foto, carousel, poster hilang, caption kosong, durasi, dan official avatar tanpa exception. Jangan memasukkan signed query ke versi.

- [ ] **Step 5: Implementasikan route `ImageResponse`**

```ts
export const runtime = "nodejs";

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  const post = await getPublicShareFeedPost(id);
  if (!post) return new NextResponse(null, { status: 404 });
  return new ImageResponse(renderFeedShareCard(post), {
    width: 1200,
    height: 630,
    headers: {
      "Cache-Control": "public, s-maxage=3600, stale-while-revalidate=86400",
    },
  });
}
```

Jika media tidak lolos validator, render fallback lokal; jangan return 500.

- [ ] **Step 6: Jalankan test**

Run: `npx tsx --test tests/share-og-security.test.ts tests/share-feed-card.test.ts`

Expected: PASS.

- [ ] **Step 7: Typecheck dan lint file terkait**

Run: `npx tsc --noEmit`

Run: `npx eslint lib/share app/api/share/og/feed tests/share-og-security.test.ts tests/share-feed-card.test.ts`

Expected: exit 0.

- [ ] **Step 8: Commit**

```bash
git add lib/share/og-image-security.ts lib/share/og/feed-card.tsx app/api/share/og/feed/[id]/route.ts tests/share-og-security.test.ts tests/share-feed-card.test.ts
git commit -m "feat(web): render secure Feed share cards"
```

---

## Task 6: Migrasikan preview produk dan tambahkan preview profil

**Files:**
- Create: `lib/share/product-share-data.ts`
- Create: `lib/share/profile-share-data.ts`
- Create: `lib/share/og/product-card.tsx`
- Create: `lib/share/og/profile-card.tsx`
- Create: `app/api/share/og/product/[slug]/route.ts`
- Create: `app/api/share/og/profile/[username]/route.ts`
- Create: `tests/share-product-profile.test.ts`
- Modify: `app/products/[slug]/page.tsx`
- Delete: `app/products/[slug]/opengraph-image.tsx`
- Modify: `app/u/[username]/page.tsx`

- [ ] **Step 1: Tulis test gagal untuk produk dan profil**

Test harus mengunci:

- harga efektif + stock label produk;
- canonical URL tanpa query;
- OG URL versioned;
- official profile memakai `OFFICIAL_BRAND_NAME` dan logo resmi, bukan nama/foto pribadi admin;
- username lowercase;
- bio/control character disanitasi;
- missing object menghasilkan null/404 path, bukan generic homepage preview.

- [ ] **Step 2: Jalankan test dan pastikan merah**

Run: `npx tsx --test tests/share-product-profile.test.ts`

Expected: FAIL.

- [ ] **Step 3: Ekstrak data helper produk/profil**

Gunakan query dan sanitasi yang sudah dipakai halaman detail/profil. Jangan menduplikasi rumus diskon. `shareVersion` harus dibangun dari data hasil resolver harga efektif dan statistik profil yang benar-benar tampil.

- [ ] **Step 4: Implementasikan card dan endpoint eksplisit**

Produk: image contain, nama dua baris, harga efektif, diskon aktif, identitas Natalo.

Profil: avatar/logo, display name, username, official badge, post/follower/following. Remote image selalu melalui `safeOgImageUrl`.

- [ ] **Step 5: Ubah metadata halaman**

`app/products/[slug]/page.tsx` dan `app/u/[username]/page.tsx` menunjuk endpoint baru secara eksplisit untuk OG dan Twitter. Canonical tanpa `v`; endpoint image dengan `v`.

- [ ] **Step 6: Pensiunkan generator produk lama**

Hapus `app/products/[slug]/opengraph-image.tsx` hanya setelah test metadata memastikan URL endpoint baru digunakan. Ini menghindari dua template produk permanen.

- [ ] **Step 7: Test dan typecheck**

Run: `npx tsx --test tests/share-product-profile.test.ts tests/brand-user.test.ts`

Run: `npx tsc --noEmit`

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/share app/api/share/og app/products/[slug]/page.tsx app/u/[username]/page.tsx tests/share-product-profile.test.ts
git rm app/products/[slug]/opengraph-image.tsx
git commit -m "feat(web): add commerce and profile share previews"
```

---

## Task 7: Perkeras Universal Links/App Links dan lifecycle deep link

**Files:**
- Create: `flutter_app/lib/services/deep_link_router.dart`
- Create: `flutter_app/test/services/deep_link_router_test.dart`
- Modify: `flutter_app/lib/services/deep_link_service.dart`
- Create: `flutter_app/test/services/deep_link_service_test.dart`
- Modify: `app/.well-known/apple-app-site-association/route.ts`
- Create: `tests/deep-link-association.test.ts`
- Verify only: `app/.well-known/assetlinks.json/route.ts`
- Verify only: `flutter_app/android/app/src/main/AndroidManifest.xml`
- Verify only: `flutter_app/ios/Runner/Runner.entitlements`

- [ ] **Step 1: Tulis parser test yang gagal**

```dart
test('accepts official https hosts and ignores analytics query', () {
  final target = parseNataloDeepLink(
    Uri.parse('https://www.natalopetshop.com/feed/post-1?v=x&utm_source=wa'),
  );
  expect(target, const FeedPostDeepLink('post-1'));
});

test('rejects deceptive host and non-https scheme', () {
  expect(parseNataloDeepLink(Uri.parse(
      'https://www.natalopetshop.com.evil.test/feed/post-1')), isNull);
  expect(parseNataloDeepLink(Uri.parse(
      'http://www.natalopetshop.com/feed/post-1')), isNull);
});
```

- [ ] **Step 2: Tulis lifecycle test gagal**

Gunakan fake dispatcher/clock untuk mengunci:

- initial link saat navigator null masuk pending;
- pending diproses sekali setelah navigator siap;
- URI sama dari initial + stream dalam jendela dedupe hanya push sekali;
- URI berbeda tetap diproses;
- query `v`/UTM tidak membedakan target dedupe.

- [ ] **Step 3: Jalankan test dan pastikan merah**

Run: `flutter test test/services/deep_link_router_test.dart test/services/deep_link_service_test.dart`

Expected: FAIL.

- [ ] **Step 4: Ekstrak parser murni dan implementasikan pending queue**

Service harus menyimpan satu pending URI terbaru sampai navigator siap, lalu dipanggil dari lifecycle point setelah root navigator terpasang. Dedupe key memakai target ternormalisasi (`feed:post-1`, `product:slug`, `profile:username`) dengan window pendek, misalnya 2 detik. Jangan dedupe berdasarkan URL mentah.

Jangan mengubah behavior route yang sudah ada: video Feed tetap `openFeedPostSmart`, foto/carousel ke detail Postingan, produk fetch by slug, profil lowercase.

- [ ] **Step 5: Tambahkan `/feed/*` ke AASA dan test association**

Test source-level/handler-level harus memastikan AASA memuat `/feed/*`, `/products/*`, `/u/*`, Team ID + bundle ID benar; Asset Links memuat package `com.natalo.petshop` dan fingerprint production.

- [ ] **Step 6: Jalankan test dan analyzer**

Run: `flutter test test/services/deep_link_router_test.dart test/services/deep_link_service_test.dart`

Run: `npx tsx --test tests/deep-link-association.test.ts`

Run: `flutter analyze lib/services/deep_link_router.dart lib/services/deep_link_service.dart`

Expected: PASS/no issues.

- [ ] **Step 7: Commit**

```bash
git add flutter_app/lib/services/deep_link_router.dart flutter_app/lib/services/deep_link_service.dart flutter_app/test/services app/.well-known/apple-app-site-association/route.ts tests/deep-link-association.test.ts
git commit -m "fix(deep-link): queue and deduplicate public share links"
```

---

## Task 8: Verification, deployment order, dan device gate

**Files:**
- Modify if needed: `docs/superpowers/specs/2026-07-22-share-preview-deep-link-design.md`
- Create: `docs/qa/share-preview-deep-link-checklist.md`

- [ ] **Step 1: Jalankan regression test web terfokus**

Run:

```bash
npx tsx --test tests/share-version.test.ts tests/share-feed-data.test.ts tests/share-metadata.test.ts tests/share-og-security.test.ts tests/share-feed-card.test.ts tests/share-product-profile.test.ts tests/deep-link-association.test.ts
npx tsc --noEmit
npm run lint
```

Expected: seluruh test PASS, typecheck/lint exit 0.

- [ ] **Step 2: Jalankan regression test Flutter terfokus**

Run dari `flutter_app`:

```bash
flutter test test/services/share_link_builder_test.dart test/services/share_sheet_launcher_test.dart test/services/deep_link_router_test.dart test/services/deep_link_service_test.dart test/state/feed_store_share_test.dart test/models/public_profile_test.dart test/services/product_service_raw_test.dart
flutter analyze
```

Expected: seluruh test PASS dan analyzer tanpa error.

- [ ] **Step 3: Jalankan full suites**

Run root: `npm test`

Run `flutter_app`: `flutter test`

Expected: tidak ada failure baru. Test yang memang ditandai skip sebelumnya boleh tetap skip dan harus dicatat.

- [ ] **Step 4: Build web pada environment aman**

`npm run build` di repo ini juga menjalankan `prisma migrate deploy`. Jalankan hanya di CI/staging yang database targetnya sudah diverifikasi, bukan sembarang shell lokal.

Expected: Next.js build sukses; seluruh dynamic route dan OG route terdaftar.

- [ ] **Step 5: Deploy web lebih dulu dan validasi HTTP**

Untuk satu Feed video, Feed foto/carousel, produk, profil user, dan profil official:

- page HTTP 200 tanpa cookie;
- canonical benar;
- `og:image` absolut dan HTTP 200 `image/png`;
- image endpoint punya cache header;
- draft/deleted Feed HTTP 404/noindex;
- AASA/Asset Links HTTP 200, JSON, tanpa redirect pada apex dan `www`.

- [ ] **Step 6: Validasi crawler dan cache WhatsApp**

Gunakan URL `v` baru setelah perubahan objek. Test WhatsApp Android, WhatsApp Business smoke, dan WhatsApp iOS. Catat bahwa preview lama yang sudah cache bukan kegagalan implementasi jika URL sama.

- [ ] **Step 7: Build dan device-test Android**

Uji app terminated/background/foreground untuk Feed video, foto/carousel, produk, profil. Verifikasi satu tap menghasilkan satu route, back stack benar, dan app tidak terpasang membuka web.

Command dasar:

```text
adb shell am start -a android.intent.action.VIEW -d "https://www.natalopetshop.com/feed/<id>?v=<version>"
```

- [ ] **Step 8: Build dan device-test iOS/TestFlight**

Uji lifecycle yang sama. Simulator boleh untuk smoke, tetapi AASA final wajib di device/TestFlight. Perubahan Flutter pada queue/dedupe memerlukan build iOS baru.

- [ ] **Step 9: Review keamanan dan code changes**

Gunakan `security-auditor` pada OG URL validation/data exposure dan `review-code-changes` pada seluruh diff. Temuan P0/P1 harus ditutup sebelum merge; P2 harus diputuskan eksplisit.

- [ ] **Step 10: Dokumentasikan hasil QA dan commit**

```bash
git add docs/qa/share-preview-deep-link-checklist.md
git commit -m "docs(qa): record share preview device verification"
```

---

## Rollout Gate

1. Merge/deploy web share pages, metadata, OG endpoints, dan AASA.
2. Verifikasi public HTTP + crawler dengan URL yang belum cache.
3. Merge/build Flutter share builder dan deep-link lifecycle.
4. Internal Android test dan iOS TestFlight.
5. Rilis bertahap; monitor `og_image_render_failed`, `deep_link_failed`, dan share result.

## Rollback

- OG endpoint bermasalah: metadata kembali menunjuk raw image/fallback statis; halaman canonical tetap dipertahankan.
- Feed public page bermasalah: pertahankan route minimal + metadata aman, jangan redirect ke homepage generik.
- Flutter share regression: rollback launcher/builder ke commit sebelumnya; URL web tetap kompatibel.
- Deep-link lifecycle regression: rollback build mobile, jangan hapus AASA/Asset Links yang sudah stabil.
- Jangan mengembalikan generator produk lama dan endpoint produk baru secara bersamaan sebagai dua sumber permanen; pilih satu lewat revert terarah.
