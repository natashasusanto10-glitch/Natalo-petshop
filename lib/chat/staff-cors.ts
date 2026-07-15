import { NextResponse } from "next/server";

const OFFICIAL_NLCHAT_ORIGINS = new Set([
  "https://tokochat-a8879.web.app",
  "https://tokochat-a8879.firebaseapp.com",
]);

const ALLOW_HEADERS = "Authorization, Content-Type, Accept";
const ALLOW_METHODS = "GET, POST, OPTIONS";

export function isAllowedNlchatOrigin(origin: string | null): boolean {
  if (!origin) return false;
  if (OFFICIAL_NLCHAT_ORIGINS.has(origin)) return true;
  if (process.env.NODE_ENV === "production") return false;
  try {
    const url = new URL(origin);
    return (
      (url.hostname === "localhost" || url.hostname === "127.0.0.1") &&
      (url.protocol === "http:" || url.protocol === "https:")
    );
  } catch {
    return false;
  }
}

export function withStaffCors(request: Request, response: NextResponse): NextResponse {
  const origin = request.headers.get("origin");
  response.headers.append("Vary", "Origin");
  if (!isAllowedNlchatOrigin(origin)) return response;
  response.headers.set("Access-Control-Allow-Origin", origin!);
  response.headers.set("Access-Control-Allow-Headers", ALLOW_HEADERS);
  response.headers.set("Access-Control-Allow-Methods", ALLOW_METHODS);
  response.headers.set("Access-Control-Expose-Headers", "Content-Length");
  return response;
}

export async function runWithStaffCors(
  request: Request,
  operation: () => Promise<NextResponse>,
): Promise<NextResponse> {
  try {
    return withStaffCors(request, await operation());
  } catch (error) {
    console.error(JSON.stringify({
      event: "staff_api_unhandled_error",
      error: error instanceof Error ? error.message.slice(0, 250) : "unknown",
    }));
    return withStaffCors(
      request,
      NextResponse.json(
        { error: "Layanan pesanan sedang tidak tersedia." },
        { status: 500, headers: { "Cache-Control": "private, no-store" } },
      ),
    );
  }
}

export function staffCorsPreflight(request: Request): NextResponse {
  const origin = request.headers.get("origin");
  if (!isAllowedNlchatOrigin(origin)) {
    return NextResponse.json(
      { error: "Origin tidak diizinkan." },
      { status: 403, headers: { Vary: "Origin", "Cache-Control": "no-store" } },
    );
  }
  return new NextResponse(null, {
    status: 204,
    headers: {
      "Access-Control-Allow-Origin": origin!,
      "Access-Control-Allow-Headers": ALLOW_HEADERS,
      "Access-Control-Allow-Methods": ALLOW_METHODS,
      "Access-Control-Max-Age": "600",
      Vary: "Origin",
      "Cache-Control": "private, no-store",
    },
  });
}
