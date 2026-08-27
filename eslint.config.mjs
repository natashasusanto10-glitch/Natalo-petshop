import reactHooks from "eslint-plugin-react-hooks";
import tseslint from "typescript-eslint";

/**
 * Minimal ESLint flat config — fokus ke react-hooks rules untuk catch
 * bug rules-of-hooks (lihat commit a22d91a — VoucherCard hooks count
 * mismatch yang loloskan production error).
 *
 * Pakai typescript-eslint parser untuk TSX/TS support. Sengaja TIDAK
 * pakai eslint-config-next preset karena ada compat issue dengan ESLint
 * 9 flat config (circular structure JSON).
 *
 * Run: `npm run lint` atau `npx eslint .`
 */
export default [
  {
    ignores: [
      ".next/**",
      "node_modules/**",
      "natalo-petshop-app/**",
      "android/**",
      "ios/**",
      "out/**",
      "build/**",
      "dist/**",
      "next-env.d.ts",
      "scripts/**",
      "prisma/**",
      "public/**",
      // SDK Flutter TERPASANG DI DALAM folder proyek (lihat FLUTTER_ROOT di
      // flutter_app/ios/Flutter/Generated.xcconfig). Tanpa baris ini eslint
      // memindai seluruh SDK — termasuk bundle DevTools Dart — dan
      // melaporkan 11 error palsu ("Definition for rule
      // 'import/no-unused-modules' was not found") dari kode yang bukan
      // milik kita. Berkas .js kena walau blok `files` di bawah hanya
      // menyebut ts/tsx/mjs, karena ESLint 9 memeriksa .js secara bawaan.
      "flutter/**",
      // App Flutter isinya Dart (nol berkas js/ts terlacak). Di-ignore
      // supaya artefak build web-nya tidak ikut terpindai.
      "flutter_app/**",
    ],
  },
  {
    files: ["**/*.{ts,tsx,mjs}"],
    languageOptions: {
      parser: tseslint.parser,
      parserOptions: {
        ecmaVersion: "latest",
        sourceType: "module",
        ecmaFeatures: { jsx: true },
      },
    },
    linterOptions: {
      // Disable processing inline `// eslint-disable` comments — banyak
      // file punya disable untuk rules dari plugin yg tidak kita load
      // (mis. @next/next/no-img-element). Kita cuma peduli react-hooks
      // di-config ini, jadi inline disable untuk rules lain tidak relevan.
      noInlineConfig: true,
    },
    plugins: {
      "react-hooks": reactHooks,
    },
    rules: {
      // Rules-of-hooks WAJIB error — prevent regress dari bug VoucherCard.
      "react-hooks/rules-of-hooks": "error",
      // Exhaustive-deps warn — banyak pattern intentional omit di codebase.
      "react-hooks/exhaustive-deps": "warn",
    },
  },
];
