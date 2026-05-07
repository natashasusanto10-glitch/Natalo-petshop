import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";

export default async function ProtectedAdminLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const session = await getSession();

  if (!session) redirect("/admin/login");
  if (session.role === "CUSTOMER") redirect("/member/dashboard");

  return children;
}
