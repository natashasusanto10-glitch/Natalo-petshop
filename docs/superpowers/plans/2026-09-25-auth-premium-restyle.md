# Auth Premium Restyle — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle halaman member login & register sesuai mockup premium yang disetujui (`C:\Users\USER\Desktop\natalo-auth-mockup.html`), lengkap dengan sistem motion, state error/loading yang accessible, dan halaman `/member/login-otp` baru agar tombol "Masuk dengan OTP WhatsApp" fungsional.

**Architecture:** CSS premium (aurora, input melayang, CTA gradien, motion tokens) hidup sebagai satu seksi `.auth-*` di `app/globals.css`; kedua halaman direwrite JSX-nya dengan logika state/fetch TIDAK disentuh. Halaman OTP login baru mengkonsumsi API yang sudah ada (`/api/auth/member-login-otp/request` + `/verify`) dan meniru pola submit/redirect halaman login password.

**Tech Stack:** Next.js 16 App Router (client components), Tailwind CSS v4 (CSS-first `@theme`, token `--color-natalo-*` sudah ada), Nunito (identitas situs, tidak diubah).

**Spec:** `C:\Users\USER\Desktop\natalo-auth-mockup.html` (disetujui user + penilaian 9.2/10) + keputusan terkunci: tanpa tombol Google; field email & HP terpisah + konfirmasi password dipertahankan (backend-compliant); CTA natalo-700 sentence case; font Nunito.

## Global Constraints

- Input: tinggi 52px, font 16px (anti auto-zoom iOS), radius 14px, permukaan putih + border `#e3e8f0` + micro-shadow, focus glow `rgba(20,62,126,.09)`.
- CTA: 52px, gradien `linear-gradient(180deg,#1d529f,#143e7e)`, sentence case, spinner loading 0.7s linear.
- Motion: easing global `cubic-bezier(0.25,1,0.5,1)`; entrance fade-up 320ms stagger 40ms; press scale 0.98 (120ms); HANYA `transform`/`opacity`; hover lift di-guard `@media (hover:hover)`; hormati `prefers-reduced-motion`.
- Error: `role="alert"` + fokus pindah ke field invalid pertama. Notice sukses: `role="status"`.
- Placeholder `#8e9bb0`; link tap area ≥ 32px; override `input:-webkit-autofill` fill putih.
- LOGIKA JANGAN DIUBAH: `safeRedirect`, handler submit/fetch, payload, cooldown, unlockEdit, notice `registered=1` — hanya JSX/CSS yang berubah (kecuali penambahan fokus-after-error dan tombol sekunder).
- `OperatingHoursCard` di register DIPERTAHANKAN (konten trust; tidak ada di mockup karena mockup dipangkas).
- Header auth: back button SAJA (tanpa judul) — semua halaman auth kini punya h1 in-page sendiri (login/register baru, forgot/reset sudah ada — terverifikasi).

## Review Focus

1. **Round-trip `redirect` hilang** — login → login-otp → sukses harus tetap mendarat ke `?redirect=…` asal; smoke test dengan `?redirect=%2Fmember%2Forders`.
2. **Autofill kuning iOS/Chrome menabrak desain** — override `-webkit-autofill` wajib mengikuti fill putih baru; cek manual di Chrome.
3. **Pesan error API OTP (429/anti-enumeration) harus tampil verbatim** di box error, bukan ditelan generic.
4. **Heading ganda** — header h1 dihapus untuk SEMUA path auth (forgot/reset terverifikasi punya h1 sendiri); kalau ada path auth baru tanpa h1, jangan masuk AUTH_PATHS.
5. **Touch devices** — hover lift CTA tidak boleh nempel setelah tap (guard `@media (hover:hover)`).

---

### Task 1: Seksi CSS "Auth premium" di globals.css

**Files:**
- Modify: `app/globals.css` (sisipkan setelah blok `.apple-reveal` / sebelum `@keyframes nat-content-fade-in`, ±baris 890)

**Interfaces:**
- Produces (dipakai Task 3–5): `.auth-aurora`, `.auth-rise`, `.auth-rise-d1`, `.auth-rise-d2`, `.auth-input`, `.auth-cta`, `.auth-cta-secondary`, `.auth-spinner`

- [ ] **Step 1: Sisipkan seksi CSS**

