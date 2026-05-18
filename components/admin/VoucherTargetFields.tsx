"use client";

import { useEffect, useMemo, useState } from "react";

type Props = {
  defaultTargetUser?: "ALL_MEMBERS" | "NEW_MEMBER";
  defaultMaxAccountAgeDays?: number | null;
  defaultRequireNoSuccessfulOrder?: boolean;
  defaultUsageLimitPeriod?: "NONE" | "LIFETIME" | "DAY" | "WEEK" | "MONTH";
  defaultUsageLimitPerUser?: number | null;
};

const AGE_PRESETS = [7, 14, 30] as const;

export function VoucherTargetFields({
  defaultTargetUser = "ALL_MEMBERS",
  defaultMaxAccountAgeDays = 14,
  defaultRequireNoSuccessfulOrder = true,
  defaultUsageLimitPeriod = "NONE",
  defaultUsageLimitPerUser = 0,
}: Props) {
  const normalizedDefaultMaxAgeDays = defaultMaxAccountAgeDays ?? 14;
  const initialPreset = useMemo(() => {
    if (
      normalizedDefaultMaxAgeDays &&
      AGE_PRESETS.includes(normalizedDefaultMaxAgeDays as (typeof AGE_PRESETS)[number])
    ) {
      return String(normalizedDefaultMaxAgeDays);
    }
    return "custom";
  }, [normalizedDefaultMaxAgeDays]);
  const [targetUser, setTargetUser] = useState(defaultTargetUser);
  const [agePreset, setAgePreset] = useState(initialPreset);
  const [voucherKind, setVoucherKind] = useState("PRODUCT_DISCOUNT");
  const [usageLimitPeriod, setUsageLimitPeriod] = useState(defaultUsageLimitPeriod);

  const isProductDiscount = voucherKind === "PRODUCT_DISCOUNT";
  const isPublicReusableKind =
    voucherKind === "PRODUCT_DISCOUNT" || voucherKind === "FREE_SHIPPING";
  const showNewMemberRules = isProductDiscount && targetUser === "NEW_MEMBER";
  const customDefault =
    normalizedDefaultMaxAgeDays &&
    !AGE_PRESETS.includes(normalizedDefaultMaxAgeDays as (typeof AGE_PRESETS)[number])
      ? String(normalizedDefaultMaxAgeDays)
      : "";

  useEffect(() => {
    const field = document.querySelector<HTMLSelectElement>('select[name="kind"]');
    if (!field) return;

    const syncKind = () => {
      setVoucherKind(field.value);
      if (field.value !== "PRODUCT_DISCOUNT") {
        setTargetUser("ALL_MEMBERS");
      }
      if (field.value === "MANUAL_PRIVATE") {
        setUsageLimitPeriod("LIFETIME");
      } else if (defaultUsageLimitPeriod === "NONE") {
        setUsageLimitPeriod("NONE");
      }
    };

    syncKind();
    field.addEventListener("change", syncKind);
    return () => field.removeEventListener("change", syncKind);
  }, []);

  return (
    <section className="rounded-2xl border border-blue-100 bg-blue-50/40 p-4">
      <p className="text-sm font-black text-zinc-950">Target Pengguna</p>
      <p className="mt-1 text-xs font-semibold text-zinc-500">
        Member baru hanya untuk Voucher Diskon Produk. Gratis ongkir tetap bisa pakai batas pemakaian publik.
      </p>
      <div className="mt-3 grid gap-2 sm:grid-cols-2">
        <label className="flex cursor-pointer items-center gap-3 rounded-xl border border-white bg-white px-4 py-3 text-sm font-bold text-zinc-700 shadow-sm">
          <input
            type="radio"
            name="targetUser"
            value="ALL_MEMBERS"
            checked={targetUser === "ALL_MEMBERS"}
            onChange={() => setTargetUser("ALL_MEMBERS")}
            className="h-4 w-4 accent-blue-600"
          />
          Semua Member
        </label>
        <label
          className={`flex items-center gap-3 rounded-xl border border-white bg-white px-4 py-3 text-sm font-bold text-zinc-700 shadow-sm ${
            isProductDiscount ? "cursor-pointer" : "cursor-not-allowed opacity-55"
          }`}
        >
          <input
            type="radio"
            name="targetUser"
            value="NEW_MEMBER"
            checked={targetUser === "NEW_MEMBER"}
            onChange={() => setTargetUser("NEW_MEMBER")}
            disabled={!isProductDiscount}
            className="h-4 w-4 accent-blue-600"
          />
          Khusus Member Baru
        </label>
      </div>

      {!isProductDiscount && (
        <p className="mt-2 rounded-xl bg-white px-3 py-2 text-xs font-semibold text-zinc-500">
          Target member baru otomatis nonaktif karena tipe voucher ini bukan Diskon Produk.
        </p>
      )}

      {showNewMemberRules && (
        <div className="mt-4 rounded-2xl border border-blue-100 bg-white p-4">
          <p className="text-xs font-black uppercase tracking-wide text-blue-700">
            Syarat Member Baru
          </p>

          <div className="mt-3 grid gap-4 sm:grid-cols-2">
            <div>
              <label className="block text-sm font-medium text-zinc-700">
                Maksimal umur akun sejak registrasi
              </label>
              <select
                name="newMemberMaxAccountAgePreset"
                value={agePreset}
                onChange={(event) => setAgePreset(event.target.value)}
                className="mt-1 block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-zinc-600"
              >
                <option value="7">7 hari</option>
                <option value="14">14 hari</option>
                <option value="30">30 hari</option>
                <option value="custom">Custom</option>
              </select>
            </div>

            {agePreset === "custom" && (
              <div>
                <label className="block text-sm font-medium text-zinc-700">
                  Custom umur akun (hari)
                </label>
                <input
                  type="number"
                  name="newMemberMaxAccountAgeDays"
                  min={1}
                  defaultValue={customDefault}
                  placeholder="Contoh: 21"
                  className="mt-1 block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-zinc-600"
                />
              </div>
            )}
          </div>

          {agePreset !== "custom" && (
            <input type="hidden" name="newMemberMaxAccountAgeDays" value={agePreset} />
          )}

          <label className="mt-4 flex items-start gap-3 rounded-xl bg-blue-50 px-3 py-3 text-sm font-semibold text-zinc-700">
            <input
              type="checkbox"
              name="newMemberRequireNoSuccessfulOrder"
              defaultChecked={defaultRequireNoSuccessfulOrder}
              className="mt-0.5 h-4 w-4 accent-blue-600"
            />
            <span>Hanya untuk user yang belum pernah checkout berhasil</span>
          </label>
        </div>
      )}

      <input
        type="hidden"
        name="newMemberRulesEnabled"
        value={showNewMemberRules ? "1" : "0"}
      />

      <div className="mt-4">
        <label className="block text-sm font-medium text-zinc-700">
          Batas pemakaian per user
        </label>
        {isPublicReusableKind ? (
          <>
            <select
              name="usageLimitPeriod"
              value={usageLimitPeriod}
              onChange={(event) =>
                setUsageLimitPeriod(event.target.value as typeof usageLimitPeriod)
              }
              className="mt-1 block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-zinc-600"
            >
              <option value="NONE">Tanpa batas per user</option>
              <option value="LIFETIME">1x per user</option>
              <option value="DAY">X kali per hari</option>
              <option value="WEEK">X kali per minggu</option>
              <option value="MONTH">X kali per bulan</option>
            </select>

            {(usageLimitPeriod === "DAY" ||
              usageLimitPeriod === "WEEK" ||
              usageLimitPeriod === "MONTH") && (
              <input
                type="number"
                name="usageLimitPerUser"
                min={1}
                defaultValue={String(defaultUsageLimitPerUser && defaultUsageLimitPerUser > 0 ? defaultUsageLimitPerUser : 1)}
                className="mt-3 block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-zinc-600"
                placeholder="Contoh: 3"
              />
            )}

            {usageLimitPeriod === "NONE" && (
              <input type="hidden" name="usageLimitPerUser" value="0" />
            )}
            {usageLimitPeriod === "LIFETIME" && (
              <input type="hidden" name="usageLimitPerUser" value="1" />
            )}
          </>
        ) : (
          <>
            <div className="mt-1 rounded-xl border border-zinc-200 bg-white px-4 py-3 text-sm font-bold text-zinc-600">
              1x per user
            </div>
            <input type="hidden" name="usageLimitPeriod" value="LIFETIME" />
            <input type="hidden" name="usageLimitPerUser" value="1" />
          </>
        )}
        <p className="mt-1 text-xs text-zinc-400">
          Default voucher publik admin adalah tanpa batas per user, sehingga bisa dipakai lagi di order berikutnya.
        </p>
      </div>
    </section>
  );
}
