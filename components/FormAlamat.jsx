"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";

const LABELS = ["Rumah", "Kantor", "Toko", "Lainnya"];
const KODEPOS_API = "https://kodepos.vercel.app/search";
const GOOGLE_API_KEY =
  process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY ??
  process.env.NEXT_PUBLIC_GOOGLE_MAPS_KEY ??
  "";
const INPUT_CLASS =
  "mt-2 block w-full rounded-xl border border-zinc-200 bg-white px-4 py-3 text-sm outline-none transition focus:border-natalo-400 focus:ring-4 focus:ring-natalo-100 disabled:cursor-not-allowed disabled:bg-zinc-50 disabled:text-zinc-400";
const CHECKOUT_SELECTED_ADDRESS_KEY = "checkout:selectedAddressId";
const CHECKOUT_ADDRESS_FORCE_APPLY_KEY = "checkout:addressForceApply";

let googleMapsPromise = null;

function loadGoogleMaps() {
  if (typeof window === "undefined") return Promise.reject(new Error("Browser belum tersedia."));
  if (!GOOGLE_API_KEY) return Promise.reject(new Error("Google Maps API key belum tersedia."));
  if (googleMapsPromise) return googleMapsPromise;

  googleMapsPromise = new Promise((resolve, reject) => {
    if (window.google?.maps?.places) {
      resolve(window.google.maps);
      return;
    }

    const existing = document.querySelector("script[data-address-google-maps='true']");
    if (existing) {
      existing.addEventListener("load", () => resolve(window.google.maps), { once: true });
      existing.addEventListener("error", reject, { once: true });
      return;
    }

    const script = document.createElement("script");
    script.src = `https://maps.googleapis.com/maps/api/js?key=${GOOGLE_API_KEY}&libraries=places&loading=async`;
    script.async = true;
    script.defer = true;
    script.dataset.addressGoogleMaps = "true";
    script.onload = () => resolve(window.google.maps);
    script.onerror = reject;
    document.head.appendChild(script);
  });

  return googleMapsPromise;
}

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

function toOption(item) {
  return { value: getRegionCode(item), label: getRegionName(item), postalCode: getPostalCode(item) };
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

function Field({
  label,
  name,
  value,
  onChange,
  type = "text",
  required = true,
  error,
  help,
  children,
  ...props
}) {
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
          className={INPUT_CLASS}
          {...props}
        />
      )}
      {help && !error && <p className="mt-1 text-xs font-medium text-zinc-500">{help}</p>}
      {error && <p className="mt-1 text-xs font-semibold text-red-500">{error}</p>}
    </div>
  );
}

