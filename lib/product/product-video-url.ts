/**
 * Derive URL MP4 progresif Bunny dari URL playlist HLS produk.
 *
 * Product API menyimpan videoUrl sebagai playlist HLS (.m3u8). Browser
 * (selain Safari) tak memutar HLS natif, jadi untuk web kita pakai MP4
 * progresif (play_<h>p.mp4) yang jalan di semua browser tanpa hls.js.
 * Rewrite murni string (host + guid tetap), jadi tak butuh env/library.
 * Butuh "MP4 Fallback" ON di library Bunny; kalau file MP4 tak ada,
 * pemutar akan error → caller fallback ke foto/thumbnail.
 *
 * Return null kalau URL bukan pola playlist Bunny (`/<guid>/playlist.m3u8`),
 * supaya caller bisa fallback aman.
 */
export function productVideoMp4(
  playlistUrl: string | null | undefined,
  height: 240 | 360 | 480 | 720 | 1080 = 720,
): string | null {
  if (!playlistUrl) return null;
  const m = playlistUrl.match(
    /^(https?:\/\/[^/]+\/[a-f0-9-]+\/)playlist\.m3u8(\?.*)?$/i,
  );
  if (!m) return null;
  return `${m[1]}play_${height}p.mp4${m[2] ?? ""}`;
}