```css
/* ===== Auth premium — login/register/login-otp member =====
   Bahasa: aurora background → permukaan putih → input melayang → CTA
   gradien. Semua animasi transform/opacity saja (kompositor, 60fps). */
:root {
  --nat-auth-ease: cubic-bezier(0.25, 1, 0.5, 1);
}
.auth-aurora {
  background:
    radial-gradient(900px 480px at 88% -8%, rgba(20, 62, 126, 0.09), transparent 62%),
    radial-gradient(720px 420px at -6% 4%, rgba(20, 62, 126, 0.05), transparent 58%),
    #f6f8fc;
}
@keyframes nat-auth-rise {
  from { opacity: 0; transform: translateY(14px); }
}
.auth-rise { animation: nat-auth-rise 0.32s var(--nat-auth-ease) backwards; }
.auth-rise-d1 { animation-delay: 40ms; }
.auth-rise-d2 { animation-delay: 80ms; }

.auth-input {
  display: block; width: 100%; height: 52px; padding: 0 16px;
  font-family: inherit; font-size: 16px; color: #0f172a; background: #fff;
  border: 1px solid #e3e8f0; border-radius: 14px; outline: none;
  box-shadow: 0 1px 2px rgba(15, 23, 42, 0.04);
  transition: border-color 0.15s var(--nat-auth-ease), box-shadow 0.15s var(--nat-auth-ease);
}
.auth-input::placeholder { color: #8e9bb0; }
.auth-input:focus {
  border-color: #93b4e3;
  box-shadow: 0 0 0 4px rgba(20, 62, 126, 0.09), 0 1px 2px rgba(15, 23, 42, 0.04);
}
.auth-input:disabled { opacity: 0.55; cursor: not-allowed; }
/* Autofill Chrome/Safari — paksa fill putih menyatu dengan permukaan input. */
input.auth-input:-webkit-autofill,
input.auth-input:-webkit-autofill:hover,
input.auth-input:-webkit-autofill:focus {
  -webkit-box-shadow: 0 0 0 1000px #ffffff inset, 0 1px 2px rgba(15, 23, 42, 0.04);
  -webkit-text-fill-color: #0f172a;
  caret-color: #0f172a;
  transition: background-color 9999s ease-out;
}

.auth-cta {
  height: 52px; border: none; border-radius: 14px; cursor: pointer; color: #fff;
  font-family: inherit; font-size: 15px; font-weight: 800;
  background: linear-gradient(180deg, #1d529f 0%, #143e7e 100%);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.16),
    0 10px 22px -6px rgba(20, 62, 126, 0.45), 0 2px 6px rgba(20, 62, 126, 0.2);
  display: inline-flex; align-items: center; justify-content: center; gap: 8px;
  transition: box-shadow 0.15s var(--nat-auth-ease), transform 0.12s var(--nat-auth-ease),
    opacity 0.15s var(--nat-auth-ease);
}
@media (hover: hover) {
  .auth-cta:hover {
    transform: translateY(-1px);
    box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.16),
      0 14px 28px -6px rgba(20, 62, 126, 0.52), 0 3px 8px rgba(20, 62, 126, 0.22);
  }
}
.auth-cta:active { transform: scale(0.98) translateY(0); }
.auth-cta:disabled { cursor: not-allowed; opacity: 0.85; transform: none; }

.auth-cta-secondary {
  height: 50px; border-radius: 14px; cursor: pointer; background: #fff;
  border: 1.5px solid #dbe1ea; color: #0f172a; font-family: inherit;
  font-size: 14.5px; font-weight: 800; text-decoration: none;
  box-shadow: 0 1px 2px rgba(15, 23, 42, 0.04);
  display: inline-flex; align-items: center; justify-content: center; gap: 10px;
  transition: border-color 0.15s var(--nat-auth-ease), background 0.15s var(--nat-auth-ease);
}
@media (hover: hover) {
  .auth-cta-secondary:hover { border-color: #25d366; background: #f0fdf4; }
}
.auth-cta-secondary svg { color: #25d366; flex-shrink: 0; }

.auth-spinner {
  width: 16px; height: 16px; flex-shrink: 0;
  border: 2px solid rgba(255, 255, 255, 0.35); border-top-color: #fff;
  border-radius: 999px; animation: nat-auth-spin 0.7s linear infinite;
}
@keyframes nat-auth-spin { to { transform: rotate(360deg); } }

@media (prefers-reduced-motion: reduce) {
  .auth-rise { animation: none; }
  .auth-cta, .auth-cta-secondary, .auth-input { transition: none; }
}
```

- [ ] **Step 2: Verifikasi statis**

