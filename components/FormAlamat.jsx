"use client";

import { GoogleMap, Marker, useJsApiLoader } from "@react-google-maps/api";
import { useEffect, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { useRouter, useSearchParams } from "next/navigation";
import {
  FiArrowLeft,
  FiBriefcase,
  FiCheck,
  FiChevronDown,
  FiHome,
  FiMapPin,
  FiNavigation,
  FiSearch,
  FiX,
} from "react-icons/fi";

const CHECKOUT_SELECTED_ADDRESS_KEY = "checkout:selectedAddressId";
const CHECKOUT_ADDRESS_FORCE_APPLY_KEY = "checkout:addressForceApply";
const PHONE_RE = /^(\+62|62|0)8[1-9][0-9]{6,11}$/;
const GOOGLE_API_KEY =
  process.env.NEXT_PUBLIC_GOOGLE_MAPS_KEY ??
  process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY ??
  "";
const googleLibraries = ["places"];
const fallbackCenter = { lat: -6.2, lng: 106.816666 };
const inputClass =
  "peer block w-full rounded-2xl border bg-white px-4 pb-2.5 pt-5 text-sm font-semibold text-slate-900 outline-none transition placeholder:text-transparent focus:ring-4 disabled:cursor-not-allowed disabled:bg-slate-50 disabled:text-slate-400";

function safeInternalPath(value, fallback) {
  return value && value.startsWith("/") && !value.startsWith("//") ? value : fallback;
}

function hasUsablePinpoint(lat, lng) {
  return (
    typeof lat === "number" &&
    Number.isFinite(lat) &&
    typeof lng === "number" &&
    Number.isFinite(lng) &&
    !(lat === 0 && lng === 0)
  );
}

function normalizeCoordinate(value) {
  const next = value === null || value === undefined || value === "" ? null : Number(value);
  return Number.isFinite(next) ? next : null;
}

function isValidLabel(label) {
  return label === "" || label === "Rumah" || label === "Kantor";
}

function mapInitialAddress(address) {
  const lat = normalizeCoordinate(address?.latitude);
  const lng = normalizeCoordinate(address?.longitude);
  const label = address?.label === "Rumah" || address?.label === "Kantor" ? address.label : "Rumah";

  return {
    nama: address?.recipient ?? "",
    phone: address?.phone ?? "",
    provinsi: address?.provinceName ?? "",
    kota: address?.cityName ?? address?.city ?? "",
    kecamatan: address?.districtName ?? "",
    kodePos: address?.postalCode ?? "",
    jalan: address?.address ?? "",
    detail: address?.streetName ?? "",
    lat,
    lng,
    isUtama: Boolean(address?.isMain),
    label,
    pinpointAddress: address?.pinpointAddress ?? "",
    areaId: address?.areaId ?? "",
    areaLabel: address?.areaLabel ?? "",
  };
}

function validateField(name, value, form) {
  if (name === "nama") {
    if (!value.trim()) return "Mohon lengkapi Nama Lengkap";
    if (value.trim().length < 2) return "Nama Lengkap minimal 2 karakter";
  }
  if (name === "phone") {
    if (!value.trim()) return "Mohon lengkapi Nomor Telepon";
    if (!PHONE_RE.test(value.replace(/\s/g, ""))) return "Format nomor Indonesia belum sesuai";
  }
  if (["provinsi", "kota", "kecamatan", "kodePos"].includes(name) && !value.trim()) {
    const labels = {
      provinsi: "Provinsi",
      kota: "Kota / Kabupaten",
      kecamatan: "Kecamatan",
      kodePos: "Kode Pos",
    };
    return `Mohon lengkapi ${labels[name]}`;
  }
  if (name === "jalan") {
    if (!value.trim()) return "Mohon lengkapi Nama Jalan";
    if (value.trim().length < 5) return "Nama Jalan minimal 5 karakter";
  }
  if (name === "detail" && !value.trim()) return "Mohon lengkapi Detail Lainnya / Patokan";
  if (name === "label") {
    if (!value) return "Mohon pilih Label Alamat";
    if (!isValidLabel(value)) return "Label hanya boleh Rumah atau Kantor";
  }
  if (name === "pinpoint" && !hasUsablePinpoint(form.lat, form.lng)) {
    return "Mohon konfirmasi titik peta";
  }
  if (name === "all") {
    const fields = ["nama", "phone", "provinsi", "kota", "kecamatan", "kodePos", "jalan", "detail", "label", "pinpoint"];
    const errors = {};
    fields.forEach((field) => {
      const error = validateField(field, form[field], form);
      if (error) errors[field] = error;
    });
    return errors;
  }
  return "";
}

function Field({
  label,
  name,
  value,
  onChange,
  onBlur,
  error,
  type = "text",
  as = "input",
  readOnly = false,
  disabled = false,
  placeholder = " ",
  children,
}) {
  const borderClass = error
    ? "border-red-300 focus:border-red-500 focus:ring-red-100"
    : "border-slate-200 focus:border-natalo-500 focus:ring-natalo-100";

  return (
    <div>
      <div className="relative">
        {children ??
          (as === "textarea" ? (
            <textarea
              name={name}
              value={value}
              onChange={onChange}
              onBlur={onBlur}
              placeholder={placeholder}
              rows={3}
              readOnly={readOnly}
              disabled={disabled}
              className={`${inputClass} min-h-[118px] resize-y placeholder:text-slate-400 ${borderClass}`}
            />
          ) : (
            <input
              name={name}
              type={type}
              value={value}
              onChange={onChange}
              onBlur={onBlur}
              placeholder={placeholder}
              readOnly={readOnly}
              disabled={disabled}
              className={`${inputClass} ${borderClass}`}
            />
          ))}
        <label className="pointer-events-none absolute left-4 top-2 text-[11px] font-black uppercase tracking-wide text-slate-500">
          {label}
        </label>
      </div>
      {error && <p className="mt-1.5 text-xs font-bold text-red-500">{error}</p>}
    </div>
  );
}

function Toggle({ checked, onChange }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      onClick={() => onChange(!checked)}
      className={`relative h-7 w-12 rounded-full transition ${
        checked ? "bg-natalo-600" : "bg-slate-200"
      }`}
    >
      <span
        className={`absolute top-1 h-5 w-5 rounded-full bg-white shadow transition ${
          checked ? "left-6" : "left-1"
        }`}
      />
    </button>
  );
}

