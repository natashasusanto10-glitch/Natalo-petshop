"use client";

/**
 * Form input pengiriman untuk markAsShipped — support 2 mode kurir:
 *
 *   1. REGULAR (JNE, JNT, SiCepat, Pos, Anteraja, dll)
 *      → Input nomor resi tradisional (text 1 baris)
 *
 *   2. INSTANT (Gojek, Grab, Lalamove, Borzo, dll)
 *      → Input info driver (textarea, free-form)
 *      Kurir instant tidak punya resi resmi — admin biasanya isi:
 *      "Nama: Pak Budi | HP: 0812... | Plat: B 1234 ABC" atau link
 *      share GPS dari aplikasi Gojek/Grab.
 *
 * Server-side validation (lihat actions.ts markAsShipped):
 *   - courierType=REGULAR → trackingNumber wajib
 *   - courierType=INSTANT → shippingDriverInfo wajib
 * Form ini juga apply client-side validation (button disable) supaya
 * admin dapat instant feedback tanpa round trip.
 *
 * Dipakai di dua context:
 *   - submitLabel="Tandai sudah dikirim" → status PROCESSING → SHIPPED
 *   - submitLabel="Update info pengiriman" → status SHIPPED (edit info)
 */
import { useState } from "react";
import { Button } from "@/components/admin/ui";

type CourierType = "REGULAR" | "INSTANT";

type Props = {
  action: (formData: FormData) => Promise<void>;
  /** Default values dari order existing. */
  defaultTrackingNumber: string;
  defaultDriverInfo: string;
  /** "Tandai sudah dikirim" atau "Update info pengiriman". */
  submitLabel: string;
  /** Primary (PROCESSING→SHIPPED) vs secondary (edit) styling. */
  variant?: "primary" | "secondary";
};

export default function ShippingForm({
  action,
  defaultTrackingNumber,
  defaultDriverInfo,
  submitLabel,
  variant = "primary",
}: Props) {
  // Auto-detect initial mode dari data existing: kalau driverInfo udah
  // ada (tapi resi kosong), default ke INSTANT. Else REGULAR.
  const initialType: CourierType =
    defaultDriverInfo.length > 0 && defaultTrackingNumber.length === 0
      ? "INSTANT"
      : "REGULAR";

  const [courierType, setCourierType] = useState<CourierType>(initialType);
  const [trackingNumber, setTrackingNumber] = useState(defaultTrackingNumber);
  const [driverInfo, setDriverInfo] = useState(defaultDriverInfo);

  const isFilled =
    courierType === "REGULAR"
      ? trackingNumber.trim().length > 0
      : driverInfo.trim().length > 0;

  return (
    <form action={action} className="space-y-3">
      {/* Hidden field carries courierType ke server */}
      <input type="hidden" name="courierType" value={courierType} />

      {/* Toggle Regular vs Instant */}
      <div className="flex gap-2 rounded-2xl bg-zinc-100 p-1">
        <button
          type="button"
          onClick={() => setCourierType("REGULAR")}
          className={`flex-1 rounded-xl px-3 py-2 text-xs font-bold transition ${
            courierType === "REGULAR"
              ? "bg-white text-zinc-900 shadow-sm"
              : "text-zinc-500 hover:text-zinc-700"
          }`}
        >
          📦 Kurir Regular
        </button>
        <button
          type="button"
          onClick={() => setCourierType("INSTANT")}
          className={`flex-1 rounded-xl px-3 py-2 text-xs font-bold transition ${
            courierType === "INSTANT"
              ? "bg-white text-zinc-900 shadow-sm"
              : "text-zinc-500 hover:text-zinc-700"
          }`}
        >
          🛵 Kurir Instant
        </button>
      </div>

      {/* Helper text di bawah toggle */}
      <p className="text-xs text-zinc-500">
        {courierType === "REGULAR"
          ? "JNE, JNT, SiCepat, Pos, Anteraja, Paxel, dll."
          : "Gojek Instant, GrabExpress, Lalamove, Borzo, dll."}
      </p>

      {courierType === "REGULAR" ? (
        <div>
          <label className="block text-xs font-bold text-zinc-700 mb-1">
            Nomor Resi <span className="text-red-500">*</span>
          </label>
          <input
            name="trackingNumber"
            placeholder="Contoh: JX1234567890"
            value={trackingNumber}
            onChange={(e) => setTrackingNumber(e.target.value)}
            className="w-full rounded-2xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-zinc-600"
            required
            autoComplete="off"
          />
          {/* Empty driverInfo supaya field sebelumnya (kalau switch) di-clear */}
          <input type="hidden" name="shippingDriverInfo" value="" />
        </div>
      ) : (
        <div>
          <label className="block text-xs font-bold text-zinc-700 mb-1">
            Info Driver <span className="text-red-500">*</span>
          </label>
          <textarea
            name="shippingDriverInfo"
            placeholder={`Contoh:\nNama: Pak Budi\nHP: 0812-3456-7890\nPlat: B 1234 ABC\nLink GPS: https://gojek.id/track/abc`}
            value={driverInfo}
            onChange={(e) => setDriverInfo(e.target.value)}
            rows={4}
            maxLength={500}
            className="w-full rounded-2xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-zinc-600 font-mono"
            required
          />
          <p className="mt-1 text-xs text-zinc-400">
            {driverInfo.length}/500 karakter
          </p>
          {/* Empty resi supaya field sebelumnya di-clear kalau switch */}
          <input type="hidden" name="trackingNumber" value="" />
        </div>
      )}

      <Button
        type="submit"
        disabled={!isFilled}
        variant={variant === "primary" ? "primary" : "secondary"}
        fullWidth
      >
        {variant === "primary" ? "🚚 " : ""}
        {submitLabel}
      </Button>
    </form>
  );
}
