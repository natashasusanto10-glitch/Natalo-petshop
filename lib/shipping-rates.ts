/**
 * Sumber tarif pengiriman bersama — satu tempat untuk mengutip tarif kurir.
 * Dipakai:
 *   - POST /api/shipping/rates     (daftar tarif untuk UI checkout)
 *   - POST /api/checkout/recalculate (preview total + voucher)
 *   - POST /api/orders             (penagihan final)
 *
 * SECURITY: sebelumnya ongkir yang dipakai create order adalah angka yang
 * DIKIRIM CLIENT (input.shippingCost) — siapa pun bisa POST order delivery
 * dengan shippingCost 0 dan total jebol (verifikasi Midtrans
 * gross_amount === order.total tetap lolos karena totalnya sendiri sudah
 * tercemar). Sekarang tarif SELALU di-resolve di server dari courierCode +
 * tujuan + berat item yang sama dengan yang dipakai mengutip.
 *
 * Mode tanpa Biteship (isBiteshipEnabled() false): tarif flat dari
 * dummyRates() — konstanta server, jadi tetap bisa diverifikasi tanpa
 * panggilan API.
 *
 * FAIL-CLOSED: resolveServerShippingFee tidak pernah mengembalikan angka
 * tebakan. Biteship gagal / kurir tidak dikenal → ok:false dan caller WAJIB
 * menggagalkan order, bukan jatuh ke angka client.
 */
import { isBiteshipEnabled } from "@/lib/biteship";
import {
  getOriginCoordinates,
  resolveOriginAreaId,
  SHIPPING_ORIGIN_UNAVAILABLE_MESSAGE,
} from "@/lib/shipping-origin";

export type ShippingItem = {
  name: string;
  price: number;
  weightGram: number;
  quantity: number;
};

export type RateOption = {
  courier_name: string;
  courier_code: string;
  courier_service_name: string;
  courier_service_code: string;
  service_type: string;
  price: number;
  duration: string;
  available: boolean;
  unavailable_reason?: string;
  description?: string;
};

export type FetchShippingRatesErrorReason =
  | "ORIGIN_NOT_CONFIGURED"
  | "ITEMS_EMPTY"
  | "INVALID_DESTINATION"
  | "BITESHIP_HTTP"
  | "BITESHIP_NETWORK";

export type FetchShippingRatesResult =
  | {
      ok: true;
      rates: RateOption[];
      /** Terisi hanya untuk mode dummy/flat. */
      message?: string;
      instantUnavailableReason: string | null;
    }
  | { ok: false; reason: FetchShippingRatesErrorReason; message: string };

export type ResolvedShippingFee =
  | { ok: true; price: number; rate: RateOption }
  | {
      ok: false;
      /** "unavailable" = Biteship/origin bermasalah; "courier-not-found" = kombinasi kurir+layanan tidak menghasilkan tarif. */
      reason: "unavailable" | "courier-not-found";
      message: string;
    };

const COURIERS = "gojek,grab,jne,jnt";

