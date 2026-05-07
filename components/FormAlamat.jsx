"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { AddressPinpointPicker } from "@/components/AddressPinpointPicker";

// Proxy ke wilayah.id via /api/wilayah agar tidak kena CORS error.
// Implementasi proxy: app/api/wilayah/[...path]/route.ts
const API_BASE = "/api/wilayah";
const LABELS = ["Rumah", "Kantor", "Lainnya"];

function getItems(payload) {
  return Array.isArray(payload?.data) ? payload.data : [];
}

function getCode(item) {
  return String(item?.code ?? item?.id ?? "");
}

function getName(item) {
  return String(item?.name ?? item?.nama ?? "");
}

function getPostalCode(item) {
  return String(item?.postal_code ?? item?.postalCode ?? item?.kode_pos ?? item?.kodePos ?? "");
}

function regionValue(item) {
  return JSON.stringify({
    code: getCode(item),
    name: getName(item),
    postalCode: getPostalCode(item),
  });
}

function parseRegion(value) {
  if (!value) return { code: "", name: "", postalCode: "" };
  try {
    const parsed = JSON.parse(value);
    return {
      code: String(parsed.code ?? ""),
      name: String(parsed.name ?? ""),
      postalCode: String(parsed.postalCode ?? ""),
    };
  } catch {
    return { code: value, name: "", postalCode: "" };
  }
}

function Spinner() {
  return (
    <span className="pointer-events-none absolute right-4 top-1/2 h-4 w-4 -translate-y-1/2 rounded-full border-2 border-natalo-200 border-t-natalo-600 animate-spin" />
  );
}

function Field({ label, name, value, onChange, type = "text", required = true, children, ...props }) {
  return (
    <div>
      <label className="block text-sm font-bold text-zinc-800">
        {label}
        {required && <span className="ml-1 text-natalo-600">*</span>}
      </label>
      {children ?? (
        <input
          name={name}
          type={type}
          required={required}
          value={value}
          onChange={onChange}
          className="mt-2 block w-full rounded-xl border border-zinc-200 bg-white px-4 py-3 text-sm outline-none transition focus:border-natalo-400 focus:ring-4 focus:ring-natalo-100"
          {...props}
        />
      )}
    </div>
  );
}

function RegionSelect({
  label,
  value,
  onChange,
  items,
  disabled,
  loading,
  placeholder,
  search,
  onSearch,
}) {
  const filtered = useMemo(() => {
    const term = (search ?? "").trim().toLowerCase();
    if (!term) return items;
    return items.filter((item) => getName(item).toLowerCase().includes(term));
  }, [items, search]);

  return (
    <div>
      <label className="block text-sm font-bold text-zinc-800">
        {label}
        <span className="ml-1 text-natalo-600">*</span>
      </label>
      {onSearch && (
        <input
          type="search"
          value={search}
          onChange={(event) => onSearch(event.target.value)}
          placeholder={`Cari ${label.toLowerCase()}...`}
          disabled={disabled}
          className="mt-2 block w-full rounded-xl border border-zinc-200 bg-white px-4 py-2.5 text-sm outline-none transition focus:border-natalo-400 focus:ring-4 focus:ring-natalo-100 disabled:bg-zinc-50"
        />
      )}
      <div className="relative mt-2">
        <select
          required
          value={value}
          onChange={onChange}
          disabled={disabled || loading}
          className="block w-full appearance-none rounded-xl border border-zinc-200 bg-white px-4 py-3 pr-11 text-sm outline-none transition focus:border-natalo-400 focus:ring-4 focus:ring-natalo-100 disabled:cursor-not-allowed disabled:bg-zinc-50 disabled:text-zinc-400"
        >
          <option value="">{loading ? "Memuat data..." : placeholder}</option>
          {filtered.map((item) => (
            <option key={getCode(item)} value={regionValue(item)}>
              {getName(item)}
            </option>
          ))}
        </select>
        {loading ? (
          <Spinner />
        ) : (
          <span className="pointer-events-none absolute right-4 top-1/2 -translate-y-1/2 text-zinc-400">⌄</span>
        )}
      </div>
    </div>
  );
}