function LabelSelector({ value, onChange }) {
  const labels = [
    { value: "Rumah", icon: FiHome },
    { value: "Kantor", icon: FiBriefcase },
  ];

  return (
    <div>
      <p className="text-sm font-black text-slate-900">Label Alamat</p>
      <div className="mt-2 grid grid-cols-2 gap-2">
        {labels.map((item) => {
          const Icon = item.icon;
          const selected = value === item.value;
          return (
            <button
              key={item.value}
              type="button"
              onClick={() => onChange(selected ? "" : item.value)}
              className={`flex h-12 items-center justify-center gap-2 rounded-2xl border text-sm font-black transition ${
                selected
                  ? "border-natalo-600 bg-natalo-50 text-natalo-700 ring-4 ring-natalo-100"
                  : "border-slate-200 bg-white text-slate-600 hover:border-natalo-200"
              }`}
            >
              <Icon aria-hidden="true" />
              {item.value}
            </button>
          );
        })}
      </div>
    </div>
  );
}

function AddressAutocompleteInput({ value, hasPinpoint, onOpen }) {
  return (
    <section className="rounded-3xl border border-natalo-100 bg-natalo-50/70 p-4 shadow-sm">
      <p className="text-xs font-black uppercase tracking-wide text-natalo-700">Cari Alamat</p>
      <button
        type="button"
        onClick={onOpen}
        className="mt-3 flex w-full items-start gap-3 rounded-3xl border border-natalo-100 bg-white p-4 text-left shadow-sm transition hover:border-natalo-300 active:scale-[0.99]"
      >
        <span className="grid h-11 w-11 shrink-0 place-items-center rounded-2xl bg-natalo-50 text-natalo-700">
          <FiMapPin className="h-5 w-5" aria-hidden="true" />
        </span>
        <span className="min-w-0 flex-1">
          <span className={`block text-sm font-black ${value ? "text-slate-950" : "text-slate-400"}`}>
            {value || "Cari alamat / nama jalan / gedung"}
          </span>
          <span className="mt-1 block text-xs font-semibold leading-5 text-slate-500">
            Mulai ketik alamat lalu pilih rekomendasi alamat.
          </span>
        </span>
        <FiSearch className="mt-1 h-5 w-5 shrink-0 text-natalo-600" aria-hidden="true" />
      </button>
      {hasPinpoint && (
        <div className="mt-3 flex items-center gap-2 rounded-2xl bg-emerald-50 px-3 py-2 text-xs font-black text-emerald-700">
          <FiCheck className="h-4 w-4" aria-hidden="true" />
          Alamat ditemukan
        </div>
      )}
    </section>
  );
}

function getData(payload) {
  if (Array.isArray(payload)) return payload;
  if (Array.isArray(payload?.data)) return payload.data;
  return [];
}

function itemId(item) {
  return String(item?.id ?? item?.code ?? item?.kode ?? "").trim();
}

function itemName(item) {
  return String(item?.name ?? item?.nama ?? "").trim();
}

function itemPostalCode(item) {
  return String(item?.postalCode ?? item?.postal_code ?? item?.kode_pos ?? "").trim();
}

