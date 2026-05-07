export function normalizeIndonesianPhone(value: string) {
  const digits = value.replace(/\D/g, "");

  if (digits.startsWith("62")) return `0${digits.slice(2)}`;
  if (digits.startsWith("8")) return `0${digits}`;
  return digits;
}