function SearchableSelect({ options, value, onChange, placeholder, disabled, loading }) {
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState("");
  const wrapperRef = useRef(null);
  const inputRef = useRef(null);

  useEffect(() => {
    function handler(event) {
      if (wrapperRef.current && !wrapperRef.current.contains(event.target)) {
        setOpen(false);
        setSearch("");
      }
    }
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, []);

  useEffect(() => {
    if (!open) return;
    setSearch("");
    window.setTimeout(() => inputRef.current?.focus(), 0);
  }, [open]);

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    if (!q) return options;
    return options.filter((option) => option.label.toLowerCase().includes(q));
  }, [options, search]);

  return (
    <div className="relative mt-2" ref={wrapperRef}>
      <button
        type="button"
        disabled={disabled || loading}
        onClick={() => !(disabled || loading) && setOpen((current) => !current)}
        className={`flex w-full items-center justify-between rounded-xl border border-zinc-200 bg-white px-4 py-3 text-left text-sm outline-none transition focus:border-natalo-400 focus:ring-4 focus:ring-natalo-100 disabled:cursor-not-allowed disabled:bg-zinc-50 disabled:text-zinc-400 ${
          disabled || loading ? "" : "hover:border-zinc-300"
        }`}
      >
        <span className={value ? "text-zinc-900" : "text-zinc-400"}>
          {loading ? "Memuat data..." : value?.label || placeholder}
        </span>
        <span className="ml-2 text-zinc-400">v</span>
      </button>

      {open && !(disabled || loading) && (
        <div className="absolute z-30 mt-1 w-full overflow-hidden rounded-xl border border-zinc-200 bg-white shadow-xl">
          <div className="border-b border-zinc-100 p-2">
            <input
              ref={inputRef}
              type="search"
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder="Cari..."
              className="w-full rounded-lg border border-zinc-200 px-3 py-2 text-sm outline-none focus:border-natalo-400"
            />
          </div>
          <div className="max-h-64 overflow-y-auto">
            {filtered.length === 0 ? (
              <div className="px-4 py-5 text-center text-sm text-zinc-500">Tidak ada hasil</div>
            ) : (
              filtered.map((option) => (
                <button
                  key={option.value}
                  type="button"
                  onClick={() => {
                    onChange(option);
                    setOpen(false);
                    setSearch("");
                  }}
                  className={`block w-full px-4 py-2.5 text-left text-sm hover:bg-natalo-50 ${
                    value?.value === option.value ? "bg-natalo-50 font-bold text-natalo-700" : "text-zinc-700"
                  }`}
                >
                  {option.label}
                </button>
              ))
            )}
          </div>
        </div>
      )}
    </div>
  );
}

function SelectField({ label, value, onChange, options, placeholder, disabled, loading, required = true }) {
  const normalizedOptions = useMemo(() => options.map(toOption).filter((option) => option.value), [options]);
  const selected = normalizedOptions.find((option) => option.value === value) ?? null;

  return (
    <div>
      <label className="block text-sm font-bold text-zinc-800">
        {label}
        {required && <span className="ml-1 text-natalo-600">*</span>}
      </label>
      <SearchableSelect
        options={normalizedOptions}
        value={selected}
        onChange={(option) => onChange(option.value)}
        placeholder={placeholder}
        disabled={disabled}
        loading={loading}
      />
    </div>
  );
}

function SelectFieldWithError({
  label,
  value,
  onChange,
  options,
  placeholder,
  disabled,
  loading,
  required = true,
  error,
}) {
  return (
    <div>
      <SelectField
        label={label}
        value={value}
        onChange={onChange}
        options={options}
        placeholder={placeholder}
        disabled={disabled}
        loading={loading}
        required={required}
      />
      {error && <p className="mt-1 text-xs font-semibold text-red-500">{error}</p>}
    </div>
  );
}

