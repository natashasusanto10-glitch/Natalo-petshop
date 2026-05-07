"use client";

interface StarsProps {
  rating: number;          // 0-5, boleh desimal (4.7)
  size?: "xs" | "sm" | "md" | "lg";
  showValue?: boolean;
  count?: number;          // jumlah review (untuk display "(156)")
  className?: string;
}

const sizeMap = {
  xs: "text-xs",
  sm: "text-sm",
  md: "text-base",
  lg: "text-2xl",
};

/** Display-only stars (read mode) */
export function Stars({ rating, size = "sm", showValue, count, className }: StarsProps) {
  const full = Math.floor(rating);
  const hasHalf = rating - full >= 0.5;
  const empty = 5 - full - (hasHalf ? 1 : 0);

  return (
    <span className={`inline-flex items-center gap-1 ${sizeMap[size]} ${className ?? ""}`}>
      <span className="text-amber-400">
        {"★".repeat(full)}
        {hasHalf ? "★" : ""}
      </span>
      {empty > 0 && <span className="text-gray-200">{"★".repeat(empty)}</span>}
      {showValue && rating > 0 && (
        <span className="ml-1 font-semibold text-gray-700">{rating.toFixed(1)}</span>
      )}
      {count !== undefined && (
        <span className="ml-1 text-gray-400">({count})</span>
      )}
    </span>
  );
}

/** Interactive stars (input mode) */
interface InputProps {
  value: number;
  onChange: (n: number) => void;
  size?: "sm" | "md" | "lg";
  required?: boolean;
}

export function StarsInput({ value, onChange, size = "lg" }: InputProps) {
  return (
    <div className={`inline-flex items-center gap-1 ${sizeMap[size]}`}>
      {[1, 2, 3, 4, 5].map((n) => (
        <button
          key={n}
          type="button"
          onClick={() => onChange(n)}
          className={`transition ${
            n <= value ? "text-amber-400 hover:text-amber-500" : "text-gray-300 hover:text-amber-300"
          }`}
        >
          ★
        </button>
      ))}
      {value > 0 && (
        <span className="ml-2 text-sm font-semibold text-gray-700">
          {value} dari 5
        </span>
      )}
    </div>
  );
}
