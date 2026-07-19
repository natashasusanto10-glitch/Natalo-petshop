/**
 * Brand identity guard — akun ADMIN adalah brand tunggal "Natalo Petshop Official",
 * BUKAN akun sosial pemilik (Natasha). Nama asli + foto pribadi pemilik
 * TIDAK BOLEH bocor ke viewer lain di permukaan publik mana pun (feed
 * author, likers, komentar, daftar follow, notifikasi).
 *
 * SINGLE SOURCE OF TRUTH: setiap endpoint yang men-serialisasi identitas
 * user ke viewer lain WAJIB lewat helper ini. Menambah endpoint baru yang
 * mengembalikan {name, profilePhotoUrl} tanpa brandify = celah kebocoran.
 *
 * Catatan foto: kita kembalikan null (bukan URL logo) — klien (Flutter +
 * web) yang render aset logo brand lokal untuk akun official. Konsisten
 * dengan /api/u/[username] yang sudah null-kan foto official.
 */

export const OFFICIAL_BRAND_NAME = "Natalo Petshop Official";

/** Username kanonik brand — dipakai untuk deep-link /u/{handle}. */
export const OFFICIAL_BRAND_USERNAME = "natalopetshop";

export function isAdminRole(role: string | null | undefined): boolean {
  return role === "ADMIN";
}

/** Nama tampilan aman: brand untuk admin, nama asli untuk user biasa. */
export function brandDisplayName(
  role: string | null | undefined,
  name: string | null | undefined,
): string {
  return isAdminRole(role) ? OFFICIAL_BRAND_NAME : (name ?? "");
}

/** Foto aman: null untuk admin (klien render logo brand), foto asli untuk user. */
export function brandPhotoUrl(
  role: string | null | undefined,
  photoUrl: string | null | undefined,
): string | null {
  return isAdminRole(role) ? null : (photoUrl ?? null);
}

/**
 * Brandify satu objek user in-place-style (return objek baru). Menerima
 * bentuk apa pun yang punya {role?, name?, profilePhotoUrl?} dan
 * mengembalikan salinan dengan name+profilePhotoUrl yang aman. Field lain
 * (id, username, dsb.) dipertahankan.
 */
export function brandifyUser<
  T extends {
    role?: string | null;
    name?: string | null;
    profilePhotoUrl?: string | null;
  },
>(user: T): T {
  if (!isAdminRole(user.role)) return user;
  return {
    ...user,
    name: OFFICIAL_BRAND_NAME,
    profilePhotoUrl: null,
  };
}

/**
 * Field aktor terstruktur untuk baris notifikasi (Announcement.actorName/
 * actorAvatarUrl), brand-safe. Admin → nama brand + avatar null (client render
 * logo). User biasa → nama & foto asli.
 */
export function notificationActorFields(
  role: string | null | undefined,
  name: string | null | undefined,
  profilePhotoUrl: string | null | undefined,
): { actorName: string | null; actorAvatarUrl: string | null } {
  return {
    // name?.trim() || null → nama kosong/whitespace jatuh ke null (bukan
    // string kosong), supaya `likerName = actorName ?? "Seseorang"` bekerja
    // dan tak ada pesan berawalan spasi " menyukai ...".
    actorName: isAdminRole(role) ? OFFICIAL_BRAND_NAME : (name?.trim() || null),
    actorAvatarUrl: brandPhotoUrl(role, profilePhotoUrl),
  };
}

/**
 * Field aktor untuk baris notif LIKE. Baris agregat (>=2 liker, judul
 * "N orang menyukai...") kehilangan identitas aktor tunggal → null; like
 * TUNGGAL membawa aktor. Dipakai di kedua cabang (create + update batch)
 * supaya keputusan "agregat kehilangan aktor" tunggal & teruji.
 */
export function likeRowActorFields(
  isAggregate: boolean,
  actor: { actorName: string | null; actorAvatarUrl: string | null },
): { actorName: string | null; actorAvatarUrl: string | null } {
  return isAggregate ? { actorName: null, actorAvatarUrl: null } : actor;
}
