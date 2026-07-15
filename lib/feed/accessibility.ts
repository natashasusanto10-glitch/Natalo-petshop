export const MAX_FEED_ALT_TEXT_LENGTH = 1000;
export const MAX_FEED_SUBTITLE_URL_LENGTH = 2048;
export const MAX_FEED_SUBTITLE_LANGUAGE_LENGTH = 35;

const SUBTITLE_LANGUAGE_PATTERN = /^[A-Za-z]{2,8}(?:-[A-Za-z0-9]{1,8})*$/;
const hasOwn = (input: object, key: string): boolean =>
  Object.prototype.hasOwnProperty.call(input, key);

export type FeedAccessibilityMetadata = {
  videoAltText: string | null;
  hasAudio: boolean | null;
  subtitleUrl: string | null;
  subtitleLanguage: string | null;
};

type ParseResult<T> =
  | { ok: true; data: T }
  | { ok: false; error: string };

function parseNullableBoundedString(
  value: unknown,
  label: string,
  maxLength: number,
): ParseResult<string | null> {
  if (value === null) return { ok: true, data: null };
  if (typeof value !== "string") {
    return { ok: false, error: `${label} harus berupa teks atau null.` };
  }

  const normalized = value.trim();
  if (!normalized) return { ok: true, data: null };
  if (normalized.length > maxLength) {
    return {
      ok: false,
      error: `${label} maksimal ${maxLength} karakter.`,
    };
  }
  return { ok: true, data: normalized };
}

function isTrustedHttpsUrl(value: string): boolean {
  try {
    const url = new URL(value);
    return (
      url.protocol === "https:" &&
      Boolean(url.hostname) &&
      !url.username &&
      !url.password
    );
  } catch {
    return false;
  }
}

export function parseFeedAltText(
  value: unknown,
  label = "Alt text",
): ParseResult<string | null> {
  return parseNullableBoundedString(
    value,
    label,
    MAX_FEED_ALT_TEXT_LENGTH,
  );
}

export function parseFeedAccessibilityMetadata(
  input: Record<string, unknown>,
  options: { partial?: boolean } = {},
): ParseResult<Partial<FeedAccessibilityMetadata>> {
  const partial = options.partial === true;
  const data: Partial<FeedAccessibilityMetadata> = {};

  if (!partial || hasOwn(input, "videoAltText")) {
    const result = parseFeedAltText(
      input.videoAltText ?? null,
      "Video alt text",
    );
    if (!result.ok) return result;
    data.videoAltText = result.data;
  }

  if (!partial || hasOwn(input, "hasAudio")) {
    if (
      input.hasAudio !== undefined &&
      input.hasAudio !== null &&
      typeof input.hasAudio !== "boolean"
    ) {
      return {
        ok: false,
        error: "hasAudio harus berupa boolean atau null.",
      };
    }
    data.hasAudio = (input.hasAudio as boolean | null | undefined) ?? null;
  }

  if (!partial || hasOwn(input, "subtitleUrl")) {
    const result = parseNullableBoundedString(
      input.subtitleUrl ?? null,
      "Subtitle URL",
      MAX_FEED_SUBTITLE_URL_LENGTH,
    );
    if (!result.ok) return result;
    if (result.data !== null && !isTrustedHttpsUrl(result.data)) {
      return {
        ok: false,
        error: "Subtitle URL harus berupa URL HTTPS yang valid.",
      };
    }
    data.subtitleUrl = result.data;
  }

  if (!partial || hasOwn(input, "subtitleLanguage")) {
    const result = parseNullableBoundedString(
      input.subtitleLanguage ?? null,
      "Subtitle language",
      MAX_FEED_SUBTITLE_LANGUAGE_LENGTH,
    );
    if (!result.ok) return result;
    if (
      result.data !== null &&
      !SUBTITLE_LANGUAGE_PATTERN.test(result.data)
    ) {
      return {
        ok: false,
        error: "Subtitle language harus berupa tag bahasa seperti id atau en-US.",
      };
    }
    data.subtitleLanguage = result.data;
  }

  return { ok: true, data };
}

export function feedAccessibilityPayload(
  post: FeedAccessibilityMetadata,
  serializeUrl: (url: string) => string | null | undefined = (url) => url,
): FeedAccessibilityMetadata {
  return {
    videoAltText: post.videoAltText,
    hasAudio: post.hasAudio,
    subtitleUrl: post.subtitleUrl
      ? serializeUrl(post.subtitleUrl) ?? post.subtitleUrl
      : null,
    subtitleLanguage: post.subtitleLanguage,
  };
}
