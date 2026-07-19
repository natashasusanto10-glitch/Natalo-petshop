/**
 * Thumbnail untuk baris notifikasi feed. Video → thumbnailUrl (URL Bunny;
 * di-sign saat baca di mapAnnouncement). Foto → URL FeedMedia pertama
 * (sortOrder asc). Null bila post tak punya keduanya.
 */
export function feedNotificationThumbnail(post: {
  thumbnailUrl: string | null;
  media?: Array<{ url: string }> | null;
}): string | null {
  return post.thumbnailUrl ?? post.media?.[0]?.url ?? null;
}
