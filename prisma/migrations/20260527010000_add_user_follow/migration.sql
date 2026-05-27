-- User-to-user follow graph for the hybrid NestJS social service.
ALTER TABLE "User"
  ADD COLUMN "followersCount" INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN "followingCount" INTEGER NOT NULL DEFAULT 0;

CREATE TABLE "UserFollow" (
  "id" TEXT NOT NULL,
  "followerId" TEXT NOT NULL,
  "followingId" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "UserFollow_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "UserFollow_followerId_followingId_key"
  ON "UserFollow"("followerId", "followingId");

CREATE INDEX "UserFollow_followerId_createdAt_idx"
  ON "UserFollow"("followerId", "createdAt");

CREATE INDEX "UserFollow_followingId_createdAt_idx"
  ON "UserFollow"("followingId", "createdAt");

ALTER TABLE "UserFollow"
  ADD CONSTRAINT "UserFollow_followerId_fkey"
  FOREIGN KEY ("followerId") REFERENCES "User"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "UserFollow"
  ADD CONSTRAINT "UserFollow_followingId_fkey"
  FOREIGN KEY ("followingId") REFERENCES "User"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
