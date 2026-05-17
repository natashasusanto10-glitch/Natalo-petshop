export const STORE_CONTACT_EMAIL =
  process.env.NEXT_PUBLIC_CONTACT_EMAIL ||
  process.env.NEXT_PUBLIC_SUPPORT_EMAIL ||
  process.env.SHOP_ORIGIN_CONTACT_EMAIL ||
  "hello@natalopetshop.com";

export function storeContactMailto(subject?: string) {
  const suffix = subject ? `?subject=${encodeURIComponent(subject)}` : "";
  return `mailto:${STORE_CONTACT_EMAIL}${suffix}`;
}
