const HOURS = [
  "Jam toko: Senin-Sabtu, 09.00-18.00 WIB",
  "Order online: 09.00-15.00 WIB",
  "Instant delivery: 09.00-18.00 WIB",
  "Minggu/libur nasional: tutup atau sesuai info admin",
];

export function OperatingHours({
  className = "",
  itemClassName = "",
}: {
  className?: string;
  itemClassName?: string;
}) {
  return (
    <ul className={className}>
      {HOURS.map((item) => (
        <li className={itemClassName} key={item}>
          {item}
        </li>
      ))}
    </ul>
  );
}

export function OperatingHoursCard({ className = "" }: { className?: string }) {
  return (
    <div className={`rounded-2xl border border-gray-100 bg-white p-4 ${className}`}>
      <p className="text-sm font-semibold text-gray-900">Jam operasional</p>
      <OperatingHours className="mt-2 space-y-1 text-xs leading-5 text-gray-500" />
    </div>
  );
}
