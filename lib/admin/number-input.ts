/** Keep the API value numeric while displaying Indonesian thousands separators. */
export function formatAdminNumber(raw: string | number): string {
  const value = String(raw).replace(/\./g, "");
  if (!/^\d*$/.test(value)) return String(raw);
  return value.replace(/^0+(?=\d)/, "").replace(/\B(?=(\d{3})+(?!\d))/g, ".");
}

export function parseAdminInteger(raw: string): number {
  if (!/^(?:\d+|\d{1,3}(?:\.\d{3})+)$/.test(raw.trim())) return NaN;
  const value = Number(raw.replace(/\./g, ""));
  return Number.isSafeInteger(value) ? value : NaN;
}
