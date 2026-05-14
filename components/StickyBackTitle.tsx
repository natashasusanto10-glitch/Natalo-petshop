"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState, type ReactNode } from "react";
import { FiArrowLeft } from "react-icons/fi";

type StickyBackTitleProps = {
  label: string;
  subtitle?: string;
  onBack?: () => void;
  href?: string;
  fallbackHref?: string;
  rightAction?: ReactNode;
  variant?: "title" | "textBack";
  stickToTop?: boolean;
};

export function StickyBackTitle({
  label,
  subtitle,
  onBack,
  href,
  fallbackHref = "/",
  rightAction,
  variant = "title",
  stickToTop = false,
}: StickyBackTitleProps) {
  const router = useRouter();
  const [isScrolled, setIsScrolled] = useState(false);

  useEffect(() => {
    function handleScroll() {
      setIsScrolled(window.scrollY > 4);
    }

    handleScroll();
    window.addEventListener("scroll", handleScroll, { passive: true });
    return () => window.removeEventListener("scroll", handleScroll);
  }, []);

  function handleBack() {
    if (onBack) {
      onBack();
      return;
    }
    if (window.history.length > 1) {
      router.back();
      return;
    }
    router.push(fallbackHref);
  }

  const labelClass =
    variant === "textBack"
      ? "text-[18px] font-extrabold leading-tight text-natalo-700"
      : "text-[22px] font-black leading-tight text-slate-950";

  const content = (
    <>
      <FiArrowLeft className="h-[22px] w-[22px] shrink-0" aria-hidden="true" />
      <span className="min-w-0">
        <span className={`block truncate ${labelClass}`}>{label}</span>
        {subtitle && (
          <span className="mt-0.5 block truncate text-xs font-bold text-slate-500">
            {subtitle}
          </span>
        )}
      </span>
    </>
  );

  return (
    <div
      className={`sticky-back-title ${stickToTop ? "sticky-back-title--page-top" : ""} ${
        isScrolled ? "sticky-back-title--scrolled" : ""
      }`}
    >
      <div className="mx-auto flex w-full max-w-4xl items-center justify-between gap-3">
        {href ? (
          <Link
            href={href}
            className="flex min-w-0 flex-1 items-center gap-2.5 rounded-2xl py-1.5 pr-2 transition active:opacity-70"
            aria-label={label}
          >
            {content}
          </Link>
        ) : (
          <button
            type="button"
            onClick={handleBack}
            className="flex min-w-0 flex-1 items-center gap-2.5 rounded-2xl py-1.5 pr-2 text-left transition active:opacity-70"
            aria-label={label}
          >
            {content}
          </button>
        )}
        {rightAction && <div className="shrink-0">{rightAction}</div>}
      </div>
    </div>
  );
}
