const NATALO_HOSTS = new Set(["natalopetshop.com", "www.natalopetshop.com"]);
const IMAGE_FETCH_TIMEOUT_MS = 4_000;
export const MAX_OG_IMAGE_BYTES = 4 * 1024 * 1024;
const ALLOWED_IMAGE_TYPES = new Set(["image/jpeg", "image/png", "image/webp", "image/gif"]);
const SHARE_VERSION_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;

const NATALO_STATIC_IMAGE_PATH_PREFIXES = [
  "/assets/",
  "/brand/",
  "/brands/",
  "/icons/",
  "/products/",
  "/uploads/",
  "/_next/static/",
] as const;
const NATALO_STATIC_IMAGE_PATHS = new Set([
  "/apple-touch-icon.png",
  "/favicon-32x32.png",
  "/logo.png",
]);
const NATALO_IMAGE_EXTENSION = /\.(?:gif|jpe?g|png|webp)$/i;

export type OgImageCachePolicy = {
  cacheControl: string;
  redirectToVersion: string | null;
};

const VERSIONED_OG_CACHE_CONTROL = "public, s-maxage=3600, stale-while-revalidate=86400";
const NO_STORE_CACHE_CONTROL = "private, no-store";

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

function hasApprovedNataloStaticImagePath(pathname: string) {
  let decodedPathname: string;
  try {
    decodedPathname = decodeURIComponent(pathname);
  } catch {
    return false;
  }

  if (
    !decodedPathname.startsWith("/") ||
    decodedPathname.includes("\\") ||
    decodedPathname.split("/").some((segment) => segment === "." || segment === "..") ||
    !NATALO_IMAGE_EXTENSION.test(decodedPathname)
  ) {
    return false;
  }

  return (
    NATALO_STATIC_IMAGE_PATHS.has(decodedPathname) ||
    NATALO_STATIC_IMAGE_PATH_PREFIXES.some((prefix) => decodedPathname.startsWith(prefix))
  );
}

function isApprovedImageHost(url: URL) {
  const hostname = url.hostname.toLowerCase();
  if (NATALO_HOSTS.has(hostname)) return hasApprovedNataloStaticImagePath(url.pathname);
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
    !isApprovedImageHost(url)
  ) {
    return null;
  }

  return url.toString();
}

function dataUrlForImage(contentType: string, bytes: Uint8Array) {
  return `data:${contentType};base64,${Buffer.from(bytes).toString("base64")}`;
}

function detectedRasterImageType(bytes: Uint8Array): string | null {
  if (
    bytes.length >= 24 &&
    bytes[0] === 0x89 &&
    bytes[1] === 0x50 &&
    bytes[2] === 0x4e &&
    bytes[3] === 0x47 &&
    bytes[4] === 0x0d &&
    bytes[5] === 0x0a &&
    bytes[6] === 0x1a &&
    bytes[7] === 0x0a &&
    bytes[8] === 0x00 &&
    bytes[9] === 0x00 &&
    bytes[10] === 0x00 &&
    bytes[11] === 0x0d &&
    bytes[12] === 0x49 &&
    bytes[13] === 0x48 &&
    bytes[14] === 0x44 &&
    bytes[15] === 0x52 &&
    (bytes[16] !== 0 || bytes[17] !== 0 || bytes[18] !== 0 || bytes[19] !== 0) &&
    (bytes[20] !== 0 || bytes[21] !== 0 || bytes[22] !== 0 || bytes[23] !== 0)
  ) {
    return "image/png";
  }

  if (
    bytes.length >= 6 &&
    bytes[0] === 0xff &&
    bytes[1] === 0xd8 &&
    bytes[2] === 0xff &&
    bytes[bytes.length - 2] === 0xff &&
    bytes[bytes.length - 1] === 0xd9
  ) {
    return "image/jpeg";
  }

  if (
    bytes.length >= 7 &&
    bytes[0] === 0x47 &&
    bytes[1] === 0x49 &&
    bytes[2] === 0x46 &&
    bytes[3] === 0x38 &&
    (bytes[4] === 0x37 || bytes[4] === 0x39) &&
    bytes[5] === 0x61 &&
    bytes[bytes.length - 1] === 0x3b
  ) {
    return "image/gif";
  }

  if (
    bytes.length >= 20 &&
    bytes[0] === 0x52 &&
    bytes[1] === 0x49 &&
    bytes[2] === 0x46 &&
    bytes[3] === 0x46 &&
    bytes[8] === 0x57 &&
    bytes[9] === 0x45 &&
    bytes[10] === 0x42 &&
    bytes[11] === 0x50 &&
    (bytes[12] === 0x56 && bytes[13] === 0x50 && bytes[14] === 0x38) &&
    (bytes[15] === 0x20 || bytes[15] === 0x4c || bytes[15] === 0x58) &&
    new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint32(4, true) + 8 === bytes.length
  ) {
    return "image/webp";
  }

  return null;
}

async function discardResponseBody(response: Response, controller: AbortController) {
  try {
    await response.body?.cancel();
  } catch {
    // The response may already be closed. Abort the request either way.
  } finally {
    controller.abort();
  }
}

async function readBoundedImageBytes(
  response: Response,
  controller: AbortController,
): Promise<Uint8Array | null> {
  const reader = response.body?.getReader();
  if (!reader) return null;

  const chunks: Uint8Array[] = [];
  let byteLength = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (!value?.byteLength) continue;

      byteLength += value.byteLength;
      if (byteLength > MAX_OG_IMAGE_BYTES) {
        try {
          await reader.cancel();
        } catch {
          // The transport may already have released the stream.
        } finally {
          controller.abort();
        }
        return null;
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }

  const bytes = new Uint8Array(byteLength);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

/**
 * Only the current deterministic token is cacheable. Legacy URLs without a
 * token still render, but never become an unbounded CDN cache-key namespace.
 */
export function resolveOgImageCachePolicy(
  requestedVersion: string | null,
  currentVersion: string,
): OgImageCachePolicy {
  if (requestedVersion === currentVersion && SHARE_VERSION_PATTERN.test(currentVersion)) {
    return { cacheControl: VERSIONED_OG_CACHE_CONTROL, redirectToVersion: null };
  }

  if (requestedVersion === null) {
    return { cacheControl: NO_STORE_CACHE_CONTROL, redirectToVersion: null };
  }

  return { cacheControl: NO_STORE_CACHE_CONTROL, redirectToVersion: currentVersion };
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
    if (Number.isFinite(contentLength) && contentLength > MAX_OG_IMAGE_BYTES) {
      await discardResponseBody(response, controller);
      return null;
    }

    const bytes = await readBoundedImageBytes(response, controller);
    if (!bytes) return null;

    const detectedType = detectedRasterImageType(bytes);
    if (detectedType !== contentType) return null;
    return dataUrlForImage(detectedType, bytes);
  } catch {
    return null;
  } finally {
    clearTimeout(timeout);
  }
}
