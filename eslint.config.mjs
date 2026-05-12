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
