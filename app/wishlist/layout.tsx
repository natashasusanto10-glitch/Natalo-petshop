import { requireCustomerSession } from "@/lib/session-guards";

export default async function WishlistLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  await requireCustomerSession();
  return children;
}
