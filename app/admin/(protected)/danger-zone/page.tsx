import { getSession } from "@/lib/auth";
import { redirect } from "next/navigation";
import { DangerZoneClient } from "@/components/admin/DangerZoneClient";

export const metadata = {
  title: "Danger Zone — Admin",
};

export default async function DangerZonePage() {
  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    redirect("/admin/login");
  }

  return (
    <main className="mx-auto max-w-3xl px-4 py-6">
      <div className="rounded-3xl border-2 border-red-200 bg-red-50/40 p-6">
        <div className="mb-4 flex items-center gap-3">
          <div className="grid h-12 w-12 place-items-center rounded-full bg-red-100">
            <svg
              viewBox="0 0 24 24"
              className="h-6 w-6 fill-red-600"
              aria-hidden
            >
              <path d="M12 2L1 21h22L12 2zm0 5l7.53 13H4.47L12 7zm-1 4v4h2v-4h-2zm0 6v2h2v-2h-2z" />
            </svg>
          </div>
          <div>
            <h1 className="text-2xl font-black text-red-900">Danger Zone</h1>
            <p className="text-sm text-red-700">
              Aksi destruktif. Tidak bisa di-undo.
            </p>
          </div>
        </div>
        <DangerZoneClient />
      </div>
    </main>
  );
}
