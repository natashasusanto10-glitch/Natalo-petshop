"use client";

import { GoogleMap, useJsApiLoader } from "@react-google-maps/api";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";

type LatLng = {
  lat: number;
  lng: number;
};

type ParsedAddress = {
  fullAddress: string;
  displayAddress: string;
  streetName: string;
};

export type PinpointValue = {
  latitude: number | null;
  longitude: number | null;
  pinpointAddress: string | null;
  streetName: string | null;
};

type AddressPinpointPickerProps = {
  defaultLatitude?: number | null;
  defaultLongitude?: number | null;
  defaultAddress?: string | null;
  defaultStreetName?: string | null;
  onChange?: (value: PinpointValue) => void;
};

const nataloOrange = "#468284";
const fallbackCenter: LatLng = { lat: -6.2, lng: 106.816666 };
const googleLibraries: "places"[] = ["places"];

const mapOptions: google.maps.MapOptions = {
  disableDefaultUI: true,
  gestureHandling: "greedy",
  zoomControl: false,
  streetViewControl: false,
  mapTypeControl: false,
  fullscreenControl: false,
  clickableIcons: false,
};

function getAddressPart(
  components: google.maps.GeocoderAddressComponent[] | undefined,
  type: string
) {
  return components?.find((component) => component.types.includes(type))?.long_name ?? "";
}

function buildParsedAddress(result: google.maps.GeocoderResult): ParsedAddress {
  const components = result.address_components;
  const streetNumber = getAddressPart(components, "street_number");
  const route = getAddressPart(components, "route");
  const streetName = [route, streetNumber].filter(Boolean).join(" ") || result.formatted_address.split(",")[0] || "";
  const district =
    getAddressPart(components, "administrative_area_level_3") ||
    getAddressPart(components, "sublocality_level_1") ||
    getAddressPart(components, "administrative_area_level_4");
  const city =
    getAddressPart(components, "administrative_area_level_2") ||
    getAddressPart(components, "locality") ||
    getAddressPart(components, "administrative_area_level_1");
  const displayAddress = [streetName, district, city]
    .filter(Boolean)
    .filter((part, index, list) => list.indexOf(part) === index)
    .join(", ");

  return {
    fullAddress: result.formatted_address,
    displayAddress: displayAddress || result.formatted_address,
    streetName,
  };
}