function PlaceAutocompleteField({
  label,
  placeholder,
  value,
  onChange,
  biasContext,
  onSelectPlace,
  disabled,
}) {
  const [suggestions, setSuggestions] = useState([]);
  const [open, setOpen] = useState(false);
  const [ready, setReady] = useState(false);
  const [mapsError, setMapsError] = useState("");
  const sessionTokenRef = useRef(null);
  const autocompleteRef = useRef(null);
  const placesServiceRef = useRef(null);
  const debounceRef = useRef(null);

  useEffect(() => {
    let active = true;
    loadGoogleMaps()
      .then((maps) => {
        if (!active) return;
        autocompleteRef.current = new maps.places.AutocompleteService();
        placesServiceRef.current = new maps.places.PlacesService(document.createElement("div"));
        sessionTokenRef.current = new maps.places.AutocompleteSessionToken();
        setReady(true);
        setMapsError("");
      })
      .catch(() => {
        if (active) setMapsError("Google Places belum bisa dimuat.");
      });
    return () => {
      active = false;
    };
  }, []);

  useEffect(() => {
    if (!ready || disabled || !value || value.length < 3) {
      setSuggestions([]);
      return;
    }

    window.clearTimeout(debounceRef.current);
    debounceRef.current = window.setTimeout(() => {
      const query = `${value} ${biasContext}`.trim();
      autocompleteRef.current?.getPlacePredictions(
        {
          input: query,
          sessionToken: sessionTokenRef.current,
          componentRestrictions: { country: "id" },
        },
        (predictions, status) => {
          setSuggestions(status === "OK" && predictions ? predictions.slice(0, 5) : []);
        }
      );
    }, 300);

    return () => window.clearTimeout(debounceRef.current);
  }, [value, biasContext, ready, disabled]);

  function handleSelect(prediction) {
    placesServiceRef.current?.getDetails(
      {
        placeId: prediction.place_id,
        fields: ["formatted_address", "geometry", "name"],
        sessionToken: sessionTokenRef.current,
      },
      (place, status) => {
        if (status !== "OK" || !place?.geometry?.location) return;
        onSelectPlace({
          mainText: prediction.structured_formatting.main_text,
          formattedAddress: place.formatted_address,
          lat: place.geometry.location.lat(),
          lng: place.geometry.location.lng(),
        });
        setOpen(false);
        setSuggestions([]);
        sessionTokenRef.current = new window.google.maps.places.AutocompleteSessionToken();
      }
    );
  }

  return (
    <div className="relative">
      <Field label={label} required>
        <input
          className={INPUT_CLASS}
          placeholder={disabled ? "Pilih kelurahan dulu" : placeholder}
          value={value}
          disabled={disabled}
          onChange={(event) => {
            onChange(event.target.value);
            setOpen(true);
          }}
          onFocus={() => setOpen(true)}
          onBlur={() => window.setTimeout(() => setOpen(false), 180)}
        />
      </Field>
      {mapsError && !disabled && <p className="mt-1 text-xs font-semibold text-red-500">{mapsError}</p>}

      {open && suggestions.length > 0 && (
        <div className="absolute z-20 mt-1 max-h-72 w-full overflow-y-auto rounded-xl border border-zinc-200 bg-white shadow-xl">
          <div className="border-b border-zinc-100 px-4 py-2 text-xs font-semibold text-zinc-500">
            Rekomendasi tempat berdasarkan alamatmu
          </div>
          {suggestions.map((suggestion) => (
            <button
              key={suggestion.place_id}
              type="button"
              onMouseDown={(event) => event.preventDefault()}
              onClick={() => handleSelect(suggestion)}
              className="flex w-full items-start gap-3 border-b border-zinc-100 px-4 py-3 text-left last:border-0 hover:bg-zinc-50"
            >
              <span className="mt-0.5 text-zinc-400">📍</span>
              <span className="min-w-0 flex-1">
                <span className="block text-sm font-bold text-zinc-900">
                  {suggestion.structured_formatting.main_text}
                </span>
                <span className="mt-0.5 block text-xs text-zinc-500">
                  {suggestion.structured_formatting.secondary_text}
                </span>
              </span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

function MapPreview({ lat, lng, onPinMove }) {
  const mapContainerRef = useRef(null);
  const mapRef = useRef(null);
  const markerRef = useRef(null);
  const geocoderRef = useRef(null);

  useEffect(() => {
    let cancelled = false;
    loadGoogleMaps()
      .then((maps) => {
        if (cancelled || !mapContainerRef.current) return;
        const position = { lat, lng };
        mapRef.current = new maps.Map(mapContainerRef.current, {
          center: position,
          zoom: 17,
          mapTypeControl: false,
          streetViewControl: false,
          fullscreenControl: false,
        });
        markerRef.current = new maps.Marker({
          position,
          map: mapRef.current,
          draggable: true,
          title: "Geser untuk koreksi lokasi",
        });
        geocoderRef.current = new maps.Geocoder();

        function updateFromPosition(nextLat, nextLng) {
          geocoderRef.current.geocode({ location: { lat: nextLat, lng: nextLng } }, (results, status) => {
            const formatted = status === "OK" && results?.[0] ? results[0].formatted_address : "";
            onPinMove(nextLat, nextLng, formatted);
          });
        }

        markerRef.current.addListener("dragend", () => {
          const next = markerRef.current.getPosition();
          updateFromPosition(next.lat(), next.lng());
        });

        mapRef.current.addListener("click", (event) => {
          const nextLat = event.latLng.lat();
          const nextLng = event.latLng.lng();
          markerRef.current.setPosition({ lat: nextLat, lng: nextLng });
          updateFromPosition(nextLat, nextLng);
        });
      })
      .catch(() => {});

    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    if (!mapRef.current || !markerRef.current) return;
    const nextPosition = { lat, lng };
    markerRef.current.setPosition(nextPosition);
    mapRef.current.panTo(nextPosition);
  }, [lat, lng]);

  return (
    <div
      ref={mapContainerRef}
      className="h-72 w-full rounded-xl border border-zinc-200 bg-zinc-100"
      style={{ minHeight: "288px" }}
    />
  );
}

export default function FormAlamat({ mode = "create", initialAddress = null }) {
  const router = useRouter();
  const searchParams = useSearchParams();
  // Allow callers (e.g. /checkout) to specify where to return after save/cancel
  // via ?return=/some/path. Restrict to internal paths only for safety.
  const rawReturn = searchParams.get("return") || "";
  const returnUrl =
    rawReturn.startsWith("/") && !rawReturn.startsWith("//")
      ? rawReturn
      : "/akun/alamat";
  const source = searchParams.get("source") || "profile";
  const rawCheckoutReturn = searchParams.get("checkoutReturn") || "";
  const checkoutReturnUrl =
    rawCheckoutReturn.startsWith("/checkout") && !rawCheckoutReturn.startsWith("//")
      ? rawCheckoutReturn
      : "/checkout";
  const isCheckoutFlow = source === "checkout";
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
    latitude: initialAddress?.latitude ?? null,
    longitude: initialAddress?.longitude ?? null,
    pinpointAddress: initialAddress?.pinpointAddress ?? "",
    streetName: initialAddress?.streetName ?? "",
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
  const [pinpointLoading, setPinpointLoading] = useState(false);
  const [fieldErrors, setFieldErrors] = useState({});

  function updateForm(field, value) {
    setForm((current) => ({ ...current, [field]: value }));
    setFieldErrors((current) => {
      if (!current[field]) return current;
      const next = { ...current };
      delete next[field];
      return next;
    });
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

  useEffect(() => {
    if (!selectedKelurahan || form.postalCode) return;
    const query = [selectedNames.village, selectedNames.regency].filter(Boolean).join(" ");
    if (!query) return;

    let active = true;
    fetch(`${KODEPOS_API}?q=${encodeURIComponent(query)}`)
      .then((response) => response.json())
      .then((payload) => {
        const code = payload?.data?.[0]?.code;
        if (active && code) updateForm("postalCode", String(code));
      })
      .catch(() => {});

    return () => {
      active = false;
    };
  }, [selectedKelurahan, selectedNames, form.postalCode]);

  const addressContext = useMemo(
    () =>
      [
        selectedNames.village,
        selectedNames.district,
        selectedNames.regency,
        selectedNames.province,
      ]
        .filter(Boolean)
        .join(", "),
    [selectedNames]
  );

  const requiredComplete = useMemo(() => {
    const hasSavedRegion = mode === "edit" && Boolean(form.city);
    const regionComplete =
      hasSavedRegion ||
      Boolean(selectedProvinsi && selectedKota && selectedKecamatan && selectedKelurahan);

    return Boolean(
      form.recipient.trim() &&
        form.phone.trim() &&
        form.address.trim() &&
        form.postalCode.trim() &&
        regionComplete
    );
  }, [
    form.recipient,
    form.phone,
    form.address,
    form.postalCode,
    form.city,
    mode,
    selectedProvinsi,
    selectedKota,
    selectedKecamatan,
    selectedKelurahan,
  ]);

  function validateForm() {
    const nextErrors = {};
    const hasSavedRegion = mode === "edit" && Boolean(form.city);

    if (!form.recipient.trim()) nextErrors.recipient = "Nama penerima wajib diisi.";
    if (!form.phone.trim()) nextErrors.phone = "No. HP penerima wajib diisi.";
    if (!form.address.trim()) nextErrors.address = "Alamat lengkap wajib diisi.";
    if (!hasSavedRegion && !selectedProvinsi) nextErrors.province = "Provinsi wajib dipilih.";
    if (!hasSavedRegion && !selectedKota) nextErrors.regency = "Kota/kabupaten wajib dipilih.";
    if (!hasSavedRegion && !selectedKecamatan) nextErrors.district = "Kecamatan wajib dipilih.";
    if (!hasSavedRegion && !selectedKelurahan) nextErrors.village = "Kelurahan wajib dipilih.";
    if (!form.postalCode.trim()) nextErrors.postalCode = "Kode pos wajib diisi.";

    setFieldErrors(nextErrors);
    return Object.keys(nextErrors).length === 0;
  }

  async function handleAddPinpoint() {
    setError("");
    const query = [form.address, addressContext].filter(Boolean).join(", ");

    if (!query.trim()) {
      setError("Isi alamat dan wilayah terlebih dahulu sebelum menambah pinpoint.");
      return;
    }

    setPinpointLoading(true);

    try {
      const maps = await loadGoogleMaps();
      const geocoder = new maps.Geocoder();

      geocoder.geocode({ address: query, region: "ID" }, (results, status) => {
        setPinpointLoading(false);
        if (status !== "OK" || !results?.[0]?.geometry?.location) {
          setError("Pinpoint belum ditemukan. Coba lengkapi alamat atau pilih wilayah lebih spesifik.");
          return;
        }

        const location = results[0].geometry.location;
        setForm((current) => ({
          ...current,
          latitude: location.lat(),
          longitude: location.lng(),
          pinpointAddress: results[0].formatted_address || current.pinpointAddress,
          streetName: current.streetName || form.address,
        }));
      });
    } catch {
      setPinpointLoading(false);
      setError("Google Maps belum bisa dimuat. Cek API key Google Maps di environment.");
    }
  }

  async function handleSubmit(event) {
    event.preventDefault();
    setError("");
    if (!validateForm()) return;
    setSubmitting(true);

    const latitude = form.latitude === null || form.latitude === "" ? null : Number(form.latitude);
    const longitude = form.longitude === null || form.longitude === "" ? null : Number(form.longitude);

    const payload = {
      ...form,
      latitude: Number.isFinite(latitude) ? latitude : null,
      longitude: Number.isFinite(longitude) ? longitude : null,
      pinpointAddress: String(form.pinpointAddress || "").trim() || null,
      streetName: String(form.streetName || "").trim() || null,
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
      if (isCheckoutFlow && data?.address?.id) {
        sessionStorage.setItem(CHECKOUT_SELECTED_ADDRESS_KEY, data.address.id);
        sessionStorage.setItem(CHECKOUT_ADDRESS_FORCE_APPLY_KEY, "1");
        router.push(checkoutReturnUrl);
      } else {
        router.push(returnUrl);
      }
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

      <Field
        label="Nama Penerima"
        name="recipient"
        value={form.recipient}
        onChange={(event) => updateForm("recipient", event.target.value)}
        placeholder="Nama penerima paket"
        error={fieldErrors.recipient}
      />

      <Field
        label="No. HP Penerima"
        name="phone"
        type="tel"
        value={form.phone}
        onChange={(event) => updateForm("phone", event.target.value)}
        placeholder="Contoh: 081234567890"
        error={fieldErrors.phone}
      />

      <Field label="Alamat Lengkap" name="address" error={fieldErrors.address}>
        <textarea
          name="address"
          required
          rows={3}
          value={form.address}
          onChange={(event) => updateForm("address", event.target.value)}
          placeholder="Nama jalan, nomor rumah, RT/RW"
          className={`${INPUT_CLASS} min-h-[112px] resize-y`}
        />
      </Field>

      <Field label="Detail Alamat / Patokan" name="streetName" required={false}>
        <input
          name="streetName"
          type="text"
          value={form.streetName}
          onChange={(event) => updateForm("streetName", event.target.value)}
          placeholder="Contoh: rumah pagar hitam, dekat Indomaret, blok/unit/lantai"
          className={INPUT_CLASS}
        />
      </Field>

      {initialAddress?.city && mode === "edit" && (
        <div className="rounded-2xl border border-zinc-100 bg-zinc-50 px-4 py-3 text-sm text-zinc-600">
          Wilayah tersimpan: <span className="font-semibold">{initialAddress.city}</span>
          <p className="mt-1 text-xs text-zinc-500">
            Pilih ulang wilayah jika ingin memperbarui provinsi sampai kelurahan.
          </p>
        </div>
      )}

      <SelectFieldWithError
        label="Provinsi"
        value={selectedProvinsi}
        onChange={(value) => {
          setSelectedProvinsi(value);
          setFieldErrors((current) => ({ ...current, province: undefined }));
        }}
        options={provinsi}
        placeholder="Pilih provinsi"
        loading={loadingProvinsi}
        required={mode !== "edit" || !form.city}
        error={fieldErrors.province}
      />

      <SelectFieldWithError
        label="Kota / Kabupaten"
        value={selectedKota}
        onChange={(value) => {
          setSelectedKota(value);
          setFieldErrors((current) => ({ ...current, regency: undefined }));
        }}
        options={kota}
        placeholder="Pilih kota/kabupaten"
        disabled={!selectedProvinsi}
        loading={loadingKota}
        required={mode !== "edit" || !form.city}
        error={fieldErrors.regency}
      />

      <SelectFieldWithError
        label="Kecamatan"
        value={selectedKecamatan}
        onChange={(value) => {
          setSelectedKecamatan(value);
          setFieldErrors((current) => ({ ...current, district: undefined }));
        }}
        options={kecamatan}
        placeholder="Pilih kecamatan"
        disabled={!selectedKota}
        loading={loadingKecamatan}
        required={mode !== "edit" || !form.city}
        error={fieldErrors.district}
      />

      <SelectFieldWithError
        label="Kelurahan"
        value={selectedKelurahan}
        onChange={(value) => {
          setSelectedKelurahan(value);
          setFieldErrors((current) => ({ ...current, village: undefined }));
        }}
        options={kelurahan}
        placeholder="Pilih kelurahan"
        disabled={!selectedKecamatan}
        loading={loadingKelurahan}
        required={mode !== "edit" || !form.city}
        error={fieldErrors.village}
      />

      <Field
        label="Kode Pos"
        name="postalCode"
        value={form.postalCode}
        onChange={(event) => updateForm("postalCode", event.target.value)}
        placeholder="Terisi otomatis setelah pilih kelurahan"
        inputMode="numeric"
        help="Kode pos terisi otomatis setelah kelurahan dipilih, tetapi masih bisa diedit jika diperlukan."
        error={fieldErrors.postalCode}
      />

      <input type="hidden" name="city" value={form.city} />
      <input type="hidden" name="latitude" value={form.latitude ?? ""} />
      <input type="hidden" name="longitude" value={form.longitude ?? ""} />
      <input type="hidden" name="pinpointAddress" value={form.pinpointAddress ?? ""} />

      <div>
        <p className="text-sm font-bold text-zinc-800">Label Alamat</p>
        <div className="mt-2 flex flex-wrap gap-2">
          {LABELS.map((label) => {
            const selected = form.label === label;
            return (
              <button
                key={label}
                type="button"
                onClick={() => updateForm("label", label)}
                className={`rounded-full border px-4 py-2 text-sm font-bold transition ${
                  selected
                    ? "border-natalo-600 bg-natalo-50 text-natalo-700"
                    : "border-zinc-200 bg-white text-zinc-600 hover:border-natalo-300"
                }`}
              >
                {label}
              </button>
            );
          })}
        </div>
      </div>

      <div className="rounded-2xl border border-zinc-200 bg-zinc-50 p-4">
        <p className="text-sm font-bold text-zinc-800">Pinpoint Lokasi GPS</p>
        <p className="mt-1 text-xs font-medium text-zinc-500">
          Opsional, pin titik tepat agar kurir lebih mudah menemukan alamatmu.
        </p>
        <button
          type="button"
          onClick={handleAddPinpoint}
          disabled={pinpointLoading || !form.address.trim()}
          className="mt-3 w-full rounded-full border border-natalo-200 bg-white px-4 py-3 text-sm font-black text-natalo-700 transition hover:border-natalo-400 disabled:cursor-not-allowed disabled:opacity-50"
        >
          {pinpointLoading ? "Mencari titik..." : form.latitude && form.longitude ? "Ubah Pinpoint" : "Tambah Pinpoint"}
        </button>

        {form.latitude && form.longitude && (
          <div className="mt-4">
            <MapPreview
              lat={Number(form.latitude)}
              lng={Number(form.longitude)}
              onPinMove={(latitude, longitude, formattedAddress) => {
                setForm((current) => ({
                  ...current,
                  latitude,
                  longitude,
                  pinpointAddress: formattedAddress || current.pinpointAddress,
                }));
              }}
            />
            <div className="mt-2 rounded-xl bg-white px-4 py-3 text-sm">
              <p className="font-semibold text-zinc-900">
                {form.pinpointAddress || "Alamat pinpoint belum terbaca."}
              </p>
              <p className="mt-1 font-mono text-xs text-zinc-500">
                {Number(form.latitude).toFixed(6)}, {Number(form.longitude).toFixed(6)}
              </p>
            </div>
          </div>
        )}
      </div>

      <label className="flex cursor-pointer items-center justify-between gap-4 rounded-2xl border border-zinc-200 bg-white px-4 py-3">
        <span>
          <span className="block text-sm font-black text-zinc-900">Jadikan Alamat Utama</span>
          <span className="mt-0.5 block text-xs font-medium text-zinc-500">
            {isCheckoutFlow
              ? "Opsional. Tanpa ini, alamat hanya dipilih untuk pesanan checkout saat ini."
              : "Pakai alamat ini sebagai default saat checkout."}
          </span>
        </span>
        <input
          type="checkbox"
          checked={form.isMain}
          onChange={(event) => updateForm("isMain", event.target.checked)}
          className="h-5 w-5 rounded border-natalo-300 text-natalo-600 focus:ring-natalo-400"
        />
      </label>

      <div className="sticky bottom-0 z-20 -mx-4 border-t border-zinc-100 bg-white/95 px-4 pb-[calc(1rem+env(safe-area-inset-bottom))] pt-3 backdrop-blur sm:static sm:mx-0 sm:border-0 sm:bg-transparent sm:p-0">
        <button
          type="submit"
          disabled={submitting || !requiredComplete}
          className="w-full rounded-full bg-natalo-600 px-6 py-3.5 text-sm font-black text-white shadow-sm transition hover:bg-natalo-700 disabled:cursor-not-allowed disabled:bg-zinc-300 disabled:text-zinc-500 disabled:shadow-none"
        >
          {submitting ? "Menyimpan..." : mode === "edit" ? "Simpan Perubahan" : "Simpan Alamat"}
        </button>
        <button
          type="button"
          onClick={() => router.push(returnUrl)}
          className="mt-2 w-full rounded-full px-6 py-3 text-sm font-bold text-zinc-600 transition hover:bg-zinc-50"
        >
          Batal
        </button>
      </div>
    </form>
  );
}