function numberOrNull(value: unknown) {
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

/**
 * Utip daftar tarif. Urutan pengecekan mengikuti endpoint lama supaya
 * bentuk respons tidak berubah: dummy/flat diprioritaskan sebelum
 * validasi item/tujuan (mode dummy mengabaikan tujuan — admin konfirmasi
 * ongkir final setelah order dibuat).
 */
export async function fetchShippingRateOptions(params: {
  originAreaId?: string | null;
  destinationAreaId?: string | null;
  destinationPostalCode?: string | null;
  destinationLatitude?: number | null;
  destinationLongitude?: number | null;
  items: ShippingItem[];
}): Promise<FetchShippingRatesResult> {
  const apiKey = process.env.BITESHIP_API_KEY;
  const originAreaId = params.originAreaId ?? null;
  const { latitude: originLatitude, longitude: originLongitude } =
    getOriginCoordinates();
  const originHasCoordinates =
    originLatitude !== null && originLongitude !== null;
  const destinationLatitude = numberOrNull(params.destinationLatitude);
  const destinationLongitude = numberOrNull(params.destinationLongitude);
  const destinationHasCoordinates =
    destinationLatitude !== null && destinationLongitude !== null;

  if (!isBiteshipEnabled()) {
    return {
      ok: true,
      rates: dummyRates(),
      instantUnavailableReason: null,
      message:
        "Pengiriman dihitung dengan tarif flat. Admin akan konfirmasi ongkir final setelah order dibuat.",
    };
  }
  // Defensive: theoretically unreachable karena isBiteshipEnabled sudah
  // check apiKey, tapi keep untuk type-safety.
  if (!apiKey) {
    return {
      ok: true,
      rates: dummyRates(),
      instantUnavailableReason: null,
      message: "Tarif pengiriman estimasi.",
    };
  }
  if (!originAreaId) {
    return {
      ok: false,
      reason: "ORIGIN_NOT_CONFIGURED",
      message: SHIPPING_ORIGIN_UNAVAILABLE_MESSAGE,
    };
  }
  if (params.items.length === 0) {
    return {
      ok: false,
      reason: "ITEMS_EMPTY",
      message: "Items kosong — tidak bisa hitung ongkir.",
    };
  }
  const destinationAreaId = String(params.destinationAreaId ?? "").trim();
  if (!destinationAreaId) {
    return {
      ok: false,
      reason: "INVALID_DESTINATION",
      message:
        "Alamat pengiriman belum valid. Mohon pilih ulang kota/kecamatan dari daftar alamat.",
    };
  }

  // Format items sesuai spec Biteship: per item, bukan single bundle
  const biteshipItems = params.items.map((item) => ({
    name: item.name.slice(0, 100),
    description: item.name.slice(0, 100),
    value: Math.max(0, item.price),
    weight: Math.max(1, item.weightGram),
    quantity: Math.max(1, item.quantity),
  }));
  const destinationPostal = String(params.destinationPostalCode ?? "").trim();

  try {
    const res = await fetch("https://api.biteship.com/v1/rates/couriers", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: apiKey,
      },
      body: JSON.stringify({
        origin_area_id: originAreaId,
        destination_area_id: destinationAreaId,
        ...(destinationPostal ? { destination_postal_code: Number(destinationPostal) } : {}),
        ...(originHasCoordinates
          ? { origin_latitude: originLatitude, origin_longitude: originLongitude }
          : {}),
        ...(destinationHasCoordinates
          ? { destination_latitude: destinationLatitude, destination_longitude: destinationLongitude }
          : {}),
        couriers: COURIERS,
        items: biteshipItems,
      }),
    });

    if (!res.ok) {
      const text = await res.text();
      console.error("[shipping] Biteship rates error:", text);
      return {
        ok: false,
        reason: "BITESHIP_HTTP",
        message:
          "Alamat pengiriman belum valid. Mohon pilih ulang kota/kecamatan dari daftar alamat.",
      };
    }

    const data = await res.json();
    const pricing: RawPricing[] = Array.isArray(data.pricing) ? data.pricing : [];

    // Map → RateOption. Field has_cod/is_cod TIDAK ikut (abaikan).
    const rates: RateOption[] = pricing.map((p) => {
      const price = typeof p.price === "number" ? p.price : 0;
      return {
        courier_name: p.courier_name ?? p.courier_code ?? "Unknown",
        courier_code: p.courier_code,
        courier_service_name: p.courier_service_name ?? p.courier_service_code,
        courier_service_code: p.type ?? p.courier_service_code,
        service_type: normalizeServiceType(p.service_type, p.duration, p.type ?? p.courier_service_code),
        price,
        duration: formatDuration(p.duration, p.shipment_duration_range, p.shipment_duration_unit),
        available: price > 0,
        unavailable_reason:
          price > 0 ? undefined : "Tidak tersedia untuk rute / berat ini.",
        description: p.description,
      };
    });

    const hasInstantRates = rates.some((rate) => {
      const courierCode = rate.courier_code.toLowerCase();
      return (
        (courierCode === "gojek" || courierCode === "grab") &&
        (rate.service_type === "instant" || rate.service_type === "same_day") &&
        rate.available
      );
    });

    return {
      ok: true,
      rates,
      instantUnavailableReason: hasInstantRates
        ? null
        : !originHasCoordinates
        ? "Titik pickup toko belum dikonfigurasi untuk Gojek Instant dan Grab Instant."
        : !destinationHasCoordinates
        ? "Lengkapi titik lokasi alamat agar Gojek Instant dan Grab Instant tersedia."
        : "Gojek Instant dan Grab Instant belum tersedia untuk alamat ini.",
    };
  } catch (e) {
    console.error("[shipping] error:", e);
    return {
      ok: false,
      reason: "BITESHIP_NETWORK",
      message: "Gagal kontak Biteship. Coba lagi.",
    };
  }
}

/**
 * Resolve ongkir final untuk SATU kombinasi kurir + layanan yang dipilih
 * user. Dipakai /api/orders (penagihan) dan /api/checkout/recalculate
 * (preview). Fail-closed — caller WAJIB menggagalkan order saat ok:false.
 *
 * `originAreaId` opsional untuk test (lewati resolveOriginAreaId/DB);
 * production memanggil tanpa parameter ini.
 */
