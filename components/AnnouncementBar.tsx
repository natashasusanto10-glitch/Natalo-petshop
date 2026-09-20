/**
 * Announcement bar global — baris tipis paling atas (maks 36px) berisi
 * info toko. < sm: marquee berjalan pelan (track digandakan, keyframe
 * nat-marquee yang sama dengan marquee brand). ≥ sm: statis di tengah.
 *
 * Sengaja dirender DI LUAR <header> sticky (Header.tsx) supaya bar ini
 * ikut scroll pergi dan hanya navbar yang menempel di top: 0.
 */
const ITEMS = [
  "Gratis Ongkir Area Medan 🛵",
  "Produk Original 100% 🛡️",
  "Banyak Promo Setiap Hari ⚡",
];

function Items({ hidden = false }: { hidden?: boolean }) {
  return (
    <div
      className="flex shrink-0 items-center gap-6 pr-6"
      aria-hidden={hidden || undefined}
    >
      {ITEMS.map((item) => (
        <span key={item} className="flex items-center gap-6 whitespace-nowrap">
          <span>{item}</span>
          <span aria-hidden className="opacity-50">
            •
          </span>
        </span>
      ))}
    </div>
  );
}

export function AnnouncementBar() {
  return (
    <div
      role="region"
      aria-label="Informasi toko"
      className="bg-gradient-to-r from-natalo-700 via-natalo-600 to-natalo-700 text-white"
    >
      {/* ≥ sm — statis di tengah, muat tanpa scroll. */}
      <div className="mx-auto hidden h-9 max-w-[var(--nat-container)] items-center justify-center gap-5 px-4 text-xs font-semibold tracking-wide sm:flex">
        {ITEMS.map((item, index) => (
          <span key={item} className="flex items-center gap-5 whitespace-nowrap">
            {index > 0 && (
              <span aria-hidden className="opacity-50">
                •
              </span>
            )}
            <span>{item}</span>
          </span>
        ))}
      </div>
      {/* < sm — marquee pelan, loop mulus. */}
      <div className="overflow-hidden sm:hidden">
        <div
          className="nat-announcement-track flex h-9 w-max items-center"
          style={{ animationDuration: "18s" }}
        >
          <Items />
          <Items hidden />
        </div>
      </div>
    </div>
  );
}
