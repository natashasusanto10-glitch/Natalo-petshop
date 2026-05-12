import { requireCustomerSession } from "@/lib/session-guards";

export default async function CheckoutLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  await requireCustomerSession();
  return children;
}