Run: `grep -c "auth-aurora\|auth-cta\|auth-input\|nat-auth-rise" app/globals.css`
Expected: ≥ 8 kemunculan.

---

### Task 2: PasswordInput — prop `id` + hover mata brand

**Files:**
- Modify: `components/PasswordInput.tsx:5-15` (props type), `:54-75` (input + tombol mata)

**Interfaces:**
- Produces: `PasswordInput` menerima `id?: string` → diteruskan ke `<input id>` (dipakai Task 3–4 untuk `htmlFor` label + focus-after-error). Komponen lain yang memakai PasswordInput (forgot/reset password) tidak berubah perilaku (prop opsional).

- [ ] **Step 1: Tambah `id` ke props type dan teruskan ke input**

```tsx
type PasswordInputProps = {
  id?: string; // ← TAMBAHAN: untuk label htmlFor + focus management
  value?: string;
  // ...prop lain tidak berubah
};
```
Dan di destructure + `<input id={id} ...>`.

- [ ] **Step 2: Selaraskan warna hover/active mata ke brand**

Ganti `text-[#999] ... hover:text-[#1E88E5] active:text-[#1E88E5]` → `text-[#94a3b8] ... hover:text-[#143e7e] active:text-[#143e7e]`.

- [ ] **Step 3: Typecheck**

Run: `npx tsc --noEmit`
Expected: PASS (prop opsional, tidak ada pemanggil yang rusak).

---

### Task 3: Restyle `app/member/login/page.tsx`

**Files:**
- Modify: `app/member/login/page.tsx` (JSX return + 2 helper kecil; state/fetch/logika TIDAK berubah)

**Interfaces:**
- Consumes: `.auth-*` (Task 1), `PasswordInput id` (Task 2)
- Produces: link sekunder → `/member/login-otp?redirect=…` (dibangun di Task 5)

- [ ] **Step 1: Tambah helper fokus setelah state**

```tsx
function focusFirstInvalid() {
  document.getElementById(identifier ? "auth-password" : "auth-identifier")?.focus();
}
```
Panggil di `handleSubmit` sebelum tiap `return` pada jalur `!res.ok` (setelah `setError`).

- [ ] **Step 2: Rewrite JSX return**

Struktur: wrapper `auth-aurora min-h-[calc(100svh-60px)] px-4 pb-10 pt-8 md:py-12` → kontainer `mx-auto w-full max-w-sm` →
1. `section.auth-rise` — logo tile putih `h-16 w-16 rounded-[20px] shadow-[0_10px_24px_-8px_rgba(20,62,126,0.22)] ring-1 ring-natalo-700/10` berisi `<Image src="/icons/icon-192x192.png" width={44} height={44} className="h-11 w-11 rounded-[12px]">`; h1 `text-[26px] font-black tracking-tight text-gray-950` "Selamat Datang Kembali!"; sub `text-[15px] text-gray-500` "Masuk untuk melanjutkan belanja kebutuhan hewan kesayanganmu."
2. Notice `registered=1`: `role="status"` + `auth-rise`, box hijau lembut.
3. `form.auth-rise.auth-rise-d1.mt-7.flex.flex-col.gap-4`:
   - Label `text-[13px] font-bold text-gray-700` + `htmlFor="auth-identifier"`; input `id="auth-identifier"` `className="auth-input"` `placeholder="Contoh: 08123456789 / nama@email.com"`.
   - Baris label Password + link "Lupa password?" (`py-2 px-0.5 text-xs font-bold text-natalo-700` — tap area ≥32px); `<PasswordInput id="auth-password" className="auth-input" ...>`.
   - Error: `role="alert"` box merah lembut `rounded-xl border border-red-100 bg-red-50 px-4 py-3 text-sm font-semibold text-red-600`.
   - CTA submit `className="auth-cta w-full"`: loading → `<span className="auth-spinner" aria-hidden /> Memproses…`, idle → "Masuk".
   - Divider: `<span className="h-px flex-1 bg-gray-200" /> atau masuk lebih cepat <span ... />` (`text-xs font-semibold text-gray-400`).
   - Sekunder: `<Link href={"/member/login-otp?redirect=" + encodeURIComponent(redirectTo)} className="auth-cta-secondary w-full">` + ikon WhatsApp SVG (path dari mockup, `width={18} height={18}` aria-hidden) + "Masuk dengan OTP WhatsApp".
