// Guard auth SENGAJA dipindah ke tiap page.tsx di bawah app/akun/* (bukan di
// sini). Layout tidak menerima searchParams/pathname dari Next.js, jadi guard
// di level layout tidak pernah bisa mengirim returnTo yang presisi — dan
// karena layout dieksekusi lebih dulu dari page anaknya, guard generik di
// sini akan SELALU redirect duluan sebelum guard presisi di page manapun
// sempat jalan. Semua 6 page di bawah akun/* sudah self-guard dengan
// requireCustomerSession(returnTo) atau getSession()+redirect(returnTo)
// sendiri-sendiri — lihat hapus-akun, sesi-aktif, pengaturan/notifikasi,
// postingan-saya (+ [id], + [id]/edit). Kalau menambah page baru di bawah
// akun/*, WAJIB beri guard sendiri di page itu — jangan andalkan layout ini.
export default function AccountLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return children;
}
