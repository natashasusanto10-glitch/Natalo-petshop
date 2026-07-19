-- Revoked session tokens. On logout the server stores the SHA-256 fingerprint
-- of the JWT (never the raw token) so a still-valid bearer JWT is rejected by
-- getSession — clearing the cookie alone did not invalidate mobile bearer
-- sessions. Rows can be purged by a cron once "expiresAt" has passed (the JWT
-- itself is expired by then and rejected on signature/exp anyway).

CREATE TABLE "RevokedToken" (
    "id" TEXT NOT NULL,
    "fingerprint" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "RevokedToken_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "RevokedToken_fingerprint_key" ON "RevokedToken"("fingerprint");

-- CreateIndex
CREATE INDEX "RevokedToken_expiresAt_idx" ON "RevokedToken"("expiresAt");
