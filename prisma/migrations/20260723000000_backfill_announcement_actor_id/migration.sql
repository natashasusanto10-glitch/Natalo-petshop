-- Backfill Announcement.actorId untuk notifikasi follow LAMA (dibuat sebelum
-- migration 20260722000000 menambah kolom actorId). Tanpa ini, pill "Ikuti"
-- di notifikasi follow lama selalu tampil "Ikuti" walau viewer sudah
-- follow-balik — server tak bisa hitung isFollowing tanpa actorId.
--
-- URL notif follow = "/u/<username>" (lihat lib/social/notifications.ts).
-- Username Natalo dibatasi [a-z0-9_.] (validateUsernameFormat), dan
-- encodeURIComponent TIDAK meng-encode karakter itu, jadi username di URL =
-- persis username tersimpan. substring(url from 4) membuang prefiks "/u/".
--
-- Follow notif tanpa username (url "/notifications") tak bisa di-backfill
-- (tak ada identitas aktor) → dibiarkan null; fallback cek-saat-tap tetap
-- berlaku, wajar karena aktornya memang tak teridentifikasi.
UPDATE "Announcement" a
SET "actorId" = u.id
FROM "User" u
WHERE a."eventType" = 'user_followed'
  AND a."actorId" IS NULL
  AND a.url LIKE '/u/%'
  AND u.username = substring(a.url FROM 4);
