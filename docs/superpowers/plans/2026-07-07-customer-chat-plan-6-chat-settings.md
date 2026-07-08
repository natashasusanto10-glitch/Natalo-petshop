# Customer Chat — Plan 6: NLCATTER Chat Settings (kill-switch + jam operasional)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Layar **owner-only "Pengaturan Chat"** di NLCATTER yang menulis dua dokumen kontrol di Firestore tokochat: `app_settings/chatConfig` (**kill-switch** `chatEnabled`) dan `app_settings/chatHours` (**jam operasional** per hari + pesan away). Menutup gap review B4/B5: sumber kill-switch tunggal (owner toggle langsung), penulis `chatHours` untuk auto-greeting/away & status online. Termasuk **seed awal** kedua dokumen.

**Architecture:** Owner menulis langsung `app_settings/chatConfig`/`chatHours` via SDK Firestore (rules **owner-write, staff-read** ditambahkan di Plan 1 Task 7). Proxy Natalo (Plan 2) **hanya membaca** dokumen ini (kill-switch `/api/chat/config`, status online, greeting/away). Tak ada mirror, tak ada endpoint tulis di Natalo — konsisten keputusan user 2026-07-07.

**Tech Stack:** Flutter, `cloud_firestore` (`app_settings/*`), `AuthProvider` (gating owner), token `AppColors`/`AppRadius`/`AppSpacing`/`AppText` + `GradientHeader` (repo NLCHAT), `flutter_test` (unit).

## Global Constraints

- Path relatif ke root repo **NLCHAT** (`C:/Users/USER/Desktop/NLCHAT`).
- **Owner-only:** layar & tombol tulis hanya untuk `userProfile?.isOwner == true`. Enforcement nyata = rules Plan 1 Task 7 (owner-write `app_settings/*`).
- **Token NLCATTER** (Roboto, `#0284C7`, `GradientHeader`, `bgScreen #F0F4F8`, `bgCard #FFFFFF`) — jangan dicampur token Natalo (memori `mockup-fidelity-per-app`).
- **Timezone WIB:** `chatHours.timezone = 'Asia/Jakarta'`; jam disimpan sebagai string `"HH:mm"` per hari (`mon..sun`), `null` = tutup seharian. Konsumen (proxy) yang mengonversi WIB.
- **Dependency:** Plan 1 Task 7 (rule `app_settings`) harus ada; proxy Plan 2 Task 3 membaca `chatConfig` (kill-switch) & (fix B3) menghitung status online dari `chatHours`.
- Skema `chatHours`/`chatConfig` = SATU sumber kebenaran, samakan dgn spec §4.5 & §11b (yang diperbarui di fix review).

---

## File Structure

- `lib/models/chat_settings.dart` — **create**: `ChatHours` (timezone, days map `{open,close}`, awayMessage), `ChatConfig` (chatEnabled) + `fromMap`/`toMap` + validasi.
- `lib/services/chat_settings_service.dart` — **create**: stream/get + tulis `app_settings/chatConfig` & `app_settings/chatHours`; `seedDefaults()`.
- `lib/screens/chat_settings_screen.dart` — **create**: layar owner (sakelar kill-switch + editor jam per hari + pesan away).
- `test/chat_settings_test.dart` — **create**: unit test parsing + validasi jam.
- Entry: tautkan dari menu owner (mis. `manage_users`/settings) — **modify** satu titik navigasi owner.

---

### Task 1: Model + validasi jam — TDD

**Files:**
- Test: `test/chat_settings_test.dart`
- Create: `lib/models/chat_settings.dart`

**Interfaces:**
- `ChatConfig.fromMap` → `chatEnabled` (default **true** bila absen — fail-open ON).
- `ChatHours.fromMap` → `timezone` (default `'Asia/Jakarta'`), `days: Map<String,{open,close}>` (`open/close` string `"HH:mm"` atau null), `awayMessage`.
- Murni: `isValidHhmm(s)`; `isOpenAt(hours, weekday, hhmm)` → bool (untuk uji logika buka/tutup; produksi dipakai proxy, tapi helper diuji di sini juga sebagai referensi).

