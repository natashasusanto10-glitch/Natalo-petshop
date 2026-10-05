"use client";

export function ProductQuantitySelector({ quantity, stock, minimum = 1, onChange }: {
  quantity: number;
  stock: number;
  minimum?: number;
  onChange: (quantity: number) => void;
}) {
  return (
    <div className="mt-4 hidden items-center justify-between gap-3 md:flex">
      <span className="text-sm font-semibold text-gray-700">Jumlah</span>
      <div className="flex items-center rounded-lg border border-gray-200">
        <button type="button" aria-label="Kurangi jumlah" disabled={quantity <= minimum || stock < minimum}
          onClick={() => onChange(quantity - 1)} className="h-10 w-10 text-lg text-natalo-600 disabled:text-gray-300">−</button>
        <output aria-label="Jumlah produk" aria-live="polite" className="min-w-10 text-center text-sm font-semibold">{quantity}</output>
        <button type="button" aria-label="Tambah jumlah" disabled={quantity >= stock || stock < minimum}
          onClick={() => onChange(quantity + 1)} className="h-10 w-10 text-lg text-natalo-600 disabled:text-gray-300">+</button>
      </div>
      {stock > 0 && stock < minimum && <p className="text-xs text-red-600">Minimum pembelian {minimum}; stok {stock}.</p>}
    </div>
  );
}
