-- Tag People (Spec B) — user lain yang ditandai di post, ala Instagram.
-- Foto: mediaId + koordinat x/y (pecahan 0-1 dari dimensi foto).
-- Video: mediaId/x/y null — tag berupa daftar nama saja.

-- CreateTable
CREATE TABLE "FeedTaggedUser" (
    "id" TEXT NOT NULL,
    "feedPostId" TEXT NOT NULL,
    "mediaId" TEXT,
    "taggedUserId" TEXT NOT NULL,
    "x" DOUBLE PRECISION,
    "y" DOUBLE PRECISION,
    "hidden" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "FeedTaggedUser_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "FeedTaggedUser_feedPostId_taggedUserId_key" ON "FeedTaggedUser"("feedPostId", "taggedUserId");

-- CreateIndex
CREATE INDEX "FeedTaggedUser_taggedUserId_hidden_idx" ON "FeedTaggedUser"("taggedUserId", "hidden");

-- CreateIndex
CREATE INDEX "FeedTaggedUser_feedPostId_idx" ON "FeedTaggedUser"("feedPostId");

-- AddForeignKey
ALTER TABLE "FeedTaggedUser" ADD CONSTRAINT "FeedTaggedUser_feedPostId_fkey" FOREIGN KEY ("feedPostId") REFERENCES "FeedPost"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "FeedTaggedUser" ADD CONSTRAINT "FeedTaggedUser_mediaId_fkey" FOREIGN KEY ("mediaId") REFERENCES "FeedMedia"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "FeedTaggedUser" ADD CONSTRAINT "FeedTaggedUser_taggedUserId_fkey" FOREIGN KEY ("taggedUserId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
