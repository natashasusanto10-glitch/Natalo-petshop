#!/usr/bin/env node
/**
 * Build APK admin variant dari inner Capacitor project (natalo-petshop-app/).
 *
 * Pendekatan: swap konfigurasi sementara di `natalo-petshop-app/` →
 * cap sync → gradle assembleRelease → rename output → revert konfigurasi.
 * Aman karena setiap perubahan di-undo di blok finally.
 *
 * Catatan: project utama (toko-pwa-starter) punya outer Capacitor v8 di
 * folder ./android/ yang tidak terpakai untuk produksi. Build sebenarnya
 * pakai inner project natalo-petshop-app/ (Capacitor v6).
 *
 * Output: natalo-petshop-app/dist/natalo-admin-<version>.apk
 *
 * Usage: npm run apk:admin:release
 */
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync, copyFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, "..");
const APP_DIR = resolve(ROOT, "natalo-petshop-app");
const ANDROID_DIR = resolve(APP_DIR, "android");

const ADMIN_APPLICATION_ID = "com.natalopetshop.app.admin";
const ADMIN_APP_NAME = "Natalo Admin";
const ADMIN_URL = "https://www.natalopetshop.com/admin/login";
const CUSTOMER_APPLICATION_ID = "com.natalopetshop.app";
const CUSTOMER_APP_NAME = "Natalo Petshop";
const CUSTOMER_URL = "https://www.natalopetshop.com";

const FILES = {
  capacitorConfig: resolve(APP_DIR, "capacitor.config.ts"),
  buildGradle: resolve(ANDROID_DIR, "app/build.gradle"),
  strings: resolve(ANDROID_DIR, "app/src/main/res/values/strings.xml"),
};

const APK_INPUT = resolve(
  ANDROID_DIR,
  "app/build/outputs/apk/release/app-release.apk",
);
const APK_OUTPUT_DIR = resolve(APP_DIR, "dist");

function log(msg) {
  console.log(`\n▶ ${msg}`);
}

function readVersionName() {
  const gradle = readFileSync(FILES.buildGradle, "utf8");
  const m = gradle.match(/versionName\s+"([^"]+)"/);
  return m ? m[1] : "unknown";
}

function swapToAdmin() {
  // capacitor.config.ts (inner)
  let cap = readFileSync(FILES.capacitorConfig, "utf8");
  cap = cap.replace(
    /appId:\s*['"]com\.natalopetshop\.app['"]/,
    `appId: '${ADMIN_APPLICATION_ID}'`,
  );
  cap = cap.replace(
    /appName:\s*['"]Natalo Petshop['"]/,
    `appName: '${ADMIN_APP_NAME}'`,
  );
  cap = cap.replace(
    /url:\s*['"]https:\/\/www\.natalopetshop\.com['"]/,
    `url: '${ADMIN_URL}'`,
  );
  writeFileSync(FILES.capacitorConfig, cap);

  // app/build.gradle — hanya applicationId
  let gradle = readFileSync(FILES.buildGradle, "utf8");
  gradle = gradle.replace(
    /applicationId\s+"com\.natalopetshop\.app"/,
    `applicationId "${ADMIN_APPLICATION_ID}"`,
  );
  writeFileSync(FILES.buildGradle, gradle);

  // strings.xml
  let strings = readFileSync(FILES.strings, "utf8");
  strings = strings.replace(
    /<string name="app_name">[^<]+<\/string>/,
    `<string name="app_name">${ADMIN_APP_NAME}</string>`,
  );
  strings = strings.replace(
    /<string name="title_activity_main">[^<]+<\/string>/,
    `<string name="title_activity_main">${ADMIN_APP_NAME}</string>`,
  );
  strings = strings.replace(
    /<string name="package_name">[^<]+<\/string>/,
    `<string name="package_name">${ADMIN_APPLICATION_ID}</string>`,
  );
  strings = strings.replace(
    /<string name="custom_url_scheme">[^<]+<\/string>/,
    `<string name="custom_url_scheme">${ADMIN_APPLICATION_ID}</string>`,
  );
  writeFileSync(FILES.strings, strings);
}

function restoreFromBackups(backups) {
  writeFileSync(FILES.capacitorConfig, backups.capacitorConfig);
  writeFileSync(FILES.buildGradle, backups.buildGradle);
  writeFileSync(FILES.strings, backups.strings);
}

function run(cmd, args, options = {}) {
  const result = spawnSync(cmd, args, {
    cwd: options.cwd ?? APP_DIR,
    stdio: "inherit",
    shell: true,
    ...options,
  });
  if (result.status !== 0) {
    throw new Error(`Command failed: ${cmd} ${args.join(" ")}`);
  }
}

async function main() {
  // Sanity check: inner node_modules harus ada
  if (!existsSync(resolve(APP_DIR, "node_modules/@capacitor/android"))) {
    throw new Error(
      `natalo-petshop-app/node_modules belum di-install. Jalankan dulu:\n` +
      `   cd natalo-petshop-app && npm install`,
    );
  }

  const versionName = readVersionName();
  log(`Mulai build admin APK (versi ${versionName})`);

  // Backup in-memory — di-restore di finally
  const backups = {
    capacitorConfig: readFileSync(FILES.capacitorConfig, "utf8"),
    buildGradle: readFileSync(FILES.buildGradle, "utf8"),
    strings: readFileSync(FILES.strings, "utf8"),
  };

  try {
    log("Swap konfigurasi → admin variant");
    swapToAdmin();

    log("Sync Capacitor ke Android (dari inner project)");
    run("npx", ["cap", "sync", "android"], { cwd: APP_DIR });

    log("Build APK release via Gradle (bisa makan beberapa menit)");
    run(".\\gradlew.bat", ["assembleRelease"], { cwd: ANDROID_DIR });

    if (!existsSync(APK_INPUT)) {
      throw new Error(`APK output tidak ditemukan di ${APK_INPUT}`);
    }

    if (!existsSync(APK_OUTPUT_DIR)) mkdirSync(APK_OUTPUT_DIR, { recursive: true });
    const finalPath = resolve(APK_OUTPUT_DIR, `natalo-admin-${versionName}.apk`);
    copyFileSync(APK_INPUT, finalPath);
    log(`✓ Selesai: ${finalPath}`);
  } finally {
    log("Revert konfigurasi → customer variant");
    restoreFromBackups(backups);
    try {
      run("npx", ["cap", "sync", "android"], { cwd: APP_DIR });
    } catch {
      console.warn(
        "\n⚠ Final cap sync revert gagal — jalankan manual sebelum build customer berikutnya.",
      );
    }
  }
}

main().catch((err) => {
  console.error("\n✗ Build admin APK gagal:", err.message);
  process.exit(1);
});
