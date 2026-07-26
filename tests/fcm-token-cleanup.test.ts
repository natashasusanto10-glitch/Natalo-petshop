import assert from "node:assert/strict";
import test, { describe } from "node:test";
import { isDeadTokenError } from "@/lib/fcm";

describe("isDeadTokenError", () => {
  test("token di-uninstall / tidak terdaftar → boleh dihapus", () => {
    assert.equal(
      isDeadTokenError("messaging/registration-token-not-registered"),
      true,
    );
  });

  test("token bentuknya tidak valid → boleh dihapus", () => {
    assert.equal(isDeadTokenError("messaging/invalid-registration-token"), true);
  });

  test("invalid-argument TIDAK menghapus token — itu error payload", () => {
    // Regresi terpenting di file ini. Kode ini dulu ada di daftar hapus.
    // Payload sama dikirim ke SEMUA token dalam satu multicast, jadi satu
    // bug bentuk pesan akan menghapus seluruh token di database sekaligus —
    // Android + iOS, semua user — dan push baru pulih setelah tiap user
    // membuka app lagi. Kerusakan permanen dari bug yang sifatnya sementara.
    assert.equal(isDeadTokenError("messaging/invalid-argument"), false);
  });

  test("error transien server FCM tidak menghapus token", () => {
    assert.equal(isDeadTokenError("messaging/server-unavailable"), false);
    assert.equal(isDeadTokenError("messaging/internal-error"), false);
    assert.equal(isDeadTokenError("messaging/quota-exceeded"), false);
  });

  test("error tanpa kode tidak menghapus token", () => {
    assert.equal(isDeadTokenError(undefined), false);
  });

  test("kode yang tidak dikenal default-nya aman (pertahankan token)", () => {
    assert.equal(isDeadTokenError("messaging/sesuatu-yang-baru"), false);
  });
});