export function AddressPinpointPicker({
  defaultLatitude,
  defaultLongitude,
  defaultAddress,
  defaultStreetName,
  onChange,
}: AddressPinpointPickerProps) {
  const apiKey = process.env.NEXT_PUBLIC_GOOGLE_MAPS_KEY ?? "";
  const initialPosition = useMemo<LatLng | null>(() => {
    if (typeof defaultLatitude === "number" && typeof defaultLongitude === "number") {
      return { lat: defaultLatitude, lng: defaultLongitude };
    }
    return null;
  }, [defaultLatitude, defaultLongitude]);

  const mapRef = useRef<google.maps.Map | null>(null);
  const geocodeTimerRef = useRef<number | null>(null);
  const autocompleteSessionRef = useRef<google.maps.places.AutocompleteSessionToken | null>(null);
  const [isOpen, setIsOpen] = useState(false);
  const [position, setPosition] = useState<LatLng | null>(initialPosition);
  const [mapCenter, setMapCenter] = useState<LatLng>(initialPosition ?? fallbackCenter);
  const [pinpointAddress, setPinpointAddress] = useState(defaultAddress ?? "");
  const [displayAddress, setDisplayAddress] = useState(defaultStreetName || defaultAddress || "");
  const [streetName, setStreetName] = useState(defaultStreetName ?? "");
  const [search, setSearch] = useState("");
  const [suggestions, setSuggestions] = useState<google.maps.places.AutocompleteSuggestion[]>([]);
  const [status, setStatus] = useState("");

  const { isLoaded, loadError } = useJsApiLoader({
    id: "google-maps-pinpoint",
    googleMapsApiKey: apiKey,
    libraries: googleLibraries,
  });

  const onChangeRef = useRef(onChange);
  useEffect(() => {
    onChangeRef.current = onChange;
  }, [onChange]);

  useEffect(() => {
    onChangeRef.current?.({
      latitude: position?.lat ?? null,
      longitude: position?.lng ?? null,
      pinpointAddress: pinpointAddress || null,
      streetName: streetName || null,
    });
  }, [position, pinpointAddress, streetName]);

  const applyGeocoderResult = useCallback((nextPosition: LatLng, result: google.maps.GeocoderResult) => {
    const parsedAddress = buildParsedAddress(result);
    setPosition(nextPosition);
    setMapCenter(nextPosition);
    setPinpointAddress(parsedAddress.fullAddress);
    setDisplayAddress(parsedAddress.displayAddress);
    setStreetName(parsedAddress.streetName);
    setStatus("");
  }, []);

  const reverseGeocode = useCallback((nextPosition: LatLng) => {
    if (!window.google?.maps) return;

    const geocoder = new window.google.maps.Geocoder();
    geocoder.geocode({ location: nextPosition }, (results, geocoderStatus) => {
      if (geocoderStatus === "OK" && results?.[0]) {
        applyGeocoderResult(nextPosition, results[0]);
        return;
      }
      setPosition(nextPosition);
      setMapCenter(nextPosition);
      setStatus("Alamat belum bisa dibaca. Geser peta atau cari alamat.");
    });
  }, [applyGeocoderResult]);

  const reverseGeocodeDebounced = useCallback((nextPosition: LatLng) => {
    if (geocodeTimerRef.current) window.clearTimeout(geocodeTimerRef.current);
    geocodeTimerRef.current = window.setTimeout(() => reverseGeocode(nextPosition), 350);
  }, [reverseGeocode]);

  const moveToPosition = useCallback((nextPosition: LatLng) => {
    setPosition(nextPosition);
    setMapCenter(nextPosition);
    mapRef.current?.panTo(nextPosition);
    reverseGeocode(nextPosition);
  }, [reverseGeocode]);

  const detectLocation = useCallback(() => {
    if (!navigator.geolocation) {
      setStatus("Browser tidak mendukung deteksi GPS.");
      return;
    }

    setStatus("Mendeteksi lokasi...");
    navigator.geolocation.getCurrentPosition(
      (location) => {
        moveToPosition({
          lat: location.coords.latitude,
          lng: location.coords.longitude,
        });
      },
      () => {
        setStatus("Lokasi tidak bisa dideteksi. Cari alamat atau geser peta manual.");
      },
      { enableHighAccuracy: true, timeout: 10000, maximumAge: 30000 }
    );
  }, [moveToPosition]);

  function openModal() {
    setIsOpen(true);
    if (!position) detectLocation();
  }

  function handleMapSettled() {
    const center = mapRef.current?.getCenter();
    if (!center) return;
    const nextPosition = { lat: center.lat(), lng: center.lng() };
    setPosition(nextPosition);
    reverseGeocodeDebounced(nextPosition);
  }

  async function handleSearch(value: string) {
    setSearch(value);
    if (!value.trim() || !window.google?.maps?.places) {
      setSuggestions([]);
      return;
    }

    if (!autocompleteSessionRef.current) {
      autocompleteSessionRef.current = new window.google.maps.places.AutocompleteSessionToken();
    }

    try {
      const { suggestions: nextSuggestions } =
        await window.google.maps.places.AutocompleteSuggestion.fetchAutocompleteSuggestions({
          input: value,
          includedRegionCodes: ["id"],
          language: "id",
          region: "id",
          sessionToken: autocompleteSessionRef.current,
        });
      setSuggestions(nextSuggestions.filter((suggestion) => suggestion.placePrediction));
    } catch {
      setSuggestions([]);
      setStatus("Pencarian alamat belum bisa digunakan. Pastikan Places API baru aktif.");
    }
  }

  async function chooseSuggestion(suggestion: google.maps.places.AutocompleteSuggestion) {
    if (!window.google?.maps || !suggestion.placePrediction) return;

    const prediction = suggestion.placePrediction;
    setSearch(prediction.text.toString());
    setSuggestions([]);
    setStatus("Memindahkan pin...");

    try {
      const place = prediction.toPlace();
      const { place: selectedPlace } = await place.fetchFields({
        fields: ["location", "formattedAddress"],
      });
      const location = selectedPlace.location;

      if (location) {
        const nextPosition = { lat: location.lat(), lng: location.lng() };
        mapRef.current?.panTo(nextPosition);
        reverseGeocode(nextPosition);
        autocompleteSessionRef.current = null;
        return;
      }
    } catch {
      // Fall through to a user-visible status below.
    }

    setStatus("Alamat pilihan belum bisa dibuka.");
  }

  return (
    <div className="rounded-2xl border border-natalo-100 bg-natalo-50/60 p-4">
      <input type="hidden" name="latitude" value={position?.lat ?? ""} />
      <input type="hidden" name="longitude" value={position?.lng ?? ""} />
      <input type="hidden" name="pinpointAddress" value={pinpointAddress} />
      <input type="hidden" name="streetName" value={streetName} />

      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="min-w-0">
          <p className="text-sm font-bold text-gray-900">Pinpoint lokasi</p>
          <p className="mt-0.5 line-clamp-2 text-xs text-gray-600">
            {displayAddress || "Tambahkan titik lokasi pengiriman."}
          </p>
          {position && (
            <p className="mt-1 font-mono text-[11px] text-natalo-800">
              {position.lat.toFixed(6)}, {position.lng.toFixed(6)}
            </p>
          )}
        </div>

        <button
          type="button"
          onClick={openModal}
          className="rounded-full px-5 py-2.5 text-sm font-black text-white shadow-sm transition hover:brightness-95"
          style={{ backgroundColor: nataloOrange }}
        >
          {position ? "Ubah Pinpoint" : "Tambah Pinpoint"}
        </button>
      </div>

      {isOpen && (
        <div className="fixed inset-0 z-50 bg-white">
          <div className="flex h-dvh flex-col bg-white">
            <div className="flex items-center justify-between border-b border-natalo-100 px-4 py-3">
              <button
                type="button"
                onClick={() => setIsOpen(false)}
                className="rounded-full border border-gray-200 px-3 py-1.5 text-sm font-bold text-gray-600"
              >
                Kembali
              </button>
              <p className="text-base font-black text-gray-950">Titik Lokasi</p>
              <div className="w-[68px]" />
            </div>

            {!apiKey && (
              <p className="mx-4 mt-3 rounded-2xl bg-red-50 px-4 py-3 text-sm font-semibold text-red-600">
                NEXT_PUBLIC_GOOGLE_MAPS_KEY belum tersedia.
              </p>
            )}

            {loadError && (
              <p className="mx-4 mt-3 rounded-2xl bg-red-50 px-4 py-3 text-sm font-semibold text-red-600">
                Google Maps gagal dimuat.
              </p>
            )}

            <div className="relative h-[60dvh] min-h-[360px] overflow-hidden bg-gray-100">
              <button
                type="button"
                onClick={detectLocation}
                className="absolute left-4 right-4 top-4 z-10 rounded-full bg-white px-5 py-3 text-sm font-black text-gray-900 shadow-lg"
              >
                Gunakan Lokasi Saat Ini
              </button>

              {isLoaded ? (
                <GoogleMap
                  mapContainerClassName="h-full w-full"
                  center={mapCenter}
                  zoom={position ? 17 : 12}
                  options={mapOptions}
                  onLoad={(map) => {
                    mapRef.current = map;
                  }}
                  onDragEnd={handleMapSettled}
                  onZoomChanged={handleMapSettled}
                />
              ) : (
                <div className="flex h-full items-center justify-center text-sm font-semibold text-gray-500">
                  Memuat Google Maps...
                </div>
              )}

              <div className="pointer-events-none absolute left-1/2 top-1/2 z-10 -translate-x-1/2 -translate-y-full">
                <div className="h-9 w-9 rounded-full border-4 border-white bg-green-500 shadow-lg" />
                <div className="mx-auto h-4 w-1 rounded-full bg-green-600 shadow" />
              </div>
            </div>

            <div className="flex min-h-0 flex-1 flex-col gap-3 px-4 py-4">
              <div className="relative">
                <input
                  type="search"
                  value={search}
                  onChange={(event) => handleSearch(event.target.value)}
                  placeholder="Cari alamat"
                  className="w-full rounded-2xl border border-gray-200 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-natalo-400"
                />

                {suggestions.length > 0 && (
                  <div className="absolute left-0 right-0 top-[calc(100%+8px)] z-20 max-h-64 overflow-auto rounded-2xl border border-gray-100 bg-white shadow-xl">
                    {suggestions.map((suggestion) => {
                      const prediction = suggestion.placePrediction;
                      if (!prediction) return null;

                      return (
                      <button
                        key={prediction.placeId}
                        type="button"
                        onClick={() => chooseSuggestion(suggestion)}
                        className="block w-full border-b border-gray-100 px-4 py-3 text-left last:border-b-0 hover:bg-natalo-50"
                      >
                        <span className="block text-sm font-black text-gray-900">
                          {prediction.mainText?.text ?? prediction.text.toString()}
                        </span>
                        <span className="mt-0.5 block text-xs font-semibold text-gray-500">
                          {prediction.secondaryText?.text ?? ""}
                        </span>
                      </button>
                      );
                    })}
                  </div>
                )}
              </div>

              <div className="rounded-2xl border border-natalo-100 bg-natalo-50 px-4 py-3">
                <p className="text-xs font-bold uppercase tracking-wide text-natalo-800">Alamat terpilih</p>
                <p className="mt-1 text-sm font-black text-gray-950">
                  {displayAddress || "Belum ada lokasi dipilih"}
                </p>
                {pinpointAddress && (
                  <p className="mt-1 line-clamp-2 text-xs font-semibold text-gray-600">
                    {pinpointAddress}
                  </p>
                )}
                {status && <p className="mt-1 text-xs font-semibold text-natalo-800">{status}</p>}
              </div>

              <button
                type="button"
                onClick={() => setIsOpen(false)}
                disabled={!position}
                className="mt-auto w-full rounded-full px-6 py-4 text-sm font-black text-white shadow-sm disabled:opacity-40"
                style={{ backgroundColor: nataloOrange }}
              >
                Pilih Lokasi Ini
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