- [ ] **Step 1: Test gagal** — parsing default (`chatEnabled` true saat absen; `timezone` default), `isValidHhmm` ("08:00" true, "24:10"/"8" false), `isOpenAt` (Senin 09:00 buka bila `mon:{open:'08:00',close:'21:00'}`; hari `null` → tutup).
- [ ] **Step 2: Jalankan — GAGAL.** `flutter test test/chat_settings_test.dart`.
- [ ] **Step 3: Implementasi model + helper.**
- [ ] **Step 4: Jalankan — LULUS.**
- [ ] **Step 5: Commit** — `git -C .../NLCHAT commit -m "feat(chat-settings): model ChatConfig/ChatHours + validasi jam"`.

---

### Task 2: Service tulis app_settings + seed

**Files:**
- Create: `lib/services/chat_settings_service.dart`

**Interfaces:**
- `streamConfig()`/`streamHours()`; `setChatEnabled(bool)`; `saveHours(ChatHours)`; `seedDefaults()` (tulis `chatConfig{chatEnabled:true}` + `chatHours` default Sen–Sab 08:00–21:00, Min tutup, awayMessage template `"Halo! Kami sedang di luar jam operasional ({jamBuka}–{jamTutup}). Pesanmu akan kami balas segera."`) — hanya bila dokumen belum ada.

- [ ] **Step 1: Implementasi** service (write `FirebaseFirestore.instance.doc('app_settings/chatConfig').set({...}, merge:true)` dst.). `seedDefaults` cek `exists` dulu (jangan timpa).
- [ ] **Step 2: Verifikasi** `flutter analyze` bersih.
- [ ] **Step 3: Commit** — `-m "feat(chat-settings): service tulis chatConfig/chatHours + seed default"`.

---

### Task 3: Layar "Pengaturan Chat" (owner-only)

**Files:**
- Create: `lib/screens/chat_settings_screen.dart`
- Modify: satu titik navigasi owner (mis. menu di `manage_users` atau home owner)

**Interfaces:**
- Consumes: Task 1–2, `AuthProvider` (gating), `GradientHeader`, token AppColors.

- [ ] **Step 1: Gating + header** — buka hanya bila `context.read<AuthProvider>().userProfile?.isOwner == true` (else pop + snack). `GradientHeader(overline:'CHAT', title:'Pengaturan Chat')`.
- [ ] **Step 2: Sakelar kill-switch** — `SwitchListTile` "Chat customer aktif" (`activeColor: AppColors.primary`) → `setChatEnabled(v)`; subtitle jelas ("Matikan untuk pemeliharaan — customer lihat 'Chat sedang dalam pemeliharaan'").
- [ ] **Step 3: Editor jam operasional** — daftar 7 hari (Sen–Min): tiap baris toggle "Buka" + dua time picker (buka/tutup, `showTimePicker` → simpan `"HH:mm"`), `null` saat toggle off. Field teks "Pesan di luar jam" (awayMessage). Tombol **Simpan** → `saveHours(...)` + snack. Validasi: `close>open` per hari.
- [ ] **Step 4: Seed on first open** — bila dokumen belum ada, panggil `seedDefaults()` lalu render nilai seed.
- [ ] **Step 5: Verifikasi manual** — toggle kill-switch → customer (Natalo) `AppChatButton` hilang + composer nonaktif; ubah jam → auto-greeting/away & status online mengikuti; non-owner tak bisa buka (rules tolak tulis).
- [ ] **Step 6: Commit** — `-m "feat(chat-settings): layar owner kill-switch + editor jam operasional"`.

---

## Definition of Done (Plan 6)

- [ ] Unit test model/validasi jam hijau.
- [ ] `flutter analyze` bersih.
- [ ] Owner bisa: toggle kill-switch (→ `app_settings/chatConfig.chatEnabled`) & atur jam/away (→ `app_settings/chatHours`); non-owner tak bisa (rules Plan 1 Task 7).
- [ ] Seed default tertulis bila dokumen belum ada; tak menimpa yang sudah ada.
- [ ] Token 100% NLCATTER; timezone `Asia/Jakarta`; jam `"HH:mm"`/null.

## Self-Review (penulis plan)

- **Menutup gap review:** B4 (editor jam operasional), B5 (penulis kill-switch = owner NLCATTER langsung, bukan mirror/PUT). ✓
- **Konsistensi:** proxy Plan 2 hanya BACA `chatConfig`/`chatHours`; rule owner-write ditambah Plan 1 Task 7; skema `chatHours` selaras auto-greeting/away (Plan 2) & status online (fix B3). ✓
- **Keamanan:** owner-only (UI + rules); tak menyentuh koleksi lain. ✓
- **Batas uji:** model/validasi unit; tulis Firestore & efek lintas-app diverifikasi manual.
