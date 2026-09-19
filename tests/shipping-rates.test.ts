import assert from "node:assert/strict";
import { afterEach, describe, it } from "node:test";
import {
  fetchShippingRateOptions,
  resolveServerShippingFee,
} from "@/lib/shipping-rates";

// resolveServerShippingFee baca env Biteship per call — set/restore env di
// sekitar tiap kasus supaya tes tidak saling bocor state. originAreaId
// selalu di-pass eksplisit supaya tes tidak menyentuh DB.
const ORIGINAL_FETCH = globalThis.fetch;
let savedEnv: Record<string, string | undefined> = {};

function setBiteshipEnv(env: { enabled?: string; apiKey?: string }) {
  savedEnv = {
    BITESHIP_ENABLED: process.env.BITESHIP_ENABLED,
    BITESHIP_API_KEY: process.env.BITESHIP_API_KEY,
  };
  if (env.enabled === undefined) delete process.env.BITESHIP_ENABLED;
  else process.env.BITESHIP_ENABLED = env.enabled;
  if (env.apiKey === undefined) delete process.env.BITESHIP_API_KEY;
  else process.env.BITESHIP_API_KEY = env.apiKey;
}

function stubFetch(handler: () => Promise<Response>) {
  globalThis.fetch = handler as typeof fetch;
}

afterEach(() => {
  globalThis.fetch = ORIGINAL_FETCH;
  for (const [key, value] of Object.entries(savedEnv)) {
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
  savedEnv = {};
});

const ITEMS = [
  { name: "Whiskas 1kg", price: 85000, weightGram: 1000, quantity: 2 },
];

describe("fetchShippingRateOptions — mode dummy/flat", () => {
  it("mode tanpa Biteship → 4 tarif flat + message", async () => {
    setBiteshipEnv({ apiKey: undefined });
    const result = await fetchShippingRateOptions({
      originAreaId: null,
      destinationAreaId: "IDN102",
      items: ITEMS,
    });
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.equal(result.rates.length, 4);
    assert.match(result.message ?? "", /tarif flat/);
  });
});

describe("resolveServerShippingFee — mode dummy/flat", () => {
  it("tarif jne/reg = 18000 (pencocokan case-insensitive)", async () => {
    setBiteshipEnv({ apiKey: undefined });
    const result = await resolveServerShippingFee({
      courierCode: "JNE",
      courierService: "REG",
      destinationAreaId: "IDN102",
      items: ITEMS,
      originAreaId: "TEST-ORIGIN",
    });
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.equal(result.price, 18000);
  });

  it("kurir tidak dikenal → ok:false courier-not-found", async () => {
    setBiteshipEnv({ apiKey: undefined });
    const result = await resolveServerShippingFee({
      courierCode: "lion",
      courierService: "reg",
      destinationAreaId: "IDN102",
      items: ITEMS,
      originAreaId: "TEST-ORIGIN",
    });
    assert.deepEqual(result, {
      ok: false,
      reason: "courier-not-found",
      message:
        "Tarif kurir yang dipilih tidak tersedia untuk alamat ini. Pilih ulang kurir lalu coba lagi.",
    });
  });

  it("courierService kosong → ok:false courier-not-found", async () => {
    setBiteshipEnv({ apiKey: undefined });
    const result = await resolveServerShippingFee({
      courierCode: "jne",
      courierService: "",
      destinationAreaId: "IDN102",
      items: ITEMS,
      originAreaId: "TEST-ORIGIN",
    });
    assert.equal(result.ok, false);
    if (result.ok) return;
    assert.equal(result.reason, "courier-not-found");
  });
});

describe("resolveServerShippingFee — mode Biteship", () => {
  it("memetakan pricing Biteship ke tarif kurir terpilih", async () => {
    setBiteshipEnv({ enabled: "true", apiKey: "test-key" });
    stubFetch(async () =>
      Response.json({
        pricing: [
          {
            courier_name: "JNE",
            courier_code: "jne",
            courier_service_name: "REG",
            courier_service_code: "reg",
            service_type: "regular",
            price: 21000,
            duration: "2-3 hari",
          },
          {
            courier_name: "J&T Express",
            courier_code: "jnt",
            courier_service_name: "EZ",
            courier_service_code: "ez",
            service_type: "regular",
            price: 19500,
            duration: "2-3 hari",
          },
        ],
      }),
    );
    const result = await resolveServerShippingFee({
      courierCode: "jnt",
      courierService: "ez",
      destinationAreaId: "IDN102",
      items: ITEMS,
      originAreaId: "TEST-ORIGIN",
    });
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.equal(result.price, 19500);
  });

  it("fetch gagal (network) → ok:false unavailable — fail-closed", async () => {
    setBiteshipEnv({ enabled: "true", apiKey: "test-key" });
    stubFetch(async () => {
      throw new Error("connection refused");
    });
    const result = await resolveServerShippingFee({
      courierCode: "jne",
      courierService: "reg",
      destinationAreaId: "IDN102",
      items: ITEMS,
      originAreaId: "TEST-ORIGIN",
    });
    assert.equal(result.ok, false);
    if (result.ok) return;
    assert.equal(result.reason, "unavailable");
  });

  it("Biteship balas HTTP error → ok:false unavailable — fail-closed", async () => {
    setBiteshipEnv({ enabled: "true", apiKey: "test-key" });
    stubFetch(async () => new Response("bad request", { status: 400 }));
    const result = await resolveServerShippingFee({
      courierCode: "jne",
      courierService: "reg",
      destinationAreaId: "IDN102",
      items: ITEMS,
      originAreaId: "TEST-ORIGIN",
    });
    assert.equal(result.ok, false);
    if (result.ok) return;
    assert.equal(result.reason, "unavailable");
  });

  it("tarif price 0 (tidak tersedia) → ok:false courier-not-found", async () => {
    setBiteshipEnv({ enabled: "true", apiKey: "test-key" });
    stubFetch(async () =>
      Response.json({
        pricing: [
          {
            courier_name: "JNE",
            courier_code: "jne",
            courier_service_name: "REG",
            courier_service_code: "reg",
            service_type: "regular",
            price: 0,
            duration: "—",
          },
        ],
      }),
    );
    const result = await resolveServerShippingFee({
      courierCode: "jne",
      courierService: "reg",
      destinationAreaId: "IDN102",
      items: ITEMS,
      originAreaId: "TEST-ORIGIN",
    });
    assert.equal(result.ok, false);
    if (result.ok) return;
    assert.equal(result.reason, "courier-not-found");
  });
});
