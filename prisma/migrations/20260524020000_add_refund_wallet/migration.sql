-- CreateEnum
CREATE TYPE "RefundWalletStatus" AS ENUM ('ACTIVE', 'FROZEN');

-- CreateEnum
CREATE TYPE "RefundLedgerType" AS ENUM ('CREDIT', 'DEBIT', 'REVERSAL', 'ADJUSTMENT');

-- CreateEnum
CREATE TYPE "RefundCaseReason" AS ENUM ('OUT_OF_STOCK', 'PARTIAL_CANCEL', 'RETURN_APPROVED', 'ORDER_CANCELLED', 'OTHER');

-- CreateEnum
CREATE TYPE "RefundCaseStatus" AS ENUM ('PENDING', 'APPROVED', 'CREDITED', 'REJECTED');

-- CreateEnum
CREATE TYPE "RefundCaseDestination" AS ENUM ('REFUND_BALANCE', 'ORIGINAL_PAYMENT');

-- CreateTable
CREATE TABLE "RefundWallet" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "availableBalance" INTEGER NOT NULL DEFAULT 0,
    "pendingBalance" INTEGER NOT NULL DEFAULT 0,
    "status" "RefundWalletStatus" NOT NULL DEFAULT 'ACTIVE',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "RefundWallet_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RefundWalletLedger" (
    "id" TEXT NOT NULL,
    "walletId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "type" "RefundLedgerType" NOT NULL,
    "amount" INTEGER NOT NULL,
    "balanceBefore" INTEGER NOT NULL,
    "balanceAfter" INTEGER NOT NULL,
    "sourceOrderId" TEXT,
    "sourceRefundCaseId" TEXT,
    "note" TEXT,
    "createdByAdminId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "RefundWalletLedger_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RefundCase" (
    "id" TEXT NOT NULL,
    "orderId" TEXT NOT NULL,
    "orderItemId" TEXT,
    "userId" TEXT NOT NULL,
    "reason" "RefundCaseReason" NOT NULL,
    "amount" INTEGER NOT NULL,
    "voucherAllocations" JSONB,
    "saldoAllocation" JSONB,
    "destination" "RefundCaseDestination" NOT NULL DEFAULT 'REFUND_BALANCE',
    "status" "RefundCaseStatus" NOT NULL DEFAULT 'PENDING',
    "adminNote" TEXT,
    "createdByAdminId" TEXT,
    "ledgerEntryId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "approvedAt" TIMESTAMP(3),
    "creditedAt" TIMESTAMP(3),

    CONSTRAINT "RefundCase_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "RefundWallet_userId_key" ON "RefundWallet"("userId");

-- CreateIndex
CREATE INDEX "RefundWallet_userId_idx" ON "RefundWallet"("userId");

-- CreateIndex
CREATE INDEX "RefundWallet_status_idx" ON "RefundWallet"("status");

-- CreateIndex
CREATE INDEX "RefundWalletLedger_walletId_createdAt_idx" ON "RefundWalletLedger"("walletId", "createdAt");

-- CreateIndex
CREATE INDEX "RefundWalletLedger_userId_createdAt_idx" ON "RefundWalletLedger"("userId", "createdAt");

-- CreateIndex
CREATE INDEX "RefundWalletLedger_sourceOrderId_idx" ON "RefundWalletLedger"("sourceOrderId");

-- CreateIndex
CREATE INDEX "RefundWalletLedger_sourceRefundCaseId_idx" ON "RefundWalletLedger"("sourceRefundCaseId");

-- CreateIndex
CREATE INDEX "RefundCase_orderId_idx" ON "RefundCase"("orderId");

-- CreateIndex
CREATE INDEX "RefundCase_orderItemId_idx" ON "RefundCase"("orderItemId");

-- CreateIndex
CREATE INDEX "RefundCase_userId_createdAt_idx" ON "RefundCase"("userId", "createdAt");

-- CreateIndex
CREATE INDEX "RefundCase_status_idx" ON "RefundCase"("status");

-- CreateIndex
CREATE INDEX "RefundCase_reason_idx" ON "RefundCase"("reason");

-- AddForeignKey
ALTER TABLE "RefundWallet" ADD CONSTRAINT "RefundWallet_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RefundWalletLedger" ADD CONSTRAINT "RefundWalletLedger_walletId_fkey" FOREIGN KEY ("walletId") REFERENCES "RefundWallet"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RefundWalletLedger" ADD CONSTRAINT "RefundWalletLedger_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RefundCase" ADD CONSTRAINT "RefundCase_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RefundCase" ADD CONSTRAINT "RefundCase_orderItemId_fkey" FOREIGN KEY ("orderItemId") REFERENCES "OrderItem"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RefundCase" ADD CONSTRAINT "RefundCase_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
