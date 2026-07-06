-- Drop dead customer-chat tables. Chat is served entirely by Firestore
-- (customerChats) in NLCATTER; these Postgres tables were never wired to a
-- live feature and only lingered in account-delete cascade + reset-all.
-- Safe to drop: zero application references remain.

-- DropForeignKey
ALTER TABLE "ChatMessage" DROP CONSTRAINT "ChatMessage_senderId_fkey";

-- DropForeignKey
ALTER TABLE "ChatMessage" DROP CONSTRAINT "ChatMessage_threadId_fkey";

-- DropForeignKey
ALTER TABLE "ChatThread" DROP CONSTRAINT "ChatThread_userId_fkey";

-- DropTable
DROP TABLE "ChatMessage";

-- DropTable
DROP TABLE "ChatThread";
