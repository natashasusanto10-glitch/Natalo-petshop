"use client";

export function PrintButton() {
  return (
    <button
      onClick={() => window.print()}
      className="print:hidden rounded-lg bg-zinc-950 px-5 py-3 text-sm font-bold text-white hover:bg-zinc-800"
    >
      Print Resi
    </button>
  );
}
