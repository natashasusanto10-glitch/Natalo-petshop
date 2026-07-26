import assert from "node:assert/strict";
import test, { describe } from "node:test";
import { missingFcmConfigKeys, readFcmConfig } from "@/lib/fcm";

const full = {
  FCM_PROJECT_ID: "natalo-app",
  FCM_CLIENT_EMAIL: "svc@natalo-app.iam.gserviceaccount.com",
  FCM_PRIVATE_KEY: "-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----",
};

describe("readFcmConfig", () => {
  test("membaca ketiga env apa adanya", () => {
    const c = readFcmConfig(full);
    assert.equal(c.projectId, "natalo-app");
    assert.equal(c.clientEmail, "svc@natalo-app.iam.gserviceaccount.com");
    assert.ok(c.rawPrivateKey?.includes("BEGIN PRIVATE KEY"));
  });
});

describe("missingFcmConfigKeys", () => {
  test("config lengkap → tidak ada yang hilang", () => {
    assert.deepEqual(missingFcmConfigKeys(full), []);
  });

  test("menyebut PERSIS env mana yang hilang, bukan sekadar 'FCM mati'", () => {
    // Nilainya masuk ke log peringatan. Pesan generik memaksa orang menebak
    // saat push native mati total; nama env yang eksplisit langsung menunjuk
    // ke setting Vercel yang perlu diperbaiki.
    assert.deepEqual(missingFcmConfigKeys({ ...full, FCM_PRIVATE_KEY: "" }), [
      "FCM_PRIVATE_KEY",
    ]);
    assert.deepEqual(
      missingFcmConfigKeys({ ...full, FCM_PROJECT_ID: undefined }),
      ["FCM_PROJECT_ID"],
    );
  });

  test("env kosong sama sekali → ketiganya dilaporkan", () => {
    assert.deepEqual(missingFcmConfigKeys({}), [
      "FCM_PROJECT_ID",
      "FCM_CLIENT_EMAIL",
      "FCM_PRIVATE_KEY",
    ]);
  });

  test("string kosong diperlakukan hilang, bukan ada", () => {
    // Vercel menyimpan env yang dihapus isinya sebagai string kosong, bukan
    // undefined — kalau ini lolos sebagai "ada", init akan gagal di firebase
    // dengan error yang jauh lebih kabur.
    assert.deepEqual(
      missingFcmConfigKeys({
        FCM_PROJECT_ID: "",
        FCM_CLIENT_EMAIL: "",
        FCM_PRIVATE_KEY: "",
      }),
      ["FCM_PROJECT_ID", "FCM_CLIENT_EMAIL", "FCM_PRIVATE_KEY"],
    );
  });
});