function LocationPicker({ open, value, onClose, onApply }) {
  const [step, setStep] = useState("provinsi");
  const [loading, setLoading] = useState(false);
  const [items, setItems] = useState([]);
  const [selected, setSelected] = useState({
    provinsi: null,
    kota: null,
    kecamatan: null,
    kodePos: value.kodePos || "",
  });
  const [manualPostalCode, setManualPostalCode] = useState(value.kodePos || "");

  const [dragY, setDragY] = useState(0);
  const [dragging, setDragging] = useState(false);
  const [snapping, setSnapping] = useState(false);
  const dragStartYRef = useRef(0);
  const dragYRef = useRef(0);
  const draggingRef = useRef(false);

  function startDrag(target, clientY) {
    if (target && target.closest && target.closest("button, a, input, textarea")) return;
    dragStartYRef.current = clientY;
    dragYRef.current = 0;
    draggingRef.current = true;
    setDragging(true);
    setSnapping(false);
    setDragY(0);
  }
  function moveDrag(clientY) {
    if (!draggingRef.current) return;
    const dy = Math.max(0, clientY - dragStartYRef.current);
    dragYRef.current = dy;
    setDragY(dy);
  }
  function endDrag() {
    if (!draggingRef.current) return;
    draggingRef.current = false;
    setDragging(false);
    if (dragYRef.current >= 120) {
      onClose();
      return;
    }
    setSnapping(true);
    dragYRef.current = 0;
    setDragY(0);
    setTimeout(() => setSnapping(false), 280);
  }
  function onTouchStart(e) {
    const t = e.touches[0];
    if (!t) return;
    startDrag(e.target, t.clientY);
  }
  function onTouchMove(e) {
    const t = e.touches[0];
    if (!t) return;
    moveDrag(t.clientY);
    if (draggingRef.current && dragYRef.current > 0 && e.cancelable) e.preventDefault();
  }
  function onMouseDown(e) {
    if (e.button !== 0) return;
    startDrag(e.target, e.clientY);
  }
  useEffect(() => {
    if (!dragging) return;
    const mm = (e) => moveDrag(e.clientY);
    const mu = () => endDrag();
    document.addEventListener("mousemove", mm);
    document.addEventListener("mouseup", mu);
    return () => {
      document.removeEventListener("mousemove", mm);
      document.removeEventListener("mouseup", mu);
    };
  }, [dragging]);

  useEffect(() => {
    if (!open) return;
    setStep("provinsi");
    setSelected({
      provinsi: value.provinsi ? { name: value.provinsi } : null,
      kota: value.kota ? { name: value.kota } : null,
      kecamatan: value.kecamatan ? { name: value.kecamatan } : null,
      kodePos: value.kodePos || "",
    });
    setManualPostalCode(value.kodePos || "");
  }, [open, value]);

  useEffect(() => {
    if (!open) return;
    let endpoint = "/api/wilayah/provinsi";
    if (step === "kota") endpoint = `/api/wilayah/kota?provinsi=${itemId(selected.provinsi)}`;
    if (step === "kecamatan") endpoint = `/api/wilayah/kecamatan?kota=${itemId(selected.kota)}`;
    if (step === "kodePos") endpoint = `/api/wilayah/kodepos?kec=${itemId(selected.kecamatan)}`;

    let active = true;
    setLoading(true);
    fetch(endpoint, { cache: "force-cache" })
      .then((response) => response.json())
      .then((payload) => {
        if (active) setItems(getData(payload));
      })
      .catch(() => {
        if (active) setItems([]);
      })
      .finally(() => {
        if (active) setLoading(false);
      });

    return () => {
      active = false;
    };
  }, [open, step, selected.provinsi, selected.kota, selected.kecamatan]);

  if (!open) return null;

  function choose(item) {
    if (step === "provinsi") {
      setSelected({ provinsi: item, kota: null, kecamatan: null, kodePos: "" });
      setStep("kota");
      return;
    }
    if (step === "kota") {
      setSelected((current) => ({ ...current, kota: item, kecamatan: null, kodePos: "" }));
      setStep("kecamatan");
      return;
    }
    if (step === "kecamatan") {
      setSelected((current) => ({ ...current, kecamatan: item, kodePos: "" }));
      setStep("kodePos");
      return;
    }
    const postalCode = itemPostalCode(item);
    setSelected((current) => ({ ...current, kodePos: postalCode }));
    setManualPostalCode(postalCode);
  }

  function apply() {
    onApply({
      provinsi: itemName(selected.provinsi),
      kota: itemName(selected.kota),
      kecamatan: itemName(selected.kecamatan),
      kodePos: manualPostalCode.trim() || selected.kodePos,
    });
    onClose();
  }

  const canApply =
    selected.provinsi &&
    selected.kota &&
    selected.kecamatan &&
    (manualPostalCode.trim() || selected.kodePos);

  return (
    <div className="fixed inset-0 z-[2100] bg-slate-950/40">
      <button type="button" aria-label="Tutup picker wilayah" className="absolute inset-0" onClick={onClose} />
      <section
        className="absolute inset-x-0 bottom-0 max-h-[86dvh] rounded-t-[28px] bg-white shadow-2xl"
        style={{
          touchAction: "pan-y",
          transform: dragging || snapping ? `translate3d(0, ${dragY}px, 0)` : undefined,
          transition: dragging
            ? "none"
            : snapping
              ? "transform 280ms cubic-bezier(0.34, 1.26, 0.64, 1)"
              : undefined,
        }}
      >
        <div
          onTouchStart={onTouchStart}
          onTouchMove={onTouchMove}
          onTouchEnd={endDrag}
          onTouchCancel={endDrag}
          onMouseDown={onMouseDown}
          className="cursor-grab touch-pan-y select-none pt-3 active:cursor-grabbing"
        >
          <div className="mx-auto h-1.5 w-12 rounded-full bg-slate-200" />
        </div>
        <div className="flex items-center justify-between border-b border-slate-100 px-4 py-4">
          <div>
            <p className="text-base font-black text-slate-950">Pilih Wilayah</p>
            <p className="text-xs font-semibold text-slate-500">
              Provinsi, kota, kecamatan, lalu kode pos
            </p>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="grid h-10 w-10 place-items-center rounded-full border border-slate-200 text-slate-600"
          >
            <FiX aria-hidden="true" />
          </button>
        </div>

        <div className="flex gap-2 overflow-x-auto px-4 py-3">
          {["provinsi", "kota", "kecamatan", "kodePos"].map((item) => (
            <button
              key={item}
              type="button"
              onClick={() => setStep(item)}
              className={`shrink-0 rounded-full px-3 py-1.5 text-xs font-black capitalize ${
                step === item ? "bg-natalo-600 text-white" : "bg-slate-100 text-slate-600"
              }`}
            >
              {item === "kodePos" ? "Kode Pos" : item}
            </button>
          ))}
        </div>

        <div className="max-h-[48dvh] overflow-y-auto px-4 pb-4">
          {loading ? (
            <p className="rounded-2xl bg-slate-50 px-4 py-5 text-center text-sm font-bold text-slate-500">
              Memuat data wilayah...
            </p>
          ) : step === "kodePos" ? (
            <div className="space-y-3">
              {items.map((item) => {
                const code = itemPostalCode(item);
                if (!code) return null;
                const selectedCode = manualPostalCode === code;
                return (
                  <button
                    key={`${itemId(item)}-${code}`}
                    type="button"
                    onClick={() => choose(item)}
                    className={`flex w-full items-center justify-between rounded-2xl border px-4 py-3 text-left transition ${
                      selectedCode
                        ? "border-natalo-600 bg-natalo-50 text-natalo-800"
                        : "border-slate-200 bg-white text-slate-700"
                    }`}
                  >
                    <span>
                      <span className="block text-sm font-black">{code}</span>
                      <span className="text-xs font-semibold text-slate-500">{itemName(item)}</span>
                    </span>
                    {selectedCode && <FiCheck aria-hidden="true" />}
                  </button>
                );
              })}
              <Field
                label="Kode Pos Manual"
                name="manualPostalCode"
                value={manualPostalCode}
                onChange={(event) => setManualPostalCode(event.target.value)}
                type="tel"
              />
            </div>
          ) : (
            <div className="space-y-2">
              {items.map((item) => (
                <button
                  key={itemId(item)}
                  type="button"
                  onClick={() => choose(item)}
                  className="block w-full rounded-2xl border border-slate-200 bg-white px-4 py-3 text-left text-sm font-black text-slate-800 transition hover:border-natalo-200 hover:bg-natalo-50"
                >
                  {itemName(item)}
                </button>
              ))}
              {items.length === 0 && (
                <p className="rounded-2xl bg-slate-50 px-4 py-5 text-center text-sm font-bold text-slate-500">
                  Data belum tersedia. Coba isi manual lewat kode pos.
                </p>
              )}
            </div>
          )}
        </div>

        <div className="border-t border-slate-100 px-4 py-3 [padding-bottom:calc(12px+env(safe-area-inset-bottom))]">
          <button
            type="button"
            disabled={!canApply}
            onClick={apply}
            className="h-12 w-full rounded-2xl bg-natalo-600 text-sm font-black text-white transition hover:bg-natalo-700 disabled:cursor-not-allowed disabled:bg-slate-300"
          >
            Gunakan Wilayah
          </button>
        </div>
      </section>
    </div>
  );
}

