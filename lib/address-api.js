import { findBiteshipAreaForAddress } from "@/lib/biteship-area";

const PHONE_RE = /^(\+62|62|0)8[1-9][0-9]{6,11}$/;
const VALID_LABELS = new Set(["Rumah", "Kantor"]);

export function coordinateOrNull(value) {
  if (value === null || value === undefined || value === "") return null;
  if (typeof value === "string" && !value.trim()) return null;
  const coordinate = Number(value);
  return Number.isFinite(coordinate) ? coordinate : null;
}

function text(value) {
  return String(value ?? "").trim();
}

function firstText(...values) {
  for (const value of values) {
    const normalized = text(value);
    if (normalized) return normalized;
  }
  return "";
}

function normalizeCity(value) {
  if (typeof value === "object" && value !== null) return text(value.name);
  return text(value);
}

function normalizeLabel(value) {
  const label = text(value);
  return VALID_LABELS.has(label) ? label : null;
}

export function normalizeAddressPayload(body = {}) {
  const latitude = coordinateOrNull(firstText(body.latitude, body.lat));
  const longitude = coordinateOrNull(firstText(body.longitude, body.lng));
  const city = normalizeCity(firstText(body.city, body.kota, body.cityName, body.city_name));
  const cityName = firstText(body.cityName, body.city_name, body.kota, city);
  const provinceName = firstText(body.provinceName, body.province_name, body.province, body.provinsi);
  const districtName = firstText(body.districtName, body.district_name, body.district, body.kecamatan);
  const postalCode = firstText(body.postalCode, body.postal_code, body.kodePos, body.kode_pos);
  const street = firstText(body.address, body.street, body.jalan);

  return {
    label: normalizeLabel(body.label),
    recipient: firstText(body.recipient, body.recipientName, body.recipient_name, body.nama),
    phone: text(body.phone),
    address: street,
    city,
    postalCode,
    areaId: firstText(body.areaId, body.area_id),
    areaLabel: firstText(body.areaLabel, body.area_label),
    provinceName,
    cityName,
    districtName,
    isMain: Boolean(body.isMain ?? body.is_primary ?? body.isUtama),
    latitude,
    longitude,
    pinpointAddress: firstText(body.pinpointAddress, body.pinpoint_address) || null,
    streetName: firstText(body.streetName, body.street_name, body.detail) || null,
  };
}

export function validateAddressPayload(payload) {
  const phone = payload.phone.replace(/\s/g, "");
  const hasManualRegion =
    Boolean(payload.provinceName) && Boolean(payload.cityName || payload.city) && Boolean(payload.districtName);

  if (!payload.recipient || payload.recipient.length < 2) {
    return "Mohon lengkapi Nama Lengkap minimal 2 karakter.";
  }
  if (!payload.phone) return "Mohon lengkapi Nomor Telepon.";
  if (!PHONE_RE.test(phone)) {
    return "Nomor Telepon harus format Indonesia, contoh 081234567890 atau +628123456789.";
  }
  if (!payload.areaId && !hasManualRegion) {
    return "Mohon lengkapi Provinsi, Kota / Kabupaten, dan Kecamatan.";
  }
  if (!payload.postalCode) return "Mohon lengkapi Kode Pos.";
  if (!payload.address || payload.address.length < 5) {
    return "Mohon lengkapi Nama Jalan minimal 5 karakter.";
  }
  if (payload.label && !VALID_LABELS.has(payload.label)) {
    return "Label alamat hanya boleh Rumah atau Kantor.";
  }
  if (payload.latitude !== null && (payload.latitude < -90 || payload.latitude > 90)) {
    return "Koordinat latitude tidak valid.";
  }
  if (payload.longitude !== null && (payload.longitude < -180 || payload.longitude > 180)) {
    return "Koordinat longitude tidak valid.";
  }
  if (
    payload.latitude !== null &&
    payload.longitude !== null &&
    (payload.latitude < -11.2 ||
      payload.latitude > 6.3 ||
      payload.longitude < 94.5 ||
      payload.longitude > 141.5)
  ) {
    return "Alamat harus berada di Indonesia.";
  }

  return null;
}

export function addressDataFromPayload(payload, userId) {
  return {
    ...(userId ? { userId } : {}),
    label: payload.label,
    recipient: payload.recipient,
    phone: payload.phone.replace(/\s/g, ""),
    address: payload.address,
    city: payload.city || payload.cityName || null,
    postalCode: payload.postalCode,
    areaId: payload.areaId || null,
    areaLabel:
      payload.areaLabel ||
      [payload.districtName, payload.cityName || payload.city, payload.provinceName]
        .filter(Boolean)
        .join(", ") ||
      null,
    provinceName: payload.provinceName || null,
    cityName: payload.cityName || payload.city || null,
    districtName: payload.districtName || null,
    latitude: payload.latitude,
    longitude: payload.longitude,
    pinpointAddress: payload.pinpointAddress,
    streetName: payload.streetName,
  };
}

export async function enrichAddressPayload(payload) {
  if (payload.areaId) return payload;

  const area = await findBiteshipAreaForAddress(payload).catch(() => null);
  if (!area) return payload;

  return {
    ...payload,
    areaId: area.area_id,
    areaLabel: area.label,
    provinceName: payload.provinceName || area.province_name,
    city: payload.city || area.city_name,
    cityName: payload.cityName || area.city_name,
    districtName: payload.districtName || area.district_name,
    postalCode: payload.postalCode || area.postal_code,
  };
}

export async function biteshipAreaPatchForAddress(address) {
  if (address?.areaId) return null;

  const payload = normalizeAddressPayload(address);
  const enriched = await enrichAddressPayload(payload);
  if (!enriched.areaId) return null;

  return {
    areaId: enriched.areaId,
    areaLabel: enriched.areaLabel,
    provinceName: enriched.provinceName || null,
    city: enriched.city || enriched.cityName || null,
    cityName: enriched.cityName || enriched.city || null,
    districtName: enriched.districtName || null,
    postalCode: enriched.postalCode,
  };
}
