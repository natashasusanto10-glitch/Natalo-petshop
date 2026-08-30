import { listCountNotice } from "@/lib/admin/list-truncation";

/**
 * Baris "menampilkan N dari M" di atas daftar admin yang dibatasi `take`.
 *
 * `total` harus dihitung dengan filter yang sama dengan daftarnya — lihat
 * catatan di lib/admin/list-truncation.ts.
 */
export function ResultCount({
  shown,
  total,
  noun,
}: {
  shown: number;
  total: number;
  noun: string;
}) {
  const notice = listCountNotice(shown, total, noun);

  if (notice.kind === "empty") return null;

  if (notice.kind === "complete") {
    return (
      <p className="mb-3 text-xs font-semibold text-zinc-500">{notice.text}</p>
    );
  }

  return (
    <p
      // role=status supaya pembaca layar mengumumkan pemotongan setelah
      // filter diganti — tanpa ini, informasi "ada yang tak tampil" hanya
      // sampai ke pengguna yang melihat.
      role="status"
      className="mb-3 rounded-lg border border-amber-300 bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-900"
    >
      {notice.text}
    </p>
  );
}
