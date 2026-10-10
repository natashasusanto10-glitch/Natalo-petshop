import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { validateImageMagicBytes } from "@/lib/upload/validate-image-bytes";

export const dynamic = "force-dynamic";
export const maxDuration = 20;
const MAX_BYTES = 2 * 1024 * 1024;

function publicImageUrl(value: string | null): URL | null {
  try {
    const token = JSON.parse(Buffer.from(process.env.UPLOADTHING_TOKEN ?? "", "base64").toString("utf8")) as { appId?: unknown };
    if (typeof token.appId !== "string" || !/^[a-z0-9]+$/i.test(token.appId)) return null;
    const url = new URL(value ?? "");
    // Restrict to this app's public file host. No arbitrary URLs, redirects,
    // signed private files, credentials, ports, or user-selected hosts.
    if (url.protocol !== "https:" || url.hostname !== `${token.appId}.ufs.sh` || url.port || url.username || url.password || url.search || url.hash || !/^\/f\/[A-Za-z0-9_-]{1,256}$/.test(url.pathname)) return null;
    return url;
  } catch { return null; }
}

export async function GET(request: NextRequest) {
  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  const url = publicImageUrl(request.nextUrl.searchParams.get("url"));
  if (!url) return NextResponse.json({ error: "URL foto tidak valid." }, { status: 400 });
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 10_000);
  try {
    const response = await fetch(url, { signal: controller.signal, redirect: "error", cache: "no-store" });
    if (!response.ok) {
      console.warn("[admin/image-preview] upstream rejected", { key: url.pathname.slice(3), status: response.status });
      return NextResponse.json({ error: "Foto belum tersedia di penyimpanan.", upstreamStatus: response.status }, { status: 502 });
    }
    const type = response.headers.get("content-type")?.split(";")[0].trim() ?? "";
    if (!new Set(["image/jpeg", "image/png", "image/webp", "image/gif"]).has(type) || Number(response.headers.get("content-length")) > MAX_BYTES || !response.body) {
      await response.body?.cancel();
      return NextResponse.json({ error: "Respons foto tidak valid." }, { status: 502 });
    }
    const reader = response.body.getReader();
    const chunks: Uint8Array[] = [];
    let size = 0;
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > MAX_BYTES) {
        await reader.cancel();
        return NextResponse.json({ error: "Foto melebihi batas ukuran." }, { status: 413 });
      }
      chunks.push(value);
    }
    const bytes = Buffer.concat(chunks);
    if (!validateImageMagicBytes(bytes, type)) return NextResponse.json({ error: "Isi foto tidak valid." }, { status: 502 });
    return new NextResponse(new Uint8Array(bytes), { headers: {
      "Content-Type": type, "Cache-Control": "private, max-age=300",
      "X-Content-Type-Options": "nosniff",
    } });
  } catch {
    console.warn("[admin/image-preview] image request failed", { key: url.pathname.slice(3), timeout: controller.signal.aborted });
    return NextResponse.json({ error: "Foto belum dapat dimuat dari penyimpanan." }, { status: 502 });
  } finally { clearTimeout(timer); }
}
