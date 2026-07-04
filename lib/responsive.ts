type Cols = { base?: number; sm?: number; lg?: number; xl?: number; xxl?: number };

// Static class list so Tailwind v4's content scanner keeps them (dynamic
// class name interpolation is safe here because every value we emit also
// literally appears in this file).
const COLS: Record<number, { base: string; sm: string; lg: string; xl: string; xxl: string }> = {
  2: { base: "grid-cols-2", sm: "sm:grid-cols-2", lg: "lg:grid-cols-2", xl: "xl:grid-cols-2", xxl: "2xl:grid-cols-2" },
  3: { base: "grid-cols-3", sm: "sm:grid-cols-3", lg: "lg:grid-cols-3", xl: "xl:grid-cols-3", xxl: "2xl:grid-cols-3" },
  4: { base: "grid-cols-4", sm: "sm:grid-cols-4", lg: "lg:grid-cols-4", xl: "xl:grid-cols-4", xxl: "2xl:grid-cols-4" },
  5: { base: "grid-cols-5", sm: "sm:grid-cols-5", lg: "lg:grid-cols-5", xl: "xl:grid-cols-5", xxl: "2xl:grid-cols-5" },
  6: { base: "grid-cols-6", sm: "sm:grid-cols-6", lg: "lg:grid-cols-6", xl: "xl:grid-cols-6", xxl: "2xl:grid-cols-6" },
};

const VALID_COLS = [2, 3, 4, 5, 6];

function getColsWithGuard(
  colCount: number,
  breakpoint: keyof Omit<(typeof COLS)[2], never>,
): string {
  if (!COLS[colCount]) {
    throw new Error(
      `Invalid column count: ${colCount}. Must be one of ${VALID_COLS.join(", ")}.`,
    );
  }
  return COLS[colCount][breakpoint];
}

export function gridColsClass(opts?: Cols): string {
  if (!opts) {
    return "grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5";
  }
  const parts = [getColsWithGuard(opts.base ?? 2, "base")];
  if (opts.sm !== undefined) parts.push(getColsWithGuard(opts.sm, "sm"));
  if (opts.lg !== undefined) parts.push(getColsWithGuard(opts.lg, "lg"));
  if (opts.xl !== undefined) parts.push(getColsWithGuard(opts.xl, "xl"));
  if (opts.xxl !== undefined) parts.push(getColsWithGuard(opts.xxl, "xxl"));
  return parts.join(" ");
}
