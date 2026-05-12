import { requireCustomerSession } from "@/lib/session-guards";

export default async function AccountLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  await requireCustomerSession();
  return children;
}
