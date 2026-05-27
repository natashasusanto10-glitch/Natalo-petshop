ALTER TABLE "ReviewImage"
ADD COLUMN "mediaType" TEXT NOT NULL DEFAULT 'image',
ADD COLUMN "videoUrl" TEXT,
ADD COLUMN "thumbnailUrl" TEXT;
