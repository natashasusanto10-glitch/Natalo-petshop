import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";

export default async function AdminIndexPage() {
  const session = await getSession("ADMIN");

  if (!session) redirect("/admin/login");
  if (session.role === "CUSTOMER") redirect("/member/dashboard");

  redirect("/admin/dashboard");
}
