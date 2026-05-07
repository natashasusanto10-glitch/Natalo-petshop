"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { AddressPinpointPicker } from "@/components/AddressPinpointPicker";

const LABELS = ["Rumah", "Kantor", "Lainnya"];

function getRegionCode(item) {
  return String(item?.code ?? item?.id ?? item?.kode ?? "").trim();
}

function getRegionName(item) {
  return String(item?.name ?? item?.nama ?? "").trim();
}

function getPostalCode(item) {
  return String(
    item?.postal_code ?? item?.postalCode ?? item?.kode_pos ?? item?.zip_code ?? ""
  ).trim();
}

function getData(payload) {
  if (Array.isArray(payload)) return payload;
  if (Array.isArray(payload?.data)) return payload.data;
  return [];
}

async function fetchWilayah(path) {
  const response = await fetch(`/api/wilayah/${path}`, { cache: "force-cache" });
  const payload = await response.json();
  if (!response.ok) throw new Error(payload.error ?? "Gagal mengambil data wilayah.");
  return getData(payload);
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

function SelectField({
  label,
  value,
  onChange,
  options,
  placeholder,
  disabled,
  loading,
  required = true,
}) {
  return (
    <div>
      <label className="block text-sm font-bold text-zinc-800">
        {label}
        {required && <span className="ml-1 text-natalo-600">*</span>}
      </label>
      <div className="relative mt-2">
        <select
          required={required}
          value={value}
          onChange={(event) => onChange(event.target.value)}
          disabled={disabled || loading}
          className="block w-full rounded-xl border border-zinc-200 bg-white px-4 py-3 pr-10 text-sm outline-none transition focus:border-natalo-400 focus:ring-4 focus:ring-natalo-100 disabled:cursor-not-allowed disabled:bg-zinc-50 disabled:text-zinc-400"
        >
          <option value="">{loading ? "Memuat data..." : placeholder}</option>
          {options.map((option) => {
            const code = getRegionCode(option);
            const name = getRegionName(option);
            return (
              <option key={code || name} value={code}>
                {name}
              </option>
            );
          })}
        </select>
        {loading && (
          <span className="absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 animate-spin rounded-full border-2 border-zinc-200 border-t-natalo-600" />
        )}
      </div>
    </div>
  );
}

export default function FormAlamat({ mode = "create", initialAddress = null }) {
  const router = useRouter();
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");

  const [form, setForm] = useState({
    recipient: initialAddress?.recipient ?? "",
    phone: initialAddress?.phone ?? "",
    address: initialAddress?.address ?? "",
    city: initialAddress?.city ?? "",
    postalCode: initialAddress?.postalCode ?? "",
    label: initialAddress?.label ?? "Rumah",
    isMain: Boolean(initialAddress?.isMain),
  });

  const [provinsi, setProvinsi] = useState([]);
  const [kota, setKota] = useState([]);
  const [kecamatan, setKecamatan] = useState([]);
  const [kelurahan, setKelurahan] = useState([]);

  const [selectedProvinsi, setSelectedProvinsi] = useState("");
  const [selectedKota, setSelectedKota] = useState("");
  const [selectedKecamatan, setSelectedKecamatan] = useState("");
  const [selectedKelurahan, setSelectedKelurahan] = useState("");

  const [loadingProvinsi, setLoadingProvinsi] = useState(true);
  const [loadingKota, setLoadingKota] = useState(false);
  const [loadingKecamatan, setLoadingKecamatan] = useState(false);
  const [loadingKelurahan, setLoadingKelurahan] = useState(false);

  const [kotaSearch, setKotaSearch] = useState("");
  const [kecamatanSearch, setKecamatanSearch] = useState("");

  function updateForm(field, value) {
    setForm((current) => ({ ...current, [field]: value }));
  }

  useEffect(() => {
    let active = true;
    setLoadingProvinsi(true);
    fetchWilayah("provinces.json")
      .then((items) => {
        if (active) setProvinsi(items);
      })
      .catch((err) => {
        if (active) setError(err instanceof Error ? err.message : "Gagal memuat provinsi.");
      })
      .finally(() => {
        if (active) setLoadingProvinsi(false);
      });
    return () => {
      active = false;
    };
  }, []);

  useEffect(() => {
    setSelectedKota("");
    setSelectedKecamatan("");
    setSelectedKelurahan("");
    setKota([]);
    setKecamatan([]);
    setKelurahan([]);
    setKotaSearch("");
    setKecamatanSearch("");

    if (!selectedProvinsi) return;

    let active = true;
    setLoadingKota(true);
    fetchWilayah(`regencies/${selectedProvinsi}.json`)
      .then((items) => {
        if (active) setKota(items);
      })
      .catch((err) => {
        if (active) setError(err instanceof Error ? err.message : "Gagal memuat kota/kabupaten.");
      })
      .finally(() => {
        if (active) setLoadingKota(false);
      });
    return () => {
      active = false;
    };
  }, [selectedProvinsi]);

  useEffect(() => {
    setSelectedKecamatan("");
    setSelectedKelurahan("");
    setKecamatan([]);
    setKelurahan([]);
    setKecamatanSearch("");

    if (!selectedKota) return;

    let active = true;
    setLoadingKecamatan(true);
    fetchWilayah(`districts/${selectedKota}.json`)
      .then((items) => {
        if (active) setKecamatan(items);
      })
      .catch((err) => {
        if (active) setError(err instanceof Error ? err.message : "Gagal memuat kecamatan.");
      })
      .finally(() => {
        if (active) setLoadingKecamatan(false);
      });
    return () => {
      active = false;
    };
  }, [selectedKota]);

  useEffect(() => {
    setSelectedKelurahan("");
    setKelurahan([]);

    if (!selectedKecamatan) return;

    let active = true;
    setLoadingKelurahan(true);
    fetchWilayah(`villages/${selectedKecamatan}.json`)
      .then((items) => {
        if (active) setKelurahan(items);
      })
      .catch((err) => {
        if (active) setError(err instanceof Error ? err.message : "Gagal memuat kelurahan.");
      })
      .finally(() => {
        if (active) setLoadingKelurahan(false);
      });
    return () => {
      active = false;
    };
  }, [selectedKecamatan]);

  const selectedNames = useMemo(() => {
    const province = provinsi.find((item) => getRegionCode(item) === selectedProvinsi);
    const regency = kota.find((item) => getRegionCode(item) === selectedKota);
    const district = kecamatan.find((item) => getRegionCode(item) === selectedKecamatan);
    const village = kelurahan.find((item) => getRegionCode(item) === selectedKelurahan);
    return {
      province: getRegionName(province),
      regency: getRegionName(regency),
      district: getRegionName(district),
      village: getRegionName(village),
      postalCode: getPostalCode(village),
    };
  }, [provinsi, kota, kecamatan, kelurahan, selectedProvinsi, selectedKota, selectedKecamatan, selectedKelurahan]);

  useEffect(() => {
    if (!selectedKelurahan) return;
    const parts = [
      selectedNames.village,
      selectedNames.district,
      selectedNames.regency,
      selectedNames.province,
    ].filter(Boolean);

    setForm((current) => ({
      ...current,
      city: parts.join(", "),
      postalCode: selectedNames.postalCode || current.postalCode,
    }));
  }, [selectedKelurahan, selectedNames]);

  const filteredKota = useMemo(() => {
    const q = kotaSearch.trim().toLowerCase();
    if (!q) return kota;
    return kota.filter((item) => getRegionName(item).toLowerCase().includes(q));
  }, [kota, kotaSearch]);

  const filteredKecamatan = useMemo(() => {
    const q = kecamatanSearch.trim().toLowerCase();
    if (!q) return kecamatan;
    return kecamatan.filter((item) => getRegionName(item).toLowerCase().includes(q));
  }, [kecamatan, kecamatanSearch]);

  async function handleSubmit(event) {
    event.preventDefault();
    setError("");
    setSubmitting(true);

    const formData = new FormData(event.currentTarget);
    const latitudeRaw = String(formData.get("latitude") || "").trim();
    const longitudeRaw = String(formData.get("longitude") || "").trim();
    const pinpointAddress = String(formData.get("pinpointAddress") || "").trim() || null;
    const streetName = String(formData.get("streetName") || "").trim() || null;

    const latitude = latitudeRaw ? Number(latitudeRaw) : null;
    const longitude = longitudeRaw ? Number(longitudeRaw) : null;

    const payload = {
      ...form,
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
          name="recipient"
          value={form.recipient}
          onChange={(event) => updateForm("recipient", event.target.value)}
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

      <Field label="Alamat Lengkap" name="address">
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

      {initialAddress?.city && mode === "edit" && (
        <div className="rounded-2xl border border-zinc-100 bg-zinc-50 px-4 py-3 text-sm text-zinc-600">
          Wilayah tersimpan: <span className="font-semibold">{initialAddress.city}</span>
        </div>
      )}

      <div className="grid gap-4 sm:grid-cols-2">
        <SelectField
          label="Provinsi"
          value={selectedProvinsi}
          onChange={setSelectedProvinsi}
          options={provinsi}
          placeholder="Pilih provinsi"
          loading={loadingProvinsi}
          required={mode !== "edit"}
        />

        <div>
          <input
            type="search"
            value={kotaSearch}
            onChange={(event) => setKotaSearch(event.target.value)}
            disabled={!selectedProvinsi || loadingKota}
            placeholder="Cari kota/kabupaten"
            className="mb-2 block w-full rounded-xl border border-zinc-200 bg-white px-4 py-2 text-sm outline-none transition focus:border-natalo-400 focus:ring-4 focus:ring-natalo-100 disabled:bg-zinc-50"
          />
          <SelectField
            label="Kota / Kabupaten"
            value={selectedKota}
            onChange={setSelectedKota}
            options={filteredKota}
            placeholder="Pilih kota/kabupaten"
            disabled={!selectedProvinsi}
            loading={loadingKota}
            required={mode !== "edit"}
          />
        </div>

        <div>
          <input
            type="search"
            value={kecamatanSearch}
            onChange={(event) => setKecamatanSearch(event.target.value)}
            disabled={!selectedKota || loadingKecamatan}
            placeholder="Cari kecamatan"
            className="mb-2 block w-full rounded-xl border border-zinc-200 bg-white px-4 py-2 text-sm outline-none transition focus:border-natalo-400 focus:ring-4 focus:ring-natalo-100 disabled:bg-zinc-50"
          />
          <SelectField
            label="Kecamatan"
            value={selectedKecamatan}
            onChange={setSelectedKecamatan}
            options={filteredKecamatan}
            placeholder="Pilih kecamatan"
            disabled={!selectedKota}
            loading={loadingKecamatan}
            required={mode !== "edit"}
          />
        </div>

        <SelectField
          label="Kelurahan"
          value={selectedKelurahan}
          onChange={setSelectedKelurahan}
          options={kelurahan}
          placeholder="Pilih kelurahan"
          disabled={!selectedKecamatan}
          loading={loadingKelurahan}
          required={mode !== "edit"}
        />
      </div>

      <Field
        label="Kode Pos"
        name="postalCode"
        value={form.postalCode}
        onChange={(event) => updateForm("postalCode", event.target.value)}
        placeholder="Otomatis setelah pilih kelurahan, bisa diedit"
        inputMode="numeric"
      />

      <input type="hidden" name="city" value={form.city} />

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

      <div>
        <p className="text-sm font-bold text-zinc-800">Pinpoint Lokasi GPS</p>
        <p className="mt-1 text-xs text-zinc-500">
          Opsional. Pin titik tepat agar kurir lebih mudah menemukan alamatmu.
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