function StreetAutocomplete({ initialQuery, onBack, onManual, onSelect }) {
  const inputRef = useRef(null);
  const debounceRef = useRef(null);
  const [query, setQuery] = useState(initialQuery || "");
  const [suggestions, setSuggestions] = useState([]);
  const [status, setStatus] = useState("");
  const [userLocation, setUserLocation] = useState(null);

  useEffect(() => {
    window.setTimeout(() => inputRef.current?.focus(), 50);
    if (!navigator.geolocation) return;
    navigator.geolocation.getCurrentPosition(
      (position) => {
        setUserLocation({
          lat: position.coords.latitude,
          lng: position.coords.longitude,
        });
      },
      () => setUserLocation(null),
      { enableHighAccuracy: true, timeout: 6000, maximumAge: 60000 }
    );
  }, []);

  useEffect(() => {
    window.clearTimeout(debounceRef.current);
    const input = query.trim();
    if (input.length < 3) {
      setSuggestions([]);
      setStatus(input ? "Ketik minimal 3 huruf." : "");
      return;
    }

    debounceRef.current = window.setTimeout(async () => {
      setStatus("Mencari alamat...");
      try {
        const response = await fetch("/api/places/autocomplete", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            input,
            location: userLocation ? `${userLocation.lat},${userLocation.lng}` : undefined,
            radius: 2000,
            components: "country:id",
          }),
        });
        const data = await response.json();
        if (!response.ok) {
          throw new Error(data.error || "Autocomplete belum bisa dipakai.");
        }
        const next = Array.isArray(data.predictions) ? data.predictions : [];
        setSuggestions(next);
        setStatus(
          next.length === 0
            ? data.error || "Alamat belum ditemukan. Kamu tetap bisa isi manual."
            : ""
        );
      } catch {
        setSuggestions([]);
        setStatus("Autocomplete belum bisa dipakai. Kamu tetap bisa isi manual.");
      }
    }, 300);

    return () => window.clearTimeout(debounceRef.current);
  }, [query, userLocation]);

  async function selectPrediction(prediction) {
    setStatus("Membuka peta...");
    try {
      const response = await fetch("/api/places/details", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ placeId: prediction.place_id }),
      });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || "Alamat belum bisa dibuka.");
      onSelect({
        prediction,
        address: data.address,
      });
    } catch (error) {
      setStatus(error instanceof Error ? error.message : "Alamat belum bisa dibuka.");
    }
  }

  // Render via Portal ke document.body untuk eliminasi semua kemungkinan
  // stacking-context dari ancestor (mis. transform/opacity di page wrapper),
  // sehingga overlay autocomplete benar-benar berada di atas global header,
  // sub-header sticky, dan sticky submit button. z-[2100] aman di atas
  // .mobile-sticky-header (z-1000) dan elemen sticky lain. data-no-swipe-back
  // mencegah iOS swipe-back gesture menangkap tap di edge kiri (yang bikin
  // suggestion paling kiri kadang tidak respond).
  if (typeof document === "undefined") return null;
  return createPortal(
    <section
      data-no-swipe-back="true"
      className="fixed inset-0 z-[2100] bg-slate-50"
    >
      <div className="mx-auto flex h-dvh max-w-md flex-col bg-slate-50">
        <div className="border-b border-slate-200 bg-white px-4 pb-3 pt-[calc(12px+env(safe-area-inset-top))]">
          <div className="flex items-center gap-3">
            <button
              type="button"
              onClick={onBack}
              className="grid h-11 w-11 shrink-0 place-items-center rounded-full border border-slate-200 text-slate-700"
            >
              <FiArrowLeft aria-hidden="true" />
            </button>
            <div className="relative flex-1">
              <FiSearch className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-400" aria-hidden="true" />
              <input
                ref={inputRef}
                type="search"
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="Cari nama tempat atau jalan"
                className="h-12 w-full rounded-2xl border border-slate-200 bg-slate-50 pl-11 pr-4 text-sm font-bold text-slate-900 outline-none focus:border-natalo-500 focus:ring-4 focus:ring-natalo-100"
              />
            </div>
          </div>
          {status && <p className="mt-2 px-1 text-xs font-bold text-slate-500">{status}</p>}
        </div>

        {/* Scroll list: padding bawah generous + safe-area-inset-bottom
            supaya suggestion terakhir tidak tertutup home indicator iOS
            atau gesture-bar Android. Saat keyboard terbuka, h-dvh adapt ke
            visual viewport sehingga scroll area otomatis shrink. */}
        <div className="flex-1 overflow-y-auto overscroll-contain px-4 pt-4 pb-[calc(24px+env(safe-area-inset-bottom))]">
          <div className="space-y-2">
            {suggestions.map((item) => (
              <button
                key={item.place_id}
                type="button"
                onClick={() => selectPrediction(item)}
                className="flex w-full gap-3 rounded-3xl border border-slate-100 bg-white p-4 text-left shadow-sm transition hover:border-natalo-200"
              >
                <span className="grid h-10 w-10 shrink-0 place-items-center rounded-2xl bg-natalo-50 text-natalo-700">
                  <FiMapPin aria-hidden="true" />
                </span>
                <span className="min-w-0">
                  <span className="block text-sm font-black text-slate-950">
                    {item.structured_formatting?.main_text || item.description}
                  </span>
                  <span className="mt-1 block text-xs font-semibold leading-5 text-slate-500">
                    {item.structured_formatting?.secondary_text || item.description}
                  </span>
                </span>
              </button>
            ))}
          </div>

          <button
            type="button"
            onClick={() => onManual(query)}
            className="mt-4 w-full rounded-2xl border border-natalo-200 bg-white px-4 py-3 text-sm font-black text-natalo-700"
          >
            Isi nama jalan manual
          </button>
        </div>
      </div>
    </section>,
    document.body,
  );
}

