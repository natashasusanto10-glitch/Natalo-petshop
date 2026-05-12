import { redirect } from "next/navigation";
import { getSession, type SessionPayload } from "@/lib/auth";

export async function requireCustomerSession(): Promise<SessionPayload> {
  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") redirect("/member/login");
  return session;
}

export async function requireAdminSession(): Promise<SessionPayload> {
  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") redirect("/admin/login");
  return session;
}
