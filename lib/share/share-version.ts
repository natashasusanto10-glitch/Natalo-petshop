import { createHash } from "node:crypto";

export function stripEphemeralUrlQuery(value: string | null | undefined) {
  if (!value) return "";
  try {
    const url = new URL(value);
    return `${url.origin}${url.pathname}`;
  } catch {
    return value.trim();
  }
}

export function buildShareVersion(parts: readonly unknown[]) {
  const normalized = parts.map((part) => String(part ?? "").trim()).join("\u001f");
  return createHash("sha256").update(normalized).digest("base64url").slice(0, 16);
}
