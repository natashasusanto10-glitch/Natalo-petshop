-- AlterTable
ALTER TABLE "FeedPost"
ADD COLUMN "videoAltText" TEXT,
ADD COLUMN "hasAudio" BOOLEAN,
ADD COLUMN "subtitleUrl" TEXT,
ADD COLUMN "subtitleLanguage" TEXT;

-- AlterTable
ALTER TABLE "FeedMedia" ADD COLUMN "altText" TEXT;
