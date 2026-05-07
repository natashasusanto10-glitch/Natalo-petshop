import { AdminChatClient } from "@/components/admin/AdminChatClient";

export default function AdminChatPage() {
  return (
    <div className="mx-auto max-w-7xl px-4 py-8">
      <div className="mb-6">
        <h1 className="text-3xl font-black tracking-tight text-zinc-950">Chat Member</h1>
        <p className="mt-2 text-sm text-zinc-500">
          Balas pertanyaan member langsung dari website.
        </p>
      </div>
      <AdminChatClient />
    </div>
  );
}
