import { NextRequest, NextResponse } from "next/server";

/**
 * Proxy untuk wilayah.id API.
 * Server-side fetch agar tidak ada masalah CORS — wilayah.id tidak mengirim
 * header Access-Control-Allow-Origin.
 *
 * Pattern URL yang di-forward:
 *   /api/wilayah/provinces.json           → https://wilayah.id/api/provinces.json
 *   /api/wilayah/regencies/{code}.json    → https://wilayah.id/api/regencies/{code}.json
 *   /api/wilayah/districts/{code}.json    → https://wilayah.id/api/districts/{code}.json
 *   /api/wilayah/villages/{code}.json     → https://wilayah.id/api/villages/{code}.json
 *
 * Response di-cache 24 jam karena data wilayah Indonesia jarang berubah.
 */

const UPSTREAM = "https://wilayah.id/api";

export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ path: string[] }> }
) {
  const { path } = await params;

  // Hanya izinkan endpoint yang kita pakai untuk mencegah open proxy.
  // Strip `.json` dari segment pertama agar `provinces.json` ikut terdaftar.
  const allowed = new Set(["provinces", "regencies", "districts", "villages"]);
  const firstSegment = (path[0] ?? "").replace(/\.json$/, "");
  if (path.length === 0 || !allowed.has(firstSegment)) {
    return NextResponse.json({ error: "Endpoint tidak diizinkan" }, { status: 400 });
  }

  const upstreamUrl = `${UPSTREAM}/${path.join("/")}`;

  try {
    const res = await fetch(upstreamUrl, {
      // Cache di Next.js fetch cache untuk 24 jam
      next: { revalidate: 86400 },
    });
    if (!res.ok) {
      return NextResponse.json(
        { error: `Upstream error ${res.status}` },
        { status: 502 }
      );
    }
    const data = await res.json();
    return NextResponse.json(data, {
      headers: {
        "Cache-Control": "public, max-age=86400, s-maxage=86400",
      },
    });
  } catch {
    return NextResponse.json(
      { error: "Gagal menghubungi wilayah.id" },
      { status: 502 }
    );
  }
}