export async function resolveServerShippingFee(params: {
  courierCode?: string | null;
  courierService?: string | null;
  destinationAreaId?: string | null;
  destinationPostalCode?: string | null;
  destinationLatitude?: number | null;
  destinationLongitude?: number | null;
  items: ShippingItem[];
  originAreaId?: string | null;
}): Promise<ResolvedShippingFee> {
  const biteshipEnabled = isBiteshipEnabled();
  const originAreaId =
    params.originAreaId !== undefined
      ? params.originAreaId
      : biteshipEnabled
        ? await resolveOriginAreaId()
        : null;

  const result = await fetchShippingRateOptions({
    originAreaId,
    destinationAreaId: params.destinationAreaId ?? null,
    destinationPostalCode: params.destinationPostalCode ?? null,
    destinationLatitude: params.destinationLatitude ?? null,
    destinationLongitude: params.destinationLongitude ?? null,
    items: params.items,
  });
  if (!result.ok) {
    console.error(
      "[shipping-rates] gagal resolve ongkir:",
      result.reason,
      result.message,
    );
    return { ok: false, reason: "unavailable", message: result.message };
  }

  const courierCode = (params.courierCode ?? "").trim().toLowerCase();
  const courierService = (params.courierService ?? "").trim().toLowerCase();
  if (!courierCode || !courierService) {
    return {
      ok: false,
      reason: "courier-not-found",
      message:
        "Layanan kurir belum dipilih. Pilih ulang kurir di halaman checkout lalu coba lagi.",
    };
  }
  const rate = result.rates.find(
    (r) =>
      r.courier_code.trim().toLowerCase() === courierCode &&
      r.courier_service_code.trim().toLowerCase() === courierService,
  );
  if (!rate || !rate.available || rate.price <= 0) {
    return {
      ok: false,
      reason: "courier-not-found",
      message:
        "Tarif kurir yang dipilih tidak tersedia untuk alamat ini. Pilih ulang kurir lalu coba lagi.",
    };
  }
  return { ok: true, price: rate.price, rate };
}

type RawPricing = {
  courier_name?: string;
  courier_code: string;
  courier_service_name?: string;
  courier_service_code: string;
  service_type?: string;
  price?: number;
  duration?: string;
  shipment_duration_range?: string;
  shipment_duration_unit?: string;
  description?: string;
  type?: string;
};

function normalizeServiceType(raw?: string, duration?: string, courierType?: string): string {
  const t = `${raw ?? ""} ${courierType ?? ""}`.toLowerCase();
  if (t.trim() === "instant") return "instant";
  if (t.trim() === "same_day") return "same_day";
  if (t.trim() === "next_day") return "next_day";
  if (t.trim() === "regular") return "regular";
  if (t.trim() === "economy") return "economy";
  if (t.includes("go_send") || t.includes("gosend") || t.includes("grab_express") || t.includes("grabexpress")) return "instant";
  if (t.includes("jtr") || t.includes("trucking") || t.includes("cargo")) return "economy";
  if (t.includes("instant")) return "instant";
  if (t.includes("same_day") || t.includes("sameday") || t.includes("same day")) return "same_day";

  const d = (duration ?? "").toLowerCase();
  if (d.includes("hour") || d.includes("jam")) return "instant";
  if (d.includes("same day") || d.includes("hari ini")) return "same_day";
  if (d.includes("next day") || d.includes("besok")) return "next_day";
  const m = d.match(/(\d+)\s*-\s*(\d+)\s*day/);
  if (m && Number(m[2]) >= 5) return "economy";
  return "regular";
}

function formatDuration(duration?: string, range?: string, unit?: string): string {
  if (duration) return duration;
  if (range) return `${range} ${unit ?? "hari"}`;
  return "—";
}

function dummyRates(): RateOption[] {
  return [
    {
      courier_name: "Gojek",
      courier_code: "gojek",
      courier_service_name: "Instant",
      courier_service_code: "instant",
      service_type: "instant",
      price: 35000,
      duration: "1-2 jam",
      available: true,
    },
    {
      courier_name: "Grab",
      courier_code: "grab",
      courier_service_name: "Same Day",
      courier_service_code: "same_day",
      service_type: "same_day",
      price: 28000,
      duration: "Hari ini",
      available: true,
    },
    {
      courier_name: "JNE",
      courier_code: "jne",
      courier_service_name: "Reguler",
      courier_service_code: "reg",
      service_type: "regular",
      price: 18000,
      duration: "2-3 hari",
      available: true,
    },
    {
      courier_name: "J&T Express",
      courier_code: "jnt",
      courier_service_name: "Reguler",
      courier_service_code: "ez",
      service_type: "regular",
      price: 17000,
      duration: "2-3 hari",
      available: true,
    },
  ];
}