function MapConfirm({ selectedPlace, onBack, onApply }) {
  const initial = selectedPlace?.address ?? {};
  const initialPosition =
    hasUsablePinpoint(initial.lat, initial.lng) ? { lat: initial.lat, lng: initial.lng } : fallbackCenter;
  const [position, setPosition] = useState(initialPosition);
  const [address, setAddress] = useState(initial);
  const [status, setStatus] = useState("");
  const [dialogOpen, setDialogOpen] = useState(false);
  const reverseTimer = useRef(null);
  const { isLoaded, loadError } = useJsApiLoader({
    id: "google-maps-address-confirm",
    googleMapsApiKey: GOOGLE_API_KEY,
    libraries: googleLibraries,
  });

  function reverseGeocode(nextPosition) {
    window.clearTimeout(reverseTimer.current);
    reverseTimer.current = window.setTimeout(async () => {
      setStatus("Membaca alamat dari pin...");
      try {
        const response = await fetch("/api/places/reverse-geocode", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ lat: nextPosition.lat, lng: nextPosition.lng }),
        });
        const data = await response.json();
        if (!response.ok) throw new Error(data.error || "Alamat belum bisa dibaca.");
        setAddress((current) => ({
          ...current,
          ...data.address,
          lat: nextPosition.lat,
          lng: nextPosition.lng,
        }));
        setStatus("");
      } catch (error) {
        setAddress((current) => ({ ...current, lat: nextPosition.lat, lng: nextPosition.lng }));
        setStatus(error instanceof Error ? error.message : "Alamat belum bisa dibaca.");
      }
    }, 350);
  }

  function moveToCurrentLocation() {
    if (!navigator.geolocation) {
      setStatus("GPS tidak tersedia di perangkat ini.");
      return;
    }
    setStatus("Mendeteksi lokasi...");
    navigator.geolocation.getCurrentPosition(
      (location) => {
        const next = { lat: location.coords.latitude, lng: location.coords.longitude };
        setPosition(next);
        reverseGeocode(next);
      },
      () => setStatus("GPS ditolak. Kamu tetap bisa geser pin di peta."),
      { enableHighAccuracy: true, timeout: 10000, maximumAge: 30000 }
    );
  }

  function confirm() {
    onApply({
      jalan: address.jalan || selectedPlace?.prediction?.structured_formatting?.main_text || "",
      provinsi: address.provinsi || "",
      kota: address.kota || "",
      kecamatan: address.kecamatan || "",
      kodePos: address.kodePos || "",
      lat: position.lat,
      lng: position.lng,
      pinpointAddress: address.formattedAddress || "",
    });
  }

  return (
    <section className="fixed inset-0 z-[2050] bg-white">
      <div className="relative mx-auto h-dvh max-w-md overflow-hidden bg-slate-100">
        <div className="absolute inset-x-0 top-0 z-20 flex items-center justify-between px-4 pt-[calc(12px+env(safe-area-inset-top))]">
          <button
            type="button"
            onClick={onBack}
            className="grid h-11 w-11 place-items-center rounded-full bg-white text-slate-700 shadow-lg"
          >
            <FiArrowLeft aria-hidden="true" />
          </button>
          <button
            type="button"
            onClick={moveToCurrentLocation}
            className="grid h-11 w-11 place-items-center rounded-full bg-white text-natalo-700 shadow-lg"
          >
            <FiNavigation aria-hidden="true" />
          </button>
        </div>

        <div className="h-full bg-slate-200">
          {isLoaded && !loadError ? (
            <GoogleMap
              mapContainerClassName="h-full w-full"
              center={position}
              zoom={17}
              options={{
                disableDefaultUI: true,
                clickableIcons: false,
                gestureHandling: "greedy",
              }}
            >
              <Marker
                position={position}
                draggable
                onDragEnd={(event) => {
                  const next = { lat: event.latLng.lat(), lng: event.latLng.lng() };
                  setPosition(next);
                  reverseGeocode(next);
                }}
              />
            </GoogleMap>
          ) : (
            <div className="flex h-full items-center justify-center px-8 text-center text-sm font-bold text-slate-500">
              {GOOGLE_API_KEY ? "Memuat Google Maps..." : "Google Maps key belum tersedia. Koordinat tetap bisa disimpan."}
            </div>
          )}
        </div>

        <div className="absolute inset-x-4 bottom-[calc(16px+env(safe-area-inset-bottom))] z-20 rounded-3xl border border-slate-100 bg-white p-4 shadow-2xl">
          <p className="text-xs font-black uppercase tracking-wide text-natalo-700">Alamat terpilih</p>
          <p className="mt-1 text-base font-black text-slate-950">
            {address.jalan || "Geser pin ke titik alamat"}
          </p>
          <p className="mt-1 line-clamp-2 text-xs font-semibold leading-5 text-slate-500">
            {[address.kecamatan, address.kota, address.provinsi, address.kodePos].filter(Boolean).join(", ") ||
              address.formattedAddress ||
              "Alamat akan terbaca setelah pin digeser."}
          </p>
          <p className="mt-2 font-mono text-[11px] text-slate-500">
            {position.lat.toFixed(6)}, {position.lng.toFixed(6)}
          </p>
          {status && <p className="mt-2 text-xs font-bold text-amber-600">{status}</p>}
          <button
            type="button"
            onClick={() => setDialogOpen(true)}
            className="mt-4 h-12 w-full rounded-2xl bg-natalo-600 text-sm font-black text-white shadow-sm transition hover:bg-natalo-700"
          >
            Konfirmasi
          </button>
        </div>

        {dialogOpen && (
          <div className="absolute inset-0 z-30 grid place-items-center bg-slate-950/40 px-5">
            <div className="w-full rounded-3xl bg-white p-5 shadow-2xl">
              <h2 className="text-lg font-black text-slate-950">Mohon konfirmasi lokasimu sesuai peta.</h2>
              <p className="mt-2 text-sm font-semibold leading-6 text-slate-500">
                Lokasi peta harus cocok dengan alamat agar pengiriman berhasil.
              </p>
              <div className="mt-5 grid grid-cols-2 gap-2">
                <button
                  type="button"
                  onClick={() => setDialogOpen(false)}
                  className="h-12 rounded-2xl border border-slate-200 text-sm font-black text-slate-700"
                >
                  Ubah
                </button>
                <button
                  type="button"
                  onClick={confirm}
                  className="h-12 rounded-2xl bg-natalo-600 text-sm font-black text-white"
                >
                  Konfirmasi
                </button>
              </div>
            </div>
          </div>
        )}
      </div>
    </section>
  );
}

