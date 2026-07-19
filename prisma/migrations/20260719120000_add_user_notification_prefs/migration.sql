-- Per-category push notification preferences, stored as a JSON map<string,bool>
-- on the user row. Nullable: existing users default to DEFAULT_NOTIFICATION_PREFS
-- (see lib/notification-preferences.ts) until they save an explicit choice.
--
-- Server-side dispatch filters push against this column so a disabled toggle
-- actually stops delivery — the previous client-side filter never ran for
-- background/tray notifications.

ALTER TABLE "User"
ADD COLUMN "notificationPrefs" JSONB;
