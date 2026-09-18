import { redirect } from "next/navigation";
import { getSession, type SessionPayload } from "@/lib/auth";

/**
 * Guard customer-only routes. Kalau belum login, redirect ke /member/login.
 *
 * `returnTo` opsional: path yang WAJIB dituju setelah login berhasil, lewat
 * `?redirect=` yang sudah dibaca + disanitasi (safeRedirect) di
 * app/member/login/page.tsx. Tanpa ini, login page default redirectTo="/" —
 * user checkout/lain yang kena guard ini akan dilempar ke Beranda setelah
 * login, bukan kembali ke halaman asal (ditemukan di alur checkout: guest
 * klik Checkout → /member/login tanpa returnTo → login sukses → Beranda,
 * bukan /checkout — padahal /checkout sendiri sudah punya fallback baca
 * sessionStorage kalau URL query kosong, jadi cukup sampai ke path-nya saja).
 */
export async function requireCustomerSession(
  returnTo?: string,
): Promise<SessionPayload> {
  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") {
    redirect(
      returnTo
        ? `/member/login?redirect=${encodeURIComponent(returnTo)}`
        : "/member/login",
    );
  }
  return session;
}

export async function requireAdminSession(): Promise<SessionPayload> {
  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") redirect("/admin/login");
  return session;
}
