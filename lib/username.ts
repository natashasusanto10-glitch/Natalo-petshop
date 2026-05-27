/**
 * Username validation + reservation helper.
 *
 * Rules (IG/TikTok-style):
 *   - 3-30 karakter
 *   - lowercase huruf a-z + angka 0-9 + underscore `_` + period `.`
 *   - tidak boleh leading/trailing `.`
 *   - tidak boleh `..` berurutan
 *   - reserved keywords blocked (admin, natalo, dst)
 *
 * 30-day reservation: handle lama yang baru diganti masih nge-block
 * user lain untuk claim — anti @mention hijack. Setelah 30 hari,
 * handle release.
 */
import { prisma } from "@/lib/prisma";

/** Hari reservasi handle lama setelah user ganti. */
export const USERNAME_RESERVATION_DAYS = 30;

export const USERNAME_MIN_LENGTH = 3;
export const USERNAME_MAX_LENGTH = 30;

/**
 * Reserved usernames — gak boleh dipake user.
 * Pertimbangan:
 *  - System routes (admin, api, auth, login, register, me, you)
 *  - Brand (natalo, support, staff, official, help, contact)
 *  - Generic surfaces (feed, cart, checkout, home, search, profile,
 *    settings, wishlist, order, voucher, points)
 *  - Common confusing handles (everyone, all, anonymous, null, undefined,
 *    deleted, system, bot)
 */
const RESERVED_USERNAMES = new Set<string>([
  "admin", "administrator", "root", "superuser",
  "api", "auth", "login", "logout", "register", "signup", "signin",
  "me", "you", "we", "us", "they",
  "natalo", "natalopetshop", "support", "staff", "official", "help",
  "contact", "team",
  "feed", "cart", "checkout", "home", "search", "profile", "settings",
  "wishlist", "favorites", "order", "orders", "voucher", "vouchers",
  "points", "loyalty", "reward", "rewards",
  "everyone", "all", "anonymous", "anon", "null", "undefined",
  "deleted", "system", "bot",
  "post", "posts", "comment", "comments", "like", "likes", "share",
  "user", "users", "account", "accounts",
  "category", "categories", "product", "products",
  "blog", "about", "tos", "privacy", "terms",
]);

export type UsernameValidationError =
  | { code: "TOO_SHORT"; message: string }
  | { code: "TOO_LONG"; message: string }
  | { code: "INVALID_CHARS"; message: string }
  | { code: "LEADING_PERIOD"; message: string }
  | { code: "TRAILING_PERIOD"; message: string }
  | { code: "CONSECUTIVE_PERIODS"; message: string }
  | { code: "RESERVED"; message: string };

/**
 * Validate format username (sebelum cek DB uniqueness). Input
 * di-lowercase sebelum check supaya konsisten. Return null kalau
 * valid, atau error code + message kalau invalid.
 */
export function validateUsernameFormat(
  raw: string,
): UsernameValidationError | null {
  const username = raw.trim().toLowerCase();

  if (username.length < USERNAME_MIN_LENGTH) {
    return {
      code: "TOO_SHORT",
      message: `Username minimal ${USERNAME_MIN_LENGTH} karakter.`,
    };
  }
  if (username.length > USERNAME_MAX_LENGTH) {
    return {
      code: "TOO_LONG",
      message: `Username maksimal ${USERNAME_MAX_LENGTH} karakter.`,
    };
  }
  // Allowed chars: a-z, 0-9, `_`, `.`
  if (!/^[a-z0-9_.]+$/.test(username)) {
    return {
      code: "INVALID_CHARS",
      message:
        "Hanya boleh huruf kecil, angka, underscore (_), dan titik (.).",
    };
  }
  if (username.startsWith(".")) {
    return {
      code: "LEADING_PERIOD",
      message: "Username tidak boleh diawali dengan titik.",
    };
  }
  if (username.endsWith(".")) {
    return {
      code: "TRAILING_PERIOD",
      message: "Username tidak boleh diakhiri dengan titik.",
    };
  }
  if (username.includes("..")) {
    return {
      code: "CONSECUTIVE_PERIODS",
      message: "Username tidak boleh punya dua titik berurutan.",
    };
  }
  if (RESERVED_USERNAMES.has(username)) {
    return {
      code: "RESERVED",
      message: "Username ini sudah disediakan sistem. Coba yang lain.",
    };
  }

  return null;
}

/**
 * Normalize input → lowercase + trim. Caller WAJIB pakai ini sebelum
 * write ke DB / compare. Konsisten dengan format validation.
 */
export function normalizeUsername(raw: string): string {
  return raw.trim().toLowerCase();
}

export type UsernameAvailabilityResult =
  | { available: true }
  | { available: false; reason: "TAKEN" | "RESERVED" };

/**
 * Cek apakah username available — di-DB tidak ada user current
 * yang pake, dan tidak ada history reservation aktif (within 30
 * days) dari user lain.
 *
 * `excludeUserId` di-pass dari endpoint set-username supaya cek
 * tidak nge-konflik dengan handle current user sendiri (user A bisa
 * "set ulang" ke handle yang sama).
 */
