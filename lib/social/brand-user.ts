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
 * Token placeholder untuk nama/username aktor di JUDUL/BODY notifikasi.
 *
 * KENAPA: judul notif ("X berkomentar", "X menyebut kamu") dulu memanggang
 * nama/username aktor jadi teks jadi → basi saat aktor ganti nama/username.
 * Kini judul disimpan dengan token ini; read path mengganti token dengan
 * nama/username LIVE terkini (in-app selalu sinkron). Push yang sudah terkirim
 * tetap snapshot (di-fill saat kirim) — tak bisa diubah, itu wajar.
 *
 * Pakai karakter Private Use Area (U+E000) supaya tak mungkin bentrok dgn
 * teks buatan user. Notif LAMA tak punya token → fill jadi no-op (tetap teks
 * lama; sinkron hanya berlaku maju/forward untuk notif baru).
 */
export const NOTIF_ACTOR_NAME_TOKEN = "actorName";
export const NOTIF_ACTOR_USERNAME_TOKEN = "actorUsername";

/**
 * Label nama & username aktor brand-safe untuk mengisi token judul notifikasi.
 * Admin → nama brand (dua-duanya). User biasa → nama asli / username; fallback
 * "Seseorang" bila kosong. [user] null (aktor terhapus) → "Seseorang".
 *
 *  - nameLabel dipakai judul jenis "X berkomentar / membalas / menyukai".
 *  - usernameLabel dipakai judul jenis "X menyebut kamu / posting baru".
 */
export function notificationActorLabels(
  user:
    | { role?: string | null; name?: string | null; username?: string | null }
    | null,
): { nameLabel: string; usernameLabel: string } {
  if (user && isAdminRole(user.role)) {
    return { nameLabel: OFFICIAL_BRAND_NAME, usernameLabel: OFFICIAL_BRAND_NAME };
  }
  const name = user?.name?.trim() || "";
  const username = user?.username?.trim() || "";
  return {
    nameLabel: name || "Seseorang",
    usernameLabel: username || name || "Seseorang",
  };
}

/** Ganti token nama/username aktor di [text] dengan label. Tanpa token → apa adanya. */
export function fillNotificationActorTokens(
  text: string,
  labels: { nameLabel: string; usernameLabel: string },
): string {
  if (!text) return text;
  return text
    .split(NOTIF_ACTOR_NAME_TOKEN)
    .join(labels.nameLabel)
    .split(NOTIF_ACTOR_USERNAME_TOKEN)
    .join(labels.usernameLabel);
}

/**
 * Resolve identitas aktor notifikasi LIVE saat baca (bukan snapshot).
 *
 * KENAPA: avatar & nama aktor di-simpan (denormalisasi) ke baris Announcement
 * saat notif dibuat. Kalau aktor lalu ganti/hapus foto profil, notif lama
 * memegang URL basi (bug "foto profil di notifikasi tak sinkron"). Helper ini
 * mengambil identitas terkini dari record User (via actorId) supaya selalu
 * sinkron, brand-safe (admin → nama brand + foto null lewat
 * [notificationActorFields]).
 *
 * Fallback ke [snapshot] bila:
 *  - [isAggregate] true → baris agregat like (avatar bertumpuk `actorAvatarUrls`)
 *    memang tak punya identitas aktor tunggal; jangan diisi satu avatar.
 *  - [actorId] null → notif lama (dibuat sebelum actorId ditulis).
 *  - [liveUser] null → user tak ditemukan (mis. akun dihapus).
 */
export function resolveNotificationActor(params: {
  actorId: string | null;
  isAggregate: boolean;
  snapshot: { actorName: string | null; actorAvatarUrl: string | null };
  liveUser:
    | { role: string | null; name: string | null; profilePhotoUrl: string | null }
    | null;
}): { actorName: string | null; actorAvatarUrl: string | null } {
  if (params.isAggregate) return params.snapshot;
  if (!params.actorId || !params.liveUser) return params.snapshot;
  return notificationActorFields(
    params.liveUser.role,
    params.liveUser.name,
    params.liveUser.profilePhotoUrl,
  );
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

/**
 * Foto avatar untuk baris notif LIKE agregat (avatar bertumpuk ala IG).
 * Brand-safe: liker akun ADMIN → foto null (di-DROP dari array, tak bocor;
 * array cuma berisi foto asli non-admin). Maks 3.
 */
export function topLikerAvatars(
  likers: Array<{ role: string | null | undefined; profilePhotoUrl: string | null | undefined }>,
): string[] {
  const out: string[] = [];
  for (const l of likers) {
    const photo = brandPhotoUrl(l.role, l.profilePhotoUrl);
    if (photo && photo.trim()) out.push(photo);
    if (out.length >= 3) break;
  }
  return out;
}
