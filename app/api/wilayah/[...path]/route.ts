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

async function fetchWilayah(upstreamPath: string) {
  const res = await fetch(`${UPSTREAM}/${upstreamPath}`, {
    next: { revalidate: 86400 },
  });
  if (!res.ok) {
    return { ok: false as const, status: res.status, data: null };
  }
  return { ok: true as const, status: res.status, data: await res.json() };
}

function unwrapData(payload: unknown): unknown[] {
  if (Array.isArray(payload)) return payload;
  if (
    payload &&
    typeof payload === "object" &&
    "data" in payload &&
    Array.isArray((payload as { data?: unknown }).data)
  ) {
    return (payload as { data: unknown[] }).data;
  }
  return [];
}

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ path: string[] }> }
) {
  const { path } = await params;
  const endpoint = (path[0] ?? "").replace(/\.json$/, "");
  const searchParams = request.nextUrl.searchParams;

  const aliases: Record<string, string | null> = {
    provinsi: "provinces.json",
    kota: searchParams.get("provinsi") ? `regencies/${searchParams.get("provinsi")}.json` : null,
    kecamatan: searchParams.get("kota") ? `districts/${searchParams.get("kota")}.json` : null,
    kodepos: searchParams.get("kec") ? `villages/${searchParams.get("kec")}.json` : null,
  };

  if (Object.prototype.hasOwnProperty.call(aliases, endpoint)) {
    const upstreamPath = aliases[endpoint];
    if (!upstreamPath) {
      return NextResponse.json({ error: "Parameter wilayah tidak lengkap" }, { status: 400 });
    }

    try {
      const result = await fetchWilayah(upstreamPath);
      if (!result.ok) {
        return NextResponse.json({ error: `Upstream error ${result.status}` }, { status: 502 });
      }
      const data = unwrapData(result.data).map((item) => {
        const value = item as Record<string, unknown>;
        return {
          ...value,
          id: value.code ?? value.id ?? value.kode,
          name: value.name ?? value.nama,
          postalCode: value.postal_code ?? value.postalCode ?? value.kode_pos,
        };
      });
      return NextResponse.json({ data }, {
        headers: { "Cache-Control": "public, max-age=86400, s-maxage=86400" },
      });
    } catch {
      return NextResponse.json({ error: "Gagal menghubungi wilayah.id" }, { status: 502 });
    }
  }

  // Hanya izinkan endpoint yang kita pakai untuk mencegah open proxy.
  // Strip `.json` dari segment pertama agar `provinces.json` ikut terdaftar.
  const allowed = new Set(["provinces", "regencies", "districts", "villages"]);
  if (path.length === 0 || !allowed.has(endpoint)) {
    return NextResponse.json({ error: "Endpoint tidak diizinkan" }, { status: 400 });
  }

  try {
    const result = await fetchWilayah(path.join("/"));
    if (!result.ok) {
      return NextResponse.json(
        { error: `Upstream error ${result.status}` },
        { status: 502 }
      );
    }
    return NextResponse.json(result.data, {
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