4. Footer `auth-rise auth-rise-d2 mt-6 text-center text-sm text-gray-500`: "Belum punya akun? Daftar gratis" (link `text-natalo-700 font-extrabold`).

HAPUS: card nested "Akun member Natalo", sub-line footer kedua. H1 header duplikat menghilang di Task 6.

- [ ] **Step 3: Typecheck + smoke grep**

Run: `npx tsc --noEmit && grep -c "auth-aurora\|auth-input\|auth-cta" app/member/login/page.tsx`
Expected: PASS, count ≥ 5.

---

### Task 4: Restyle `app/member/register/page.tsx`

**Files:**
- Modify: `app/member/register/page.tsx` (JSX + helper fokus; logika OTP/cooldown/unlockEdit TIDAK berubah)

**Interfaces:**
- Consumes: `.auth-*` (Task 1), `PasswordInput id` (Task 2)
- Produces: id field `reg-name|reg-email|reg-phone|reg-password|reg-confirm|reg-otp` untuk focus management

- [ ] **Step 1: Helper fokus**

```tsx
function focusFirstInvalid(sent: boolean) {
  const id = !name ? "reg-name" : !email ? "reg-email" : !phone ? "reg-phone"
    : !password ? "reg-password" : !confirmPassword ? "reg-confirm"
    : sent ? "reg-otp" : "reg-name";
  document.getElementById(id)?.focus();
}
```
Panggil setelah `setError` pada validasi mismatch/OTP dan jalur `!res.ok`.

- [ ] **Step 2: Rewrite JSX**

Sama seperti Task 3 (aurora, logo tile, h1 "Mulai Langkahmu!", sub "Daftar sekarang dan nikmati voucher promo khusus member baru."), form `auth-rise auth-rise-d1` berisi field Nama/Email/No. HP/Password(+helper "Minimal 8 karakter.")/Konfirmasi — semua `className="auth-input"` + id `reg-*`; mismatch confirm tetap menandai border merah via kelas kondisional Tailwind di atas `auth-input` (append `border-red-300` saat mismatch).
- Info OTP di TENGAH form DIBUANG → pill `otp-note` DI BAWAH CTA: `rounded-xl border border-[#e2e9f4] bg-[#f1f5fb] px-3 py-2.5 text-xs leading-relaxed text-slate-600`.
- CTA: "Kirim kode OTP" → loading spinner → otpSent: "Verifikasi & Daftar"; disabled tetap `loading || (confirmPassword && mismatch)`.
- Blok OTP saat `otpSent`: kartu putih `rounded-2xl border border-[#dbe7f7] bg-white p-4 shadow-[0_1px_2px_rgba(15,23,42,0.04)]`; input `id="reg-otp"` `auth-input text-center text-lg font-black tracking-[0.35em]`; tombol "Kirim ulang OTP (Xs)" + "Ubah data" gaya link natalo-700.
- Benefits box → satu baris: "Gratis — kumpulkan poin loyalty & harga khusus member." (`auth-rise auth-rise-d2 mt-6 text-center text-xs text-gray-500`).
- Footer "Sudah punya akun? Masuk" + `OperatingHoursCard className="mt-6"` DIPERTAHANKAN.

- [ ] **Step 3: Typecheck + smoke grep**

Run: `npx tsc --noEmit && grep -c "reg-name\|reg-otp\|auth-input" app/member/register/page.tsx`
Expected: PASS, count ≥ 8.

---

### Task 5: Halaman BARU `app/member/login-otp/page.tsx`

**Files:**
- Create: `app/member/login-otp/page.tsx`

**Interfaces:**
- Consumes: API `POST /api/auth/member-login-otp/request` `{phone}` → `{ok, message}` / `{error}`; `POST /api/auth/member-login-otp/verify` `{phone, otp}` → `{ok, role, token, user}` (set cookie). Respons verify mirror `member-login` → parse sama dengan login page.
- Consumes: `mergeFromServer`, `dispatchAuthUpdated` dari `@/lib/cart`; `safeRedirect` pola login; `.auth-*` (Task 1)
- Produces: rute tujuan tombol sekunder login (Task 3); didaftarkan di AUTH_PATHS (Task 6)

- [ ] **Step 1: Tulis halaman (client component)**

