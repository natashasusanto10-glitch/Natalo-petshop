export const CHAT_TEXT_MAX_LEN = 4000;

export function validateChatSendContent(
  text: string,
  hasResolvedContext: boolean,
): { ok: true } | { ok: false; error: string } {
  if (text.length > CHAT_TEXT_MAX_LEN) {
    return { ok: false, error: "Pesan maksimal 4000 karakter." };
  }
  if (!text && !hasResolvedContext) {
    return { ok: false, error: "Pesan tidak boleh kosong tanpa konteks yang valid." };
  }
  return { ok: true };
}
