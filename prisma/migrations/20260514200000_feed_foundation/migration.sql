-- Feed foundation (F1): tables, enums, indexes, FKs untuk in-app feed video.
-- See docs (akan menyusul) untuk design rationale. Tab REKOMENDASI/PROMO/KOMUNITAS
-- + 5 kind FeedPost + moderation workflow (PENDING_REVIEW → ACTIVE / REJECTED / HIDDEN).

-- CreateEnum
CREATE TYPE "FeedPostKind" AS ENUM ('VIDEO_ONLY', 'PRODUCT_ONLY', 'VIDEO_PRODUCT', 'PROMO', 'COMMUNITY');

-- CreateEnum
CREATE TYPE "FeedPostTab" AS ENUM ('REKOMENDASI', 'PROMO', 'KOMUNITAS');

-- CreateEnum
CREATE TYPE "FeedPostStatus" AS ENUM ('PENDING_REVIEW', 'ACTIVE', 'REJECTED', 'HIDDEN');

-- CreateEnum
CREATE TYPE "FeedReportTargetType" AS ENUM ('POST', 'COMMENT');

-- CreateEnum
CREATE TYPE "FeedReportReason" AS ENUM ('SPAM', 'INAPPROPRIATE', 'MISLEADING', 'COPYRIGHT', 'OTHER');

-- CreateEnum
CREATE TYPE "FeedReportStatus" AS ENUM ('PENDING', 'RESOLVED', 'DISMISSED');

