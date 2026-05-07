"use client";

export type ManualBankCode = "BCA_NATASHA" | "BCA_NL_PET";

export type PaymentSelection =
  | { provider: "MANUAL"; bank: ManualBankCode }
  | { provider: "MIDTRANS" };

interface Props {
  value: PaymentSelection | null;
  onChange: (value: PaymentSelection) => void;
  midtransAvailable: boolean;
}

const MANUAL_BANKS = [
  {
    code: "BCA_NATASHA" as const,
    bank: "BCA",
    number: "8280277046",
    accountName: "Natasha",
    color: "bg-natalo-500",
  },
  {
    code: "BCA_NL_PET" as const,
    bank: "BCA",
    number: "8372422288",
    accountName: "NL Pet Indonesia CV",
    color: "bg-natalo-500",
  },
];

export function MetodePembayaran({ value, onChange, midtransAvailable }: Props) {
  const isBankSelected = (bank: ManualBankCode) =>
    value?.provider === "MANUAL" && value.bank === bank;
  const isMidtransSelected = value?.provider === "MIDTRANS";

  return (
    <div className="space-y-5">
      <section>
        <h3 className="mb-2 flex items-center gap-2 text-sm font-bold text-zinc-700">
          Transfer Bank Manual
        </h3>
        <p className="mb-3 text-xs text-zinc-500">
          Transfer manual ke rekening kami. Konfirmasi via WhatsApp setelah transfer.
        </p>
        <div className="space-y-2">
          {MANUAL_BANKS.map((b) => (
            <button
              key={b.code}
              type="button"
              onClick={() => onChange({ provider: "MANUAL", bank: b.code })}
              className={`flex w-full items-center justify-between gap-3 rounded-2xl border p-4 text-left transition ${
                isBankSelected(b.code)
                  ? "border-natalo-600 bg-natalo-50"
                  : "border-zinc-200 bg-white hover:border-natalo-300"
              }`}
            >
              <div className="flex items-center gap-3">
                <span
                  className={`inline-flex h-9 w-12 shrink-0 items-center justify-center rounded text-xs font-black text-white ${b.color}`}
                >
                  {b.bank}
                </span>
                <div className="min-w-0">
                  <p className="font-semibold text-zinc-950">Bank {b.bank}</p>
                  <p className="font-mono text-xs text-zinc-500">
                    {b.number} - a/n {b.accountName}
                  </p>
                </div>
              </div>
              {isBankSelected(b.code) && (
                <span className="shrink-0 text-natalo-600">✓</span>
              )}
            </button>
          ))}
        </div>
      </section>

      {midtransAvailable && (
        <section>
          <h3 className="mb-2 flex items-center gap-2 text-sm font-bold text-zinc-700">
            Pembayaran Online
          </h3>
          <p className="mb-3 text-xs text-zinc-500">
            Virtual Account, GoPay, ShopeePay, QRIS - verifikasi otomatis.
          </p>
          <button
            type="button"
            onClick={() => onChange({ provider: "MIDTRANS" })}
            className={`flex w-full items-center justify-between gap-3 rounded-2xl border p-4 text-left transition ${
              isMidtransSelected
                ? "border-natalo-600 bg-natalo-50"
                : "border-zinc-200 bg-white hover:border-natalo-300"
            }`}
          >
            <div className="flex items-center gap-3">
              <span className="inline-flex h-9 w-12 shrink-0 items-center justify-center rounded bg-zinc-900 text-xs font-black text-white">
                Pay
              </span>
              <div className="min-w-0">
                <p className="font-semibold text-zinc-950">Bayar Online (Midtrans)</p>
                <p className="text-xs text-zinc-500">
                  BCA/BNI/BRI/Mandiri VA - GoPay - ShopeePay - QRIS
                </p>
              </div>
            </div>
            {isMidtransSelected && (
              <span className="shrink-0 text-natalo-600">✓</span>
            )}
          </button>

          {isMidtransSelected && (
            <div className="mt-2 flex flex-wrap gap-1.5 px-1">
              {[
                "BCA VA",
                "BNI VA",
                "BRI VA",
                "Mandiri VA",
                "GoPay",
                "ShopeePay",
                "QRIS",
              ].map((m) => (
                <span
                  key={m}
                  className="rounded-full bg-natalo-100 px-2 py-0.5 text-[10px] font-semibold text-natalo-800"
                >
                  {m}
                </span>
              ))}
            </div>
          )}
        </section>
      )}
    </div>
  );
}