function MiniMapPreview({ lat, lng, address }) {
  const { isLoaded } = useJsApiLoader({
    id: "google-maps-address-confirm",
    googleMapsApiKey: GOOGLE_API_KEY,
    libraries: googleLibraries,
  });

  return (
    <section className="overflow-hidden rounded-3xl border border-natalo-100 bg-white shadow-sm">
      <div className="h-40 bg-slate-100">
        {isLoaded && GOOGLE_API_KEY ? (
          <GoogleMap
            mapContainerClassName="h-full w-full"
            center={{ lat, lng }}
            zoom={16}
            options={{ disableDefaultUI: true, clickableIcons: false }}
          >
            <Marker position={{ lat, lng }} />
          </GoogleMap>
        ) : (
          <div className="flex h-full items-center justify-center text-sm font-bold text-slate-500">
            Preview lokasi tersimpan
          </div>
        )}
      </div>
      <div className="p-4">
        <p className="text-sm font-black text-slate-950">Lokasi sudah dikonfirmasi</p>
        <p className="mt-1 line-clamp-2 text-xs font-semibold text-slate-500">{address}</p>
      </div>
    </section>
  );
}

export default function FormAlamat({ mode = "create", initialAddress = null }) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const returnUrl = safeInternalPath(searchParams.get("return") || "", "/akun/alamat");
  const source = searchParams.get("source") || "profile";
  const checkoutReturnUrl = safeInternalPath(searchParams.get("checkoutReturn") || "", "/checkout");
  const isCheckoutFlow = source === "checkout";
  const [screen, setScreen] = useState("form");
  const [selectedPlace, setSelectedPlace] = useState(null);
  const [pickerOpen, setPickerOpen] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState("");
  const [touched, setTouched] = useState({});
  const [form, setForm] = useState(() => mapInitialAddress(initialAddress));

  const errors = useMemo(() => validateField("all", "", form), [form]);
  const visibleErrors = Object.fromEntries(
    Object.entries(errors).filter(([field]) => touched[field] || touched.submit)
  );
  const isValid = Object.keys(errors).length === 0;
  const hasPinpoint = hasUsablePinpoint(form.lat, form.lng);

  function update(field, value) {
    setForm((current) => ({ ...current, [field]: value }));
  }

  function blur(field) {
    setTouched((current) => ({ ...current, [field]: true }));
  }

  function applyMapResult(result) {
    setForm((current) => ({
      ...current,
      jalan: result.jalan || current.jalan,
      provinsi: result.provinsi || current.provinsi,
      kota: result.kota || current.kota,
      kecamatan: result.kecamatan || current.kecamatan,
      kodePos: result.kodePos || current.kodePos,
      lat: result.lat,
      lng: result.lng,
      pinpointAddress: result.pinpointAddress || current.pinpointAddress,
    }));
    setTouched((current) => ({
      ...current,
      jalan: true,
      provinsi: true,
      kota: true,
      kecamatan: true,
      kodePos: true,
    }));
    setScreen("form");
  }

  async function handleSubmit(event) {
    event.preventDefault();
    setSubmitError("");
    setTouched((current) => ({ ...current, submit: true }));
    if (!isValid) return;
    setSubmitting(true);

    const payload = {
      recipient: form.nama,
      nama: form.nama,
      phone: form.phone,
      address: form.jalan,
      jalan: form.jalan,
      detail: form.detail,
      streetName: form.detail,
      provinceName: form.provinsi,
      provinsi: form.provinsi,
      cityName: form.kota,
      city: form.kota,
      kota: form.kota,
      districtName: form.kecamatan,
      kecamatan: form.kecamatan,
      postalCode: form.kodePos,
      kodePos: form.kodePos,
      latitude: form.lat,
      longitude: form.lng,
      lat: form.lat,
      lng: form.lng,
      pinpointAddress: form.pinpointAddress,
      isMain: form.isUtama,
      isUtama: form.isUtama,
      label: form.label || null,
      areaId: form.areaId,
      areaLabel: form.areaLabel,
    };

    try {
      const target = mode === "edit" ? `/api/alamat/${initialAddress.id}` : "/api/alamat";
      const response = await fetch(target, {
        method: mode === "edit" ? "PATCH" : "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || "Gagal menyimpan alamat.");
      if (isCheckoutFlow && data?.address?.id) {
        sessionStorage.setItem(CHECKOUT_SELECTED_ADDRESS_KEY, data.address.id);
        sessionStorage.setItem(CHECKOUT_ADDRESS_FORCE_APPLY_KEY, "1");
        router.push(checkoutReturnUrl);
      } else {
        router.push(returnUrl);
      }
      router.refresh();
    } catch (error) {
      setSubmitError(error instanceof Error ? error.message : "Gagal menyimpan alamat.");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <>
      <form onSubmit={handleSubmit} className="space-y-5">
        {submitError && (
        <div className="rounded-2xl border border-red-100 bg-red-50 px-4 py-3 text-sm font-bold text-red-600">
            {submitError}
          </div>
        )}

        <AddressAutocompleteInput
          value={form.jalan}
          hasPinpoint={hasPinpoint}
          onOpen={() => setScreen("autocomplete")}
        />

        <div className="grid gap-4">
          <Field
            label="Nama Lengkap"
            name="nama"
            value={form.nama}
            onChange={(event) => update("nama", event.target.value)}
            onBlur={() => blur("nama")}
            error={visibleErrors.nama}
          />
          <Field
            label="Nomor Telepon"
            name="phone"
            type="tel"
            value={form.phone}
            onChange={(event) => update("phone", event.target.value)}
            onBlur={() => blur("phone")}
            error={visibleErrors.phone}
          />

          <button
            type="button"
            onClick={() => setPickerOpen(true)}
            className={`rounded-3xl border bg-white p-4 text-left shadow-sm transition ${
              visibleErrors.provinsi || visibleErrors.kota || visibleErrors.kecamatan || visibleErrors.kodePos
                ? "border-red-200"
                : "border-slate-100 hover:border-natalo-200"
            }`}
          >
            <div className="flex items-center justify-between gap-3">
              <div>
                <p className="text-xs font-black uppercase tracking-wide text-slate-500">Wilayah Pengiriman</p>
                <p className="mt-1 text-sm font-black text-slate-950">
                  {[form.kecamatan, form.kota, form.provinsi].filter(Boolean).join(", ") || "Pilih wilayah"}
                </p>
                <p className="mt-1 text-xs font-semibold text-slate-500">
                  {form.kodePos ? `Kode Pos ${form.kodePos}` : "Provinsi, Kota / Kabupaten, Kecamatan, Kode Pos"}
                </p>
              </div>
              <FiChevronDown className="shrink-0 text-slate-400" aria-hidden="true" />
            </div>
          </button>
          {(visibleErrors.provinsi ||
            visibleErrors.kota ||
            visibleErrors.kecamatan ||
            visibleErrors.kodePos) && (
            <p className="-mt-3 text-xs font-bold text-red-500">
              {visibleErrors.provinsi || visibleErrors.kota || visibleErrors.kecamatan || visibleErrors.kodePos}
            </p>
          )}

          <button
            type="button"
            onClick={() => setScreen("autocomplete")}
            onBlur={() => blur("jalan")}
            className={`rounded-3xl border bg-white p-4 text-left shadow-sm transition ${
              visibleErrors.jalan ? "border-red-200" : "border-slate-100 hover:border-natalo-200"
            }`}
          >
            <div className="flex items-start gap-3">
              <span className="mt-0.5 grid h-10 w-10 shrink-0 place-items-center rounded-2xl bg-natalo-50 text-natalo-700">
                <FiMapPin aria-hidden="true" />
              </span>
              <span className="min-w-0 flex-1">
                <span className="text-xs font-black uppercase tracking-wide text-slate-500">Nama Jalan</span>
                <span className={`mt-1 block text-sm font-black ${form.jalan ? "text-slate-950" : "text-slate-400"}`}>
                  {form.jalan || "Pilih alamat terlebih dahulu"}
                </span>
                <span className="mt-1 block text-xs font-semibold text-slate-500">
                  Dipilih dari autocomplete.
                </span>
              </span>
            </div>
          </button>
          {visibleErrors.jalan && <p className="-mt-3 text-xs font-bold text-red-500">{visibleErrors.jalan}</p>}

          <Field
            label="Detail Lainnya / Patokan"
            name="detail"
            value={form.detail}
            as="textarea"
            onChange={(event) => update("detail", event.target.value)}
            onBlur={() => blur("detail")}
            error={visibleErrors.detail}
            placeholder="Contoh: Rumah cat putih, dekat Sinar Aquarium"
          />
        </div>

        {hasPinpoint ? (
          <MiniMapPreview
            lat={form.lat}
            lng={form.lng}
            address={form.pinpointAddress || [form.jalan, form.kecamatan, form.kota].filter(Boolean).join(", ")}
          />
        ) : (
          <button
            type="button"
            onClick={() => setScreen("autocomplete")}
            className={`block w-full rounded-3xl border bg-white p-4 text-left shadow-sm transition ${
              visibleErrors.pinpoint ? "border-red-200" : "border-slate-100 hover:border-natalo-200"
            }`}
          >
            <p className="text-xs font-black uppercase tracking-wide text-slate-500">Konfirmasi Titik Peta</p>
            <p className="mt-1 text-sm font-black text-slate-950">Preview map akan tampil setelah alamat dipilih</p>
            <p className="mt-1 text-xs font-semibold leading-5 text-slate-500">
              Pilih alamat dari rekomendasi, lalu konfirmasi pin lokasi pengiriman.
            </p>
            {visibleErrors.pinpoint && (
              <p className="mt-2 text-xs font-bold text-red-500">{visibleErrors.pinpoint}</p>
            )}
          </button>
        )}

        <section className="rounded-3xl border border-slate-100 bg-white p-4 shadow-sm">
          <div className="flex items-center justify-between gap-4">
            <div>
              <p className="text-sm font-black text-slate-950">Jadikan Alamat Utama</p>
              <p className="mt-1 text-xs font-semibold leading-5 text-slate-500">
                Satu user hanya punya satu alamat utama.
              </p>
            </div>
            <Toggle checked={form.isUtama} onChange={(value) => update("isUtama", value)} />
          </div>
        </section>

        <div>
          <LabelSelector value={form.label} onChange={(value) => update("label", value)} />
          {visibleErrors.label && <p className="mt-1.5 text-xs font-bold text-red-500">{visibleErrors.label}</p>}
        </div>

        <div className="keyboard-hide-on-focus sticky bottom-0 z-50 -mx-4 border-t border-slate-100 bg-white px-4 pb-[calc(12px+env(safe-area-inset-bottom))] pt-3 shadow-[0_-10px_28px_rgba(15,23,42,0.08)] sm:static sm:mx-0 sm:border-0 sm:bg-transparent sm:p-0 sm:shadow-none">
          <button
            type="submit"
            disabled={submitting || !isValid}
            className="h-13 w-full rounded-2xl bg-natalo-600 px-6 py-4 text-sm font-black text-white shadow-sm transition hover:bg-natalo-700 disabled:cursor-not-allowed disabled:bg-slate-300 disabled:text-slate-500"
          >
            {submitting ? "Menyimpan..." : mode === "edit" ? "Simpan Perubahan" : "Simpan Alamat"}
          </button>
          <button
            type="button"
            onClick={() => router.push(returnUrl)}
            className="mt-2 h-12 w-full rounded-2xl px-6 text-sm font-black text-slate-600 transition hover:bg-slate-50"
          >
            Batal
          </button>
        </div>
      </form>

      <LocationPicker
        open={pickerOpen}
        value={form}
        onClose={() => setPickerOpen(false)}
        onApply={(region) => {
          setForm((current) => ({ ...current, ...region, areaId: "", areaLabel: "" }));
          setTouched((current) => ({
            ...current,
            provinsi: true,
            kota: true,
            kecamatan: true,
            kodePos: true,
          }));
        }}
      />

      {screen === "autocomplete" && (
        <StreetAutocomplete
          initialQuery={form.jalan}
          onBack={() => setScreen("form")}
          onManual={(jalan) => {
            update("jalan", jalan);
            blur("jalan");
            setScreen("form");
          }}
          onSelect={(place) => {
            setSelectedPlace(place);
            setScreen("map");
          }}
        />
      )}

      {screen === "map" && selectedPlace && (
        <MapConfirm
          selectedPlace={selectedPlace}
          onBack={() => setScreen("autocomplete")}
          onApply={applyMapResult}
        />
      )}
    </>
  );
}