export async function checkUsernameAvailability(
  username: string,
  excludeUserId?: string,
): Promise<UsernameAvailabilityResult> {
  const normalized = normalizeUsername(username);

  // 1. Cek current owner — kalau ada user lain yang sedang pakai.
  const owner = await prisma.user.findUnique({
    where: { username: normalized },
    select: { id: true },
  });
  if (owner && owner.id !== excludeUserId) {
    return { available: false, reason: "TAKEN" };
  }

  // 2. Cek reservasi history aktif. UserA pernah pake handle,
  // kemudian ganti, handle lama nge-reserve 30 hari. UserB gak boleh
  // claim selama window itu. Tapi UserA sendiri boleh re-claim
  // handle lama-nya kalau mau (excludeUserId match).
  const now = new Date();
  const reservation = await prisma.usernameHistory.findFirst({
    where: {
      username: normalized,
      reservedUntil: { gt: now },
      ...(excludeUserId ? { userId: { not: excludeUserId } } : {}),
    },
    select: { id: true },
  });
  if (reservation) {
    return { available: false, reason: "RESERVED" };
  }

  return { available: true };
}

/**
 * Public profile resolution — resolve username string ke User row.
 * Dipakai oleh /api/u/[username] + /u/[username] page untuk public
 * profile lookup.
 *
 * Lookup order:
 *   1. User.username = X (current owner) — most common.
 *   2. UsernameHistory.username = X dengan reservedUntil > NOW
 *      → anti-broken-link selama 30 hari grace period. User A ganti
 *        handle dari `asiong` → `asiong2`, link lama `/u/asiong`
 *        tetap resolve ke User A selama window 30 hari.
 *      → setelah grace habis, kalau User B claim `asiong`, link
 *        mengarah ke User B (step 1 match).
 *
 * Return null kalau tidak ada match — caller render 404.
 */
export async function resolveUserByUsername(
  rawUsername: string,
): Promise<{
  id: string;
  name: string;
  username: string | null;
  profilePhotoUrl: string | null;
  bio: string | null;
  followersCount: number;
  followingCount: number;
  createdAt: Date;
} | null> {
  const normalized = normalizeUsername(rawUsername);
  if (normalized.length === 0) return null;

  // Step 1: current owner
  const current = await prisma.user.findUnique({
    where: { username: normalized },
    select: {
      id: true,
      name: true,
      username: true,
      profilePhotoUrl: true,
      bio: true,
      followersCount: true,
      followingCount: true,
      createdAt: true,
    },
  });
  if (current) return current;

  // Step 2: history reservation grace period
  const now = new Date();
  const reservation = await prisma.usernameHistory.findFirst({
    where: {
      username: normalized,
      reservedUntil: { gt: now },
    },
    orderBy: { createdAt: "desc" },
    select: {
      user: {
        select: {
          id: true,
          name: true,
          username: true,
          profilePhotoUrl: true,
          bio: true,
          followersCount: true,
          followingCount: true,
          createdAt: true,
        },
      },
    },
  });
  return reservation?.user ?? null;
}

/**
 * Set/change username untuk user. Atomik dalam transaction:
 *   1. Validasi format (di caller, bukan disini)
 *   2. Validasi availability
 *   3. Insert UsernameHistory row untuk handle lama (kalau ada)
 *   4. Update User.username + usernameUpdatedAt
 *
 * Return updated user.username atau throw ApiException kalau gagal.
 */
export async function setUserUsername(
  userId: string,
  newUsername: string,
): Promise<{ username: string }> {
  const normalized = normalizeUsername(newUsername);

  return prisma.$transaction(async (tx) => {
    const user = await tx.user.findUnique({
      where: { id: userId },
      select: { id: true, username: true },
    });
    if (!user) {
      throw new Error("USER_NOT_FOUND");
    }

    // No-op kalau sama dengan current (idempotent).
    if (user.username === normalized) {
      return { username: normalized };
    }

    // Availability check INSIDE transaction supaya race-safe.
    // Edge case: 2 user concurrent set username sama, transaction
    // isolation level Postgres default = READ COMMITTED. Unique
    // constraint di-DB level guarantee 1 winner. Kita check dulu
    // untuk error message yang user-friendly.
    const owner = await tx.user.findUnique({
      where: { username: normalized },
      select: { id: true },
    });
    if (owner && owner.id !== userId) {
      throw new Error("USERNAME_TAKEN");
    }
    const now = new Date();
    const reservation = await tx.usernameHistory.findFirst({
      where: {
        username: normalized,
        reservedUntil: { gt: now },
        userId: { not: userId },
      },
      select: { id: true },
    });
    if (reservation) {
      throw new Error("USERNAME_RESERVED");
    }

    // Reserve handle lama (kalau user pernah punya username).
    if (user.username) {
      const reservedUntil = new Date(
        now.getTime() + USERNAME_RESERVATION_DAYS * 24 * 60 * 60 * 1000,
      );
      await tx.usernameHistory.create({
        data: {
          userId,
          username: user.username,
          reservedUntil,
        },
      });
    }

    // Update user.
    await tx.user.update({
      where: { id: userId },
      data: {
        username: normalized,
        usernameUpdatedAt: now,
      },
    });

    return { username: normalized };
  });
}
