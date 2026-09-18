// Guard auth SENGAJA dipindah ke tiap page.tsx (bukan di sini) — sama alasan
// dengan app/akun/layout.tsx. Layout tidak menerima searchParams/pathname,
// dan dieksekusi sebelum page anaknya, jadi guard generik di sini akan
// SELALU redirect duluan dengan path tidak presisi sebelum guard presisi di
// notifications/[id]/page.tsx (returnTo ke pengumuman spesifik) sempat jalan.
// Kedua page anak (list + [id]) sudah self-guard sendiri-sendiri.
export default function NotificationsLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return children;
}
