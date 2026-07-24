-- CreateTable
CREATE TABLE "Hashtag" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "postCount" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "Hashtag_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "FeedPostHashtag" (
    "id" TEXT NOT NULL,
    "feedPostId" TEXT NOT NULL,
    "hashtagId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "FeedPostHashtag_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "Hashtag_name_key" ON "Hashtag"("name");
CREATE UNIQUE INDEX "FeedPostHashtag_feedPostId_hashtagId_key" ON "FeedPostHashtag"("feedPostId", "hashtagId");
CREATE INDEX "FeedPostHashtag_hashtagId_idx" ON "FeedPostHashtag"("hashtagId");

-- AddForeignKey
ALTER TABLE "FeedPostHashtag" ADD CONSTRAINT "FeedPostHashtag_feedPostId_fkey" FOREIGN KEY ("feedPostId") REFERENCES "FeedPost"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "FeedPostHashtag" ADD CONSTRAINT "FeedPostHashtag_hashtagId_fkey" FOREIGN KEY ("hashtagId") REFERENCES "Hashtag"("id") ON DELETE CASCADE ON UPDATE CASCADE;