State: `redirectTo`, `phone`, `otp`, `step: "phone" | "otp"`, `notice`, `error`, `loading`, `resendCooldown` (mulai 30 setelah OTP terkirim, interval 1s). `safeRedirect` disalin dari login page (dengan komentar backslash). Submit phone: `POST request` → ok → `setStep("otp")` + notice `data.message` + cooldown; error → error box + fokus `otp-phone`. Submit verify: `POST verify` → ok → `mergeFromServer().catch(() => {})` + `dispatchAuthUpdated()` + `router.replace(redirectTo)` + `router.refresh()`; error → box + fokus `reg-otp` analog (`login-otp` id).
JSX: `auth-aurora` + logo tile + h1 "Masuk dengan OTP" + sub "Kami kirim kode 6 digit ke WhatsApp kamu."; step phone: input `id="otp-phone"` `type="tel" autoComplete="tel"` `auth-input` + CTA "Kirim kode OTP"; step otp: ringkasan nomor + input `id="login-otp-code"` `inputMode="numeric" maxLength={6}` `auth-input text-center text-lg font-black tracking-[0.35em]` + CTA "Verifikasi & Masuk" + tombol link "Kirim ulang OTP (Xs)" (disabled saat cooldown) + "Ubah nomor" (kembali ke step phone, reset otp); divider + link "Masuk dengan password" → `/member/login?redirect=…`. Semua box notice/error + CTA mengikuti Task 3. Entrance: `auth-rise` (+d1 form, +d2 footer).

- [ ] **Step 2: Typecheck**

Run: `npx tsc --noEmit` — Expected: PASS.

---

### Task 6: Header — auth branch tanpa judul + daftar login-otp

**Files:**
- Modify: `components/Header.tsx:18-24` (AUTH_PATHS) dan `:197-231` (branch isAuthPage)

- [ ] **Step 1: Daftarkan rute OTP + perbarui komentar**

```tsx
// Halaman auth (login / daftar / OTP login / lupa-reset password) — header
// dirender dalam variant minimal: back button SAJA. Judul h1 kini milik
// halaman (Selamat Datang Kembali! dll) — sekaligus memperbaiki hierarki
// heading yang sebelumnya ganda. Value tetap disimpan sebagai fallback.
const AUTH_PATHS: Record<string, string> = {
  "/member/login": "Masuk",
  "/member/register": "Daftar Member",
  "/member/login-otp": "Masuk dengan OTP",
  "/member/forgot-password": "Lupa Password",
  "/member/reset-password": "Reset Password",
};
```

- [ ] **Step 2: Hapus `<h1>{authTitle}</h1>` dari branch isAuthPage**

Ganti dengan spacer kosong; susunan: back button (kiri) + `<span aria-hidden className="h-10 w-10 shrink-0" />` (kanan). `authTitle` tetap dipakai untuk derivasi `isAuthPage` sehingga tidak ada unused var.

- [ ] **Step 3: Typecheck**

Run: `npx tsc --noEmit` — Expected: PASS.

---

### Task 7: Verifikasi penuh + commit lokal

- [ ] **Step 1: Lint types & test suite**

Run: `npx tsc --noEmit && npm test`
Expected: PASS semua (±808 test; tidak ada test yang menyentuh styling halaman auth).

- [ ] **Step 2: Build produksi**

Run: `npm run build` — Expected: sukses tanpa error type.

- [ ] **Step 3: Smoke lokal**

Run: `npm run start -- -p 3100` (background) lalu:
```bash
curl -s http://localhost:3100/member/login | grep -o "Selamat Datang Kembali" | head -1
curl -s http://localhost:3100/member/register | grep -o "Mulai Langkahmu" | head -1
curl -s "http://localhost:3100/member/login-otp?redirect=%2Fmember%2Forders" | grep -o "Masuk dengan OTP" | head -1
```
Expected: ketiganya tercetak. Matikan server (`taskkill //F //T //PID <pid>`) — JANGAN biarkan proses yatim.

- [ ] **Step 4: Commit lokal (TANPA push)**

```bash
git add app/globals.css components/PasswordInput.tsx components/Header.tsx app/member/login/page.tsx app/member/register/page.tsx app/member/login-otp/ docs/superpowers/plans/2026-09-25-auth-premium-restyle.md
git commit -m "feat(auth): restyle premium login & register + halaman OTP login"
```
Push + deploy Vercel MENUNGGU perintah eksplisit user.

- [ ] **Step 5: Review akhir**

Baca ulang `git diff` fokus pada: logika lama tidak berubah (safeRedirect, payload fetch, cooldown), tidak ada id ganda per halaman, reduced-motion block hadir, `role="alert"`/`role="status"` benar, semua link redirect di-encode. Laporkan hasil + catatan deviasi ke user.
