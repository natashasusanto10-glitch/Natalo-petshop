const NATALO_HOSTS = new Set(["natalopetshop.com", "www.natalopetshop.com"]);
const IMAGE_FETCH_TIMEOUT_MS = 4_000;
const MAX_OG_IMAGE_BYTES = 4 * 1024 * 1024;
const ALLOWED_IMAGE_TYPES = new Set(["image/jpeg", "image/png", "image/webp", "image/gif"]);

function isIpLiteral(hostname: string) {
  return (
    /^\d{1,3}(?:\.\d{1,3}){3}$/.test(hostname) ||
    hostname.includes(":")
  );
}

function hasApprovedSuffix(hostname: string, suffix: string) {
  return hostname === suffix || hostname.endsWith(`.${suffix}`);
}

function configuredCdnHosts() {
  return [process.env.BUNNY_CDN_HOSTNAME, process.env.BUNNY_PRODUCT_CDN_HOSTNAME]
    .map((host) => host?.trim().toLowerCase())
    .filter((host): host is string => Boolean(host));
}

function isApprovedImageHost(hostname: string) {
  if (NATALO_HOSTS.has(hostname)) return true;
  if (configuredCdnHosts().includes(hostname)) return true;

  // UploadThing hosts are used for public Feed photos and profile avatars.
  return hostname === "utfs.io" || hasApprovedSuffix(hostname, "ufs.sh");
}

/**
 * Validates a database-derived remote image before passing it to ImageResponse.
 * The OG route never fetches arbitrary user input: only public Feed media from
 * these explicit HTTPS hosts can be rendered.
 */
export function safeOgImageUrl(value: string | null | undefined): string | null {
  if (!value) return null;

  let url: URL;
  try {
    url = new URL(value);
  } catch {
    return null;
  }

  const hostname = url.hostname.toLowerCase();
  if (
    url.protocol !== "https:" ||
    url.username ||
    url.password ||
    url.port ||
    url.hash ||
    isIpLiteral(hostname) ||
    !isApprovedImageHost(hostname)
  ) {
    return null;
  }

  return url.toString();
}

function dataUrlForImage(contentType: string, bytes: ArrayBuffer) {
  return `data:${contentType};base64,${Buffer.from(bytes).toString("base64")}`;
}

/**
 * Fetches only allowlisted images for the OG renderer. Redirects, oversized
 * payloads and non-image responses fall back to the local Natalo card.
 */
export async function fetchSafeOgImageData(
  value: string | null | undefined,
  fetcher: typeof fetch = fetch,
): Promise<string | null> {
  const url = safeOgImageUrl(value);
  if (!url) return null;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), IMAGE_FETCH_TIMEOUT_MS);
  try {
    const response = await fetcher(url, {
      headers: { Accept: "image/avif,image/webp,image/png,image/jpeg,image/gif" },
      redirect: "error",
      signal: controller.signal,
    });
    if (!response.ok) return null;

    const contentType = response.headers.get("content-type")?.split(";", 1)[0]?.toLowerCase();
    if (!contentType || !ALLOWED_IMAGE_TYPES.has(contentType)) return null;

    const contentLength = Number(response.headers.get("content-length"));
    if (Number.isFinite(contentLength) && contentLength > MAX_OG_IMAGE_BYTES) return null;

    const bytes = await response.arrayBuffer();
    if (bytes.byteLength > MAX_OG_IMAGE_BYTES) return null;
    return dataUrlForImage(contentType, bytes);
  } catch {
    return null;
  } finally {
    clearTimeout(timeout);
  }
}
