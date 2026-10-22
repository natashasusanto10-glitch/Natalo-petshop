"use client";

// Setelan chat (aktif/mati + jam buka) dibaca dari Firestore di balik
// /api/chat/config — tiap panggilan = 2 baca dokumen. Hasilnya disimpan di
// sessionStorage 5 menit supaya pindah halaman / buka-tutup chat tidak
// membaca ulang. Semua akses penyimpanan dibungkus try/catch: tanpa
// penyimpanan (mode privat, diblokir) tetap jalan, hanya tanpa simpanan.

const KEY = "natalo.chatConfig.v1";
export const CHAT_CONFIG_TTL_MS = 5 * 60 * 1000;

export type ChatConfig = { chatEnabled: boolean; online: boolean | null };

type Stored = ChatConfig & { at: number };

function readStored(now: number): ChatConfig | null {
  try {
    const raw = window.sessionStorage.getItem(KEY);
    if (!raw) return null;
    const v = JSON.parse(raw) as Partial<Stored>;
    if (typeof v.at !== "number" || typeof v.chatEnabled !== "boolean") return null;
    if (now - v.at < 0 || now - v.at >= CHAT_CONFIG_TTL_MS) return null;
    return { chatEnabled: v.chatEnabled, online: typeof v.online === "boolean" ? v.online : null };
  } catch {
    return null;
  }
}

function writeStored(cfg: ChatConfig, now: number): void {
  try {
    window.sessionStorage.setItem(KEY, JSON.stringify({ ...cfg, at: now }));
  } catch {
    /* penyimpanan tidak tersedia — lanjut tanpa simpanan */
  }
}

/** Buang simpanan (mis. kirim pesan ditolak karena chat dimatikan). */
export function forgetChatConfig(): void {
  try {
    window.sessionStorage.removeItem(KEY);
  } catch {
    /* abaikan */
  }
}

let inflight: Promise<ChatConfig | null> | null = null;

/** null = tidak tahu (gagal ambil); tidak disimpan supaya dicoba lagi. */
export function getChatConfig(): Promise<ChatConfig | null> {
  const cached = readStored(Date.now());
  if (cached) return Promise.resolve(cached);
  if (inflight) return inflight;
  inflight = (async () => {
    try {
      const res = await fetch("/api/chat/config", { cache: "no-store", credentials: "same-origin" });
      if (!res.ok) return null;
      const json = (await res.json().catch(() => null)) as { chatEnabled?: unknown; online?: unknown } | null;
      if (!json) return null;
      const cfg: ChatConfig = {
        chatEnabled: json.chatEnabled !== false,
        online: typeof json.online === "boolean" ? json.online : null,
      };
      writeStored(cfg, Date.now());
      return cfg;
    } catch {
      return null;
    } finally {
      inflight = null;
    }
  })();
  return inflight;
}
