import { validateImageMagicBytes } from "@/lib/upload/validate-image-bytes";

const ALLOWED_PROOF_HOSTS = new Set(["ufs.sh", "utfs.io"]);
const ALLOWED_PROOF_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);

export function parseAllowedPaymentProofUrl(raw: string): URL | null {
  try {
    const url = new URL(raw);
    if (url.protocol !== "https:") return null;
    if (!ALLOWED_PROOF_HOSTS.has(url.hostname) && !url.hostname.endsWith(".ufs.sh")) return null;
    return url;
  } catch {
    return null;
  }
}

export function normalizeAllowedPaymentProofType(raw: string): string | null {
  const contentType = raw.split(";", 1)[0].trim().toLowerCase();
  return ALLOWED_PROOF_TYPES.has(contentType) ? contentType : null;
}

export function hasValidPaymentProofBytes(bytes: Uint8Array, contentType: string): boolean {
  return validateImageMagicBytes(Buffer.from(bytes), contentType);
}
