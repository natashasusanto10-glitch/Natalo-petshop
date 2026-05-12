import { requireAdminSession } from "@/lib/session-guards";

export default async function ProtectedAdminLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  await requireAdminSession();

  return children;
}
