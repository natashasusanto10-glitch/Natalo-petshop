import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";

export default async function EditBrandPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") redirect("/admin/login");
  const { id } = await params;
  redirect(`/admin/brands?edit=${encodeURIComponent(id)}`);
}