-- CreateTable
CREATE TABLE "FeedPost" (
    "id" TEXT NOT NULL,
    "authorId" TEXT NOT NULL,
    "authorRole" TEXT NOT NULL,
    "kind" "FeedPostKind" NOT NULL,
    "tab" "FeedPostTab" NOT NULL,
    "status" "FeedPostStatus" NOT NULL DEFAULT 'ACTIVE',
    "title" TEXT NOT NULL,
    "description" TEXT,
    "videoUrl" TEXT,
    "videoMimeType" TEXT,
    "videoSizeBytes" INTEGER,
    "videoDurationSec" INTEGER,
    "videoWidth" INTEGER,
    "videoHeight" INTEGER,
    "thumbnailUrl" TEXT,
    "productId" TEXT,
    "promoOriginalPrice" INTEGER,
    "promoDiscountPrice" INTEGER,
    "promoStartsAt" TIMESTAMP(3),
    "promoEndsAt" TIMESTAMP(3),
    "likeCount" INTEGER NOT NULL DEFAULT 0,
    "commentCount" INTEGER NOT NULL DEFAULT 0,
    "viewCount" INTEGER NOT NULL DEFAULT 0,
    "moderatedById" TEXT,
    "moderatedAt" TIMESTAMP(3),
    "moderationNote" TEXT,
    "publishedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "FeedPost_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "FeedComment" (
    "id" TEXT NOT NULL,
    "postId" TEXT NOT NULL,
    "authorId" TEXT NOT NULL,
    "parentCommentId" TEXT,
    "content" TEXT NOT NULL,
    "isAdminOfficial" BOOLEAN NOT NULL DEFAULT false,
    "isHidden" BOOLEAN NOT NULL DEFAULT false,
    "hiddenById" TEXT,
    "hiddenAt" TIMESTAMP(3),
    "hiddenReason" TEXT,
    "likeCount" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "FeedComment_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "FeedLike" (
    "userId" TEXT NOT NULL,
    "postId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "FeedLike_pkey" PRIMARY KEY ("userId","postId")
);

-- CreateTable
CREATE TABLE "FeedCommentLike" (
    "userId" TEXT NOT NULL,
    "commentId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "FeedCommentLike_pkey" PRIMARY KEY ("userId","commentId")
);

-- CreateTable
CREATE TABLE "FeedReport" (
    "id" TEXT NOT NULL,
    "reporterId" TEXT NOT NULL,
    "targetType" "FeedReportTargetType" NOT NULL,
    "postId" TEXT,
    "commentId" TEXT,
    "reason" "FeedReportReason" NOT NULL,
    "detail" TEXT,
    "status" "FeedReportStatus" NOT NULL DEFAULT 'PENDING',
    "resolvedById" TEXT,
    "resolvedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "FeedReport_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "FeedPost_tab_status_publishedAt_idx" ON "FeedPost"("tab", "status", "publishedAt");

-- CreateIndex
CREATE INDEX "FeedPost_authorId_status_createdAt_idx" ON "FeedPost"("authorId", "status", "createdAt");

-- CreateIndex
CREATE INDEX "FeedPost_productId_status_idx" ON "FeedPost"("productId", "status");

-- CreateIndex
CREATE INDEX "FeedPost_status_createdAt_idx" ON "FeedPost"("status", "createdAt");

-- CreateIndex
CREATE INDEX "FeedComment_postId_isHidden_createdAt_idx" ON "FeedComment"("postId", "isHidden", "createdAt");

-- CreateIndex
CREATE INDEX "FeedComment_authorId_idx" ON "FeedComment"("authorId");

-- CreateIndex
CREATE INDEX "FeedComment_parentCommentId_idx" ON "FeedComment"("parentCommentId");

-- CreateIndex
CREATE INDEX "FeedLike_postId_idx" ON "FeedLike"("postId");

-- CreateIndex
CREATE INDEX "FeedCommentLike_commentId_idx" ON "FeedCommentLike"("commentId");

-- CreateIndex
CREATE INDEX "FeedReport_status_createdAt_idx" ON "FeedReport"("status", "createdAt");

-- CreateIndex
CREATE INDEX "FeedReport_reporterId_idx" ON "FeedReport"("reporterId");

-- CreateIndex
CREATE INDEX "FeedReport_postId_idx" ON "FeedReport"("postId");

-- CreateIndex
CREATE INDEX "FeedReport_commentId_idx" ON "FeedReport"("commentId");

-- AddForeignKey
ALTER TABLE "FeedPost" ADD CONSTRAINT "FeedPost_authorId_fkey" FOREIGN KEY ("authorId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "FeedPost" ADD CONSTRAINT "FeedPost_productId_fkey" FOREIGN KEY ("productId") REFERENCES "Product"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "FeedPost" ADD CONSTRAINT "FeedPost_moderatedById_fkey" FOREIGN KEY ("moderatedById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "FeedComment" ADD CONSTRAINT "FeedComment_postId_fkey" FOREIGN KEY ("postId") REFERENCES "FeedPost"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "FeedComment" ADD CONSTRAINT "FeedComment_authorId_fkey" FOREIGN KEY ("authorId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "FeedComment" ADD CONSTRAINT "FeedComment_parentCommentId_fkey" FOREIGN KEY ("parentCommentId") REFERENCES "FeedComment"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "FeedComment" ADD CONSTRAINT "FeedComment_hiddenById_fkey" FOREIGN KEY ("hiddenById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "FeedLike" ADD CONSTRAINT "FeedLike_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "FeedLike" ADD CONSTRAINT "FeedLike_postId_fkey" FOREIGN KEY ("postId") REFERENCES "FeedPost"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "FeedCommentLike" ADD CONSTRAINT "FeedCommentLike_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "FeedCommentLike" ADD CONSTRAINT "FeedCommentLike_commentId_fkey" FOREIGN KEY ("commentId") REFERENCES "FeedComment"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "FeedReport" ADD CONSTRAINT "FeedReport_reporterId_fkey" FOREIGN KEY ("reporterId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "FeedReport" ADD CONSTRAINT "FeedReport_postId_fkey" FOREIGN KEY ("postId") REFERENCES "FeedPost"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "FeedReport" ADD CONSTRAINT "FeedReport_commentId_fkey" FOREIGN KEY ("commentId") REFERENCES "FeedComment"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "FeedReport" ADD CONSTRAINT "FeedReport_resolvedById_fkey" FOREIGN KEY ("resolvedById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
