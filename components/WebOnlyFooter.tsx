"use client";

import { useEffect, useState } from "react";
import { isCapacitorNative } from "@/lib/native-platform";

/**
 * Wrapper untuk menyembunyikan footer besar saat app jalan di Capacitor
 * native (iOS .ipa / Android APK). Di native shell, user sudah punya bottom
 * navigation untuk navigasi utama — footer besar terasa redundant + tidak
 * native. Link legal (T&C / Privasi / Pengembalian) tersedia di /bantuan.
 *
 * Browser biasa + PWA install dari browser → footer tetap render normal.
 *
 * Pakai children prop supaya `<Footer />` tetap server component (SSR penuh).
 * Initial state `null` → render null sampai client mount; hindari flash
 * footer-lalu-hilang di native (worst-case web: footer muncul setelah JS load,
 * sama dengan delay biasa lazy component).
 */
export function WebOnlyFooter({ children }: { children: React.ReactNode }) {
  const [isNative, setIsNative] = useState<boolean | null>(null);

  useEffect(() => {
    const native = isCapacitorNative();
    setIsNative(native);
    document.body.classList.toggle("capacitor-app", native);

    return () => {
      document.body.classList.remove("capacitor-app");
    };
  }, []);

  if (isNative !== false) return null;
  return <>{children}</>;
}
