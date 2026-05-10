"use client";

import type { ReactNode } from "react";
import { openExternalLink, type OpenLinkOptions } from "@/lib/external-link";

type Props = {
  href: string;
  children: ReactNode;
  className?: string;
  "aria-label"?: string;
  title?: string;
  onClick?: () => void; // Optional callback yang dijalankan sebelum open
} & OpenLinkOptions;

/**
 * Drop-in replacement untuk `<a href="..." target="_blank">` yang menggunakan
 * Capacitor in-app browser di iOS native (TestFlight/.ipa) — user gak kicked
 * out ke Safari, stay di app dengan SafariViewController.
 *
 * Behavior:
 * - URL native (wa.me, mailto:, tel:) → OS native handler launch (WhatsApp app, Mail, dll)
 * - URL web biasa (https://...) di iOS native → in-app SafariViewController
 * - Web/PWA → window.open(_blank) standard
 *
 * SEO-friendly: tetap pakai `<a>` element dengan href yang valid biar crawler
 * tetap bisa follow link. Click handler intercept di runtime untuk override
 * behavior di iOS native.
 */
export function ExternalLink({
  href,
  children,
  className,
  onClick,
  toolbarColor,
  forceInApp,
  ...rest
}: Props) {
  return (
    <a
      href={href}
      target="_blank"
      rel="noopener noreferrer"
      className={className}
      onClick={(e) => {
        e.preventDefault();
        onClick?.();
        void openExternalLink(href, { toolbarColor, forceInApp });
      }}
      {...rest}
    >
      {children}
    </a>
  );
}
