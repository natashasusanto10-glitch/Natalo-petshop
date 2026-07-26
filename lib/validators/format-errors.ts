/**
 * Pengubah error Zod → pesan siap-tampil berbahasa Indonesia.
 *
 * ATURAN: JANGAN pernah balas "Payload tidak valid" (atau varian kata
 * "payload" apa pun) ke admin/pelanggan. Kata itu istilah internal dan
 * tidak memberi petunjuk apa pun — satu string yang sama bisa berarti 14+
 * penyebab berbeda, sehingga satu-satunya cara mendiagnosis adalah
 * trial-and-error di UI. Selalu sebut FIELD dan ALASANNYA.
 */

/**
 * Terjemahkan pesan bawaan Zod (berbahasa Inggris, penuh istilah teknis)
 * ke kalimat yang bisa dibaca admin. Pola yang tidak dikenal dilewatkan
 * apa adanya — lebih baik bahasa Inggris daripada informasinya hilang.
 */
export function humanizeZodMessage(message: string): string {
  const tooBigChars = message.match(/have <=(\d+) characters/);
  if (tooBigChars) return `maksimal ${tooBigChars[1]} karakter`;
  const tooSmallChars = message.match(/have >=(\d+) characters/);
  if (tooSmallChars) return `minimal ${tooSmallChars[1]} karakter`;
  const tooBigItems = message.match(/have <=(\d+) items/);
  if (tooBigItems) return `maksimal ${tooBigItems[1]} item`;
  const tooSmallItems = message.match(/have >=(\d+) items/);
  if (tooSmallItems) return `minimal ${tooSmallItems[1]} item`;
  const tooBigNum = message.match(/number to be <=(\d+)/);
  if (tooBigNum) return `maksimal ${tooBigNum[1]}`;
  const tooSmallNum = message.match(/number to be >=(\d+)/);
  if (tooSmallNum) return `minimal ${tooSmallNum[1]}`;
  if (message.includes("received NaN")) return "harus berupa angka (nilai sekarang bukan angka)";
  if (message.includes("expected int")) return "harus bilangan bulat, tanpa desimal";
  if (message.includes("received null")) return "ada nilai kosong yang belum terisi";
  if (message.includes("received undefined")) return "wajib diisi";
  if (message.startsWith("Invalid input: expected")) return `format tidak sesuai (${message})`;
  return message;
}

/**
 * Ubah `zodError.flatten().fieldErrors` jadi satu pesan siap-tampil.
 *
 * @param labels peta nama field teknis → label yang dilihat admin di form.
 *   Field tanpa entri dipakai apa adanya supaya tidak pernah senyap.
 */
export function formatFieldErrors(
  fieldErrors: Record<string, string[] | undefined>,
  labels: Record<string, string>,
  formErrors: string[] = [],
  fallback = "Ada data yang belum valid.",
): string {
  const parts = Object.entries(fieldErrors)
    .filter(([, messages]) => messages && messages.length > 0)
    .map(([field, messages]) => `${labels[field] ?? field}: ${humanizeZodMessage(messages![0])}`);
  const all = [...parts, ...formErrors];
  return all.length > 0 ? all.join(". ") : fallback;
}
