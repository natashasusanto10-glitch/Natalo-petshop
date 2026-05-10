type Props = {
  stock: number;
  outOfStock: boolean;
};

export function TrustInfoCard({ stock, outOfStock }: Props) {
  return (
    <div className="mt-4 divide-y divide-gray-100 rounded-2xl border border-gray-100 bg-white">
      <div className="flex items-center gap-3 px-4 py-3">
        <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-emerald-50 text-emerald-600">
          <svg
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth={2}
            className="h-5 w-5"
            aria-hidden="true"
          >
            <path d="M12 3l8 3v5c0 5-3.5 8.5-8 10-4.5-1.5-8-5-8-10V6l8-3z" />
            <path d="M9 12l2 2 4-4" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </span>
        <div className="min-w-0">
          <p className="text-sm font-extrabold text-gray-900">
            Garansi 100% Original
          </p>
          <p className="text-xs text-gray-500">Uang kembali jika produk palsu</p>
        </div>
      </div>
      <div className="flex items-center gap-3 px-4 py-3">
        <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-emerald-50 text-emerald-600">
          <svg
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth={2}
            className="h-5 w-5"
            aria-hidden="true"
          >
            <path d="M21 9l-9-5-9 5 9 5 9-5z" strokeLinejoin="round" />
            <path d="M3 9v6l9 5 9-5V9" strokeLinejoin="round" />
            <path d="M12 14v6" />
          </svg>
        </span>
        <div className="min-w-0">
          <p className="text-sm font-extrabold text-gray-900">
            {outOfStock ? "Stok habis" : `Stok tersedia: ${stock}`}
          </p>
          <p className="text-xs text-gray-500">
            {outOfStock
              ? "Hubungi admin untuk info restock"
              : "Siap dikirim hari ini sebelum 15:00"}
          </p>
        </div>
      </div>
    </div>
  );
}
