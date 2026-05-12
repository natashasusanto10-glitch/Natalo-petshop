import { requireCustomerSession } from "@/lib/session-guards";

export default async function NotificationsLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  await requireCustomerSession();
  return children;
}
