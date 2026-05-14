import type { Metadata } from "next";
import { StickyBackTitle } from "@/components/StickyBackTitle";
import { prisma } from "@/lib/prisma";
import { requireCustomerSession } from "@/lib/session-guards";
import { RedeemPointsClient } from "./RedeemPointsClient";

export const metadata: Metadata = { title: "Tukar Poin" };

export default async function RedeemLoyaltyPointsPage() {
  const session = await requireCustomerSession();
  const aggregate = await prisma.customerPoint.aggregate({
    where: { userId: session.sub },
    _sum: { points: true },
  });

  const totalPoints = aggregate._sum.points ?? 0;

  return (
    <main className="min-h-screen bg-slate-50">
      <StickyBackTitle label="Tukar Poin" fallbackHref="/member" stickToTop />
      <div className="mx-auto max-w-2xl px-4 py-4 md:py-10">
        <RedeemPointsClient totalPoints={totalPoints} />
      </div>
    </main>
  );
}