export default function FormAlamat({ mode = "create", initialAddress = null }) {
  const router = useRouter();
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");

  const [provinsi, setProvinsi] = useState([]);
  const [kota, setKota] = useState([]);
  const [kecamatan, setKecamatan] = useState([]);
  const [kelurahan, setKelurahan] = useState([]);

  const [loadingProvinsi, setLoadingProvinsi] = useState(false);
  const [loadingKota, setLoadingKota] = useState(false);
  const [loadingKecamatan, setLoadingKecamatan] = useState(false);
  const [loadingKelurahan, setLoadingKelurahan] = useState(false);

  const [selectedProvinsi, setSelectedProvinsi] = useState("");
  const [selectedKota, setSelectedKota] = useState("");
  const [selectedKecamatan, setSelectedKecamatan] = useState("");
  const [selectedKelurahan, setSelectedKelurahan] = useState("");
  const [kodePos, setKodePos] = useState(initialAddress?.postalCode ?? "");

  const [searchKota, setSearchKota] = useState("");
  const [searchKecamatan, setSearchKecamatan] = useState("");

  const [form, setForm] = useState({
    recipientName: initialAddress?.recipientName ?? "",
    phone: initialAddress?.phone ?? "",
    address: initialAddress?.address ?? "",
    label: initialAddress?.label ?? "Rumah",
    isMain: Boolean(initialAddress?.isMain),
  });

  useEffect(() => {
    setLoadingProvinsi(true);
    fetch(`${API_BASE}/provinces.json`)
      .then((response) => response.json())
      .then((data) => setProvinsi(getItems(data)))
      .catch(() => setError("Gagal memuat data provinsi. Coba muat ulang halaman."))
      .finally(() => setLoadingProvinsi(false));
  }, []);

  useEffect(() => {
    if (!initialAddress || provinsi.length === 0 || selectedProvinsi) return;
    const found = provinsi.find((item) => {
      return getCode(item) === initialAddress.provinceCode || getName(item) === initialAddress.province;
    });
    if (found) setSelectedProvinsi(regionValue(found));
  }, [initialAddress, provinsi, selectedProvinsi]);

  useEffect(() => {
    const selected = parseRegion(selectedProvinsi);
    setKota([]);
    setKecamatan([]);
    setKelurahan([]);
    setSelectedKota("");
    setSelectedKecamatan("");
    setSelectedKelurahan("");
    setSearchKota("");
    setSearchKecamatan("");
    if (!selected.code) return;
    setLoadingKota(true);
    fetch(`${API_BASE}/regencies/${selected.code}.json`)
      .then((response) => response.json())
      .then((data) => setKota(getItems(data)))
      .catch(() => setError("Gagal memuat kota/kabupaten."))
      .finally(() => setLoadingKota(false));
  }, [selectedProvinsi]);

  useEffect(() => {
    if (!initialAddress || kota.length === 0 || selectedKota) return;
    const found = kota.find((item) => {
      return getCode(item) === initialAddress.cityCode || getName(item) === initialAddress.city;
    });
    if (found) setSelectedKota(regionValue(found));
  }, [initialAddress, kota, selectedKota]);

  useEffect(() => {
    const selected = parseRegion(selectedKota);
    setKecamatan([]);
    setKelurahan([]);
    setSelectedKecamatan("");
    setSelectedKelurahan("");
    setSearchKecamatan("");
    if (!selected.code) return;
    setLoadingKecamatan(true);
    fetch(`${API_BASE}/districts/${selected.code}.json`)
      .then((response) => response.json())
      .then((data) => setKecamatan(getItems(data)))
      .catch(() => setError("Gagal memuat kecamatan."))
      .finally(() => setLoadingKecamatan(false));
  }, [selectedKota]);

  useEffect(() => {
    if (!initialAddress || kecamatan.length === 0 || selectedKecamatan) return;
    const found = kecamatan.find((item) => {
      return getCode(item) === initialAddress.districtCode || getName(item) === initialAddress.district;
    });
    if (found) setSelectedKecamatan(regionValue(found));
  }, [initialAddress, kecamatan, selectedKecamatan]);

  useEffect(() => {
    const selected = parseRegion(selectedKecamatan);
    setKelurahan([]);
    setSelectedKelurahan("");
    if (!selected.code) return;
    setLoadingKelurahan(true);
    fetch(`${API_BASE}/villages/${selected.code}.json`)
      .then((response) => response.json())
      .then((data) => setKelurahan(getItems(data)))
      .catch(() => setError("Gagal memuat kelurahan."))
      .finally(() => setLoadingKelurahan(false));
  }, [selectedKecamatan]);

  useEffect(() => {
    if (!initialAddress || kelurahan.length === 0 || selectedKelurahan) return;
    const found = kelurahan.find((item) => {
      return getCode(item) === initialAddress.villageCode || getName(item) === initialAddress.village;
    });
    if (found) setSelectedKelurahan(regionValue(found));
  }, [initialAddress, kelurahan, selectedKelurahan]);

  function updateForm(field, value) {
    setForm((current) => ({ ...current, [field]: value }));
  }

  function handleKelurahanChange(event) {
    const value = event.target.value;
    setSelectedKelurahan(value);
    const selected = parseRegion(value);
    if (selected.postalCode) setKodePos(selected.postalCode);
  }

  async function handleSubmit(event) {
    event.preventDefault();
    setError("");

    // Ambil koordinat dari hidden input AddressPinpointPicker
    const formData = new FormData(event.currentTarget);
    const latitudeRaw = String(formData.get("latitude") || "").trim();
    const longitudeRaw = String(formData.get("longitude") || "").trim();
    const pinpointAddress = String(formData.get("pinpointAddress") || "").trim() || null;
    const streetName = String(formData.get("streetName") || "").trim() || null;

    // Pinpoint GPS WAJIB untuk alamat baru. Untuk edit, opsional
    // (alamat lama mungkin belum punya pinpoint — tidak boleh di-block).
    if (mode !== "edit" && (!latitudeRaw || !longitudeRaw)) {
      setError("Pinpoint titik GPS wajib diisi. Klik tombol \"Tambah Pinpoint\" untuk menentukan lokasi.");
      return;
    }

    setSubmitting(true);

    const province = parseRegion(selectedProvinsi);
    const city = parseRegion(selectedKota);
    const district = parseRegion(selectedKecamatan);
    const village = parseRegion(selectedKelurahan);

    const latitude = latitudeRaw ? Number(latitudeRaw) : null;
    const longitude = longitudeRaw ? Number(longitudeRaw) : null;

    const payload = {
      ...form,
      province,
      city,
      district,
      village,
      postalCode: kodePos.trim(),
      latitude: Number.isFinite(latitude) ? latitude : null,
      longitude: Number.isFinite(longitude) ? longitude : null,
      pinpointAddress,
      streetName,
    };

    const target = mode === "edit" ? `/api/alamat/${initialAddress.id}` : "/api/alamat";
    const method = mode === "edit" ? "PUT" : "POST";

    try {
      const response = await fetch(target, {
        method,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error ?? "Gagal menyimpan alamat.");
      router.push("/akun/alamat");
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal menyimpan alamat.");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-5">
      {error && (
        <div className="rounded-2xl border border-red-100 bg-red-50 px-4 py-3 text-sm font-semibold text-red-600">
          {error}
        </div>
      )}

      <div className="grid gap-4 sm:grid-cols-2">
        <Field
          label="Nama Penerima"
          name="recipientName"
          value={form.recipientName}
          onChange={(event) => updateForm("recipientName", event.target.value)}
          placeholder="Nama penerima paket"
        />
        <Field
          label="No. HP Penerima"
          name="phone"
          type="tel"
          value={form.phone}
          onChange={(event) => updateForm("phone", event.target.value)}
          placeholder="08xxxxxxxxxx / +628xxxxxxxxxx"
        />
      </div>

      <Field label="Alamat Lengkap" name="address" required={true}>
        <textarea
          name="address"
          required
          rows={4}
          value={form.address}
          onChange={(event) => updateForm("address", event.target.value)}
          placeholder="Nama jalan, nomor rumah, RT/RW, patokan"
          className="mt-2 block w-full rounded-xl border border-zinc-200 bg-white px-4 py-3 text-sm outline-none transition focus:border-natalo-400 focus:ring-4 focus:ring-natalo-100"
        />
      </Field>

      <div className="grid gap-4 sm:grid-cols-2">
        <RegionSelect
          label="Provinsi"
          value={selectedProvinsi}
          onChange={(event) => setSelectedProvinsi(event.target.value)}
          items={provinsi}
          loading={loadingProvinsi}
          disabled={false}
          placeholder="Pilih provinsi"
        />
        <RegionSelect
          label="Kota / Kabupaten"
          value={selectedKota}
          onChange={(event) => setSelectedKota(event.target.value)}
          items={kota}
          loading={loadingKota}
          disabled={!selectedProvinsi}
          placeholder={!selectedProvinsi ? "Pilih provinsi dulu" : "Pilih kota/kabupaten"}
          search={searchKota}
          onSearch={setSearchKota}
        />
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <RegionSelect
          label="Kecamatan"
          value={selectedKecamatan}
          onChange={(event) => setSelectedKecamatan(event.target.value)}
          items={kecamatan}
          loading={loadingKecamatan}
          disabled={!selectedKota}
          placeholder={!selectedKota ? "Pilih kota dulu" : "Pilih kecamatan"}
          search={searchKecamatan}
          onSearch={setSearchKecamatan}
        />
        <RegionSelect
          label="Kelurahan"
          value={selectedKelurahan}
          onChange={handleKelurahanChange}
          items={kelurahan}
          loading={loadingKelurahan}
          disabled={!selectedKecamatan}
          placeholder={!selectedKecamatan ? "Pilih kecamatan dulu" : "Pilih kelurahan"}
        />
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <Field
          label="Kode Pos"
          name="postalCode"
          value={kodePos}
          onChange={(event) => setKodePos(event.target.value)}
          placeholder="Otomatis dari kelurahan"
          inputMode="numeric"
        />
        <Field label="Label Alamat" name="label" required={false}>
          <select
            name="label"
            value={form.label}
            onChange={(event) => updateForm("label", event.target.value)}
            className="mt-2 block w-full rounded-xl border border-zinc-200 bg-white px-4 py-3 text-sm outline-none transition focus:border-natalo-400 focus:ring-4 focus:ring-natalo-100"
          >
            {LABELS.map((label) => (
              <option key={label} value={label}>
                {label}
              </option>
            ))}
          </select>
        </Field>
      </div>

      <div>
        <p className="text-sm font-bold text-zinc-800">
          Pinpoint Lokasi GPS
          {mode !== "edit" && <span className="ml-1 text-natalo-600">*</span>}
        </p>
        <p className="mt-1 text-xs text-zinc-500">
          {mode !== "edit"
            ? "Wajib diisi. Pin titik tepat agar kurir mudah menemukan alamatmu."
            : "Pin titik tepat agar kurir mudah menemukan alamatmu."}
        </p>
        <div className="mt-2">
          <AddressPinpointPicker
            defaultLatitude={initialAddress?.latitude ?? null}
            defaultLongitude={initialAddress?.longitude ?? null}
            defaultAddress={initialAddress?.pinpointAddress ?? null}
            defaultStreetName={initialAddress?.streetName ?? null}
          />
        </div>
      </div>

      <label className="flex cursor-pointer items-center justify-between gap-4 rounded-2xl border border-natalo-100 bg-natalo-50 px-4 py-3">
        <span>
          <span className="block text-sm font-black text-zinc-900">Alamat Utama</span>
          <span className="block text-xs font-semibold text-natalo-800">
            Pakai alamat ini sebagai default saat checkout.
          </span>
        </span>
        <input
          type="checkbox"
          checked={form.isMain}
          onChange={(event) => updateForm("isMain", event.target.checked)}
          className="h-5 w-5 rounded border-natalo-300 text-natalo-600 focus:ring-natalo-400"
        />
      </label>

      <div className="flex flex-wrap gap-3 pt-2">
        <button
          type="submit"
          disabled={submitting}
          className="rounded-full bg-natalo-600 px-6 py-3 text-sm font-black text-white transition hover:bg-natalo-700 disabled:cursor-not-allowed disabled:opacity-60"
        >
          {submitting ? "Menyimpan..." : mode === "edit" ? "Simpan perubahan" : "Simpan alamat"}
        </button>
        <button
          type="button"
          onClick={() => router.push("/akun/alamat")}
          className="rounded-full border border-zinc-200 px-6 py-3 text-sm font-bold text-zinc-700 transition hover:border-zinc-400"
        >
          Batal
        </button>
      </div>
    </form>
  );
}
