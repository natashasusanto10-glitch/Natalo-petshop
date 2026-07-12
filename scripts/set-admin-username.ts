/**
 * Set username kanonik "natalopetshop" untuk akun official (role ADMIN).
 *
 * Kenapa: akun official butuh username supaya bisa dituju deep-link
 * /u/{username} dan bisa di-tap/di-follow dari feed. Sebelumnya admin
 * dibuat tanpa username (admin-login upsert), jadi profilnya tak bisa
 * dibuka.
 *
 * Usage (local):  npx dotenv -e .env.local -- npx tsx scripts/set-admin-username.ts
 * Usage (prod):   npx dotenv -e .env       -- npx tsx scripts/set-admin-username.ts
 *
 * Idempotent — aman dijalankan berkali-kali. Kalau username sudah benar,
 * tidak melakukan apa-apa. Kalau username "natalopetshop" sudah dipakai
 * user NON-admin (bentrok), script berhenti dengan error tanpa mengubah
 * apa pun (biar tidak menabrak data user lain).
 */
import { prisma } from "@/lib/prisma";
import { OFFICIAL_BRAND_USERNAME } from "@/lib/social/brand-user";

async function main() {
  const admins = await prisma.user.findMany({
    where: { role: "ADMIN" },
    select: { id: true, name: true, username: true },
  });

  if (admins.length === 0) {
    console.log("[set-admin-username] Tidak ada user role ADMIN. Skip.");
    return;
  }

  // Cek bentrok: apakah username brand sudah dipakai user non-admin?
  const clash = await prisma.user.findUnique({
    where: { username: OFFICIAL_BRAND_USERNAME },
    select: { id: true, role: true },
  });
  if (clash && clash.role !== "ADMIN") {
    throw new Error(
      `[set-admin-username] Username "${OFFICIAL_BRAND_USERNAME}" sudah ` +
        `dipakai user non-admin (${clash.id}). Batal — selesaikan bentrok ` +
        `dulu secara manual.`,
    );
  }

  // Username unik → hanya SATU admin kanonik yang boleh pegang handle brand.
  // Prioritas: yang sudah punya handle ini (idempotent), lalu id="admin",
  // lalu admin pertama. Admin lain (kalau ada) dibiarkan — brand = 1 akun.
  const canonical =
    admins.find((a) => a.username === OFFICIAL_BRAND_USERNAME) ??
    admins.find((a) => a.id === "admin") ??
    admins[0];

  if (canonical.username === OFFICIAL_BRAND_USERNAME) {
    console.log(
      `[set-admin-username] ${canonical.id} sudah "${OFFICIAL_BRAND_USERNAME}". Tidak ada perubahan.`,
    );
  } else {
    await prisma.user.update({
      where: { id: canonical.id },
      data: {
        username: OFFICIAL_BRAND_USERNAME,
        usernameUpdatedAt: new Date(),
      },
    });
    console.log(
      `[set-admin-username] ${canonical.id} (${canonical.name}) → username ` +
        `"${OFFICIAL_BRAND_USERNAME}".`,
    );
  }

  if (admins.length > 1) {
    console.warn(
      `[set-admin-username] Ada ${admins.length} user ADMIN. Handle brand ` +
        `hanya di-set ke ${canonical.id}. Admin lain: ` +
        admins
          .filter((a) => a.id !== canonical.id)
          .map((a) => a.id)
          .join(", "),
    );
  }
  console.log("[set-admin-username] Selesai.");
}

main()
  .catch((err) => {
    console.error(err);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
