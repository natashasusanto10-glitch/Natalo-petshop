import Link from "next/link";
import type { ComponentPropsWithoutRef, ReactNode } from "react";

/**
 * Button — primitive aksi kanonik untuk admin. Satu sumber warna + radius +
 * tinggi (target sentuh ≥44px) + focus-visible, menggantikan CTA yang
 * sebelumnya di-hardcode berbeda-beda tiap halaman.
 *
 * Aturan warna:
 *   - primary   → aksi utama "maju" (biru brand). Maks 1 per konteks.
 *   - secondary → aksi sekunder (outline netral).
 *   - ghost     → aksi tersier / low-emphasis.
 *   - danger    → aksi destruktif solid (Hapus permanen).
 *   - dangerSoft→ aksi destruktif low-emphasis (outline merah).
 *
 * Render sebagai <button> secara default, atau sebagai Next <Link> kalau
 * diberi prop `href`.
 */
export type ButtonVariant =
  | "primary"
  | "secondary"
  | "ghost"
  | "danger"
  | "dangerSoft";
export type ButtonSize = "sm" | "md";

const BASE =
  "inline-flex items-center justify-center gap-2 rounded-full font-bold transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-natalo-400 focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50";

const VARIANT_CLASSES: Record<ButtonVariant, string> = {
  primary: "bg-natalo-600 text-white shadow-sm hover:bg-natalo-700",
  secondary:
    "border border-zinc-300 bg-white text-zinc-700 hover:border-zinc-400 hover:bg-zinc-50",
  ghost: "text-zinc-700 hover:bg-zinc-100",
  danger: "bg-red-600 text-white shadow-sm hover:bg-red-500",
  dangerSoft:
    "border border-red-200 bg-white text-red-600 hover:border-red-300 hover:bg-red-50",
};

// Tinggi minimum 44px (min-h-11) untuk target sentuh; `sm` untuk konteks
// tabel desktop yang padat (tetap ≥36px, dipakai di area non-mobile).
const SIZE_CLASSES: Record<ButtonSize, string> = {
  md: "min-h-11 px-5 text-sm",
  sm: "min-h-9 px-3.5 text-xs",
};

type BaseProps = {
  variant?: ButtonVariant;
  size?: ButtonSize;
  fullWidth?: boolean;
  className?: string;
  children: ReactNode;
};

type ButtonProps = BaseProps &
  Omit<ComponentPropsWithoutRef<"button">, "className" | "children"> & {
    href?: undefined;
  };

type LinkProps = BaseProps &
  Omit<ComponentPropsWithoutRef<typeof Link>, "className" | "children"> & {
    href: string;
  };

export type ButtonComponentProps = ButtonProps | LinkProps;

function classes(
  variant: ButtonVariant,
  size: ButtonSize,
  fullWidth: boolean,
  className: string,
): string {
  return [BASE, VARIANT_CLASSES[variant], SIZE_CLASSES[size], fullWidth && "w-full", className]
    .filter(Boolean)
    .join(" ");
}

export function Button({
  variant = "primary",
  size = "md",
  fullWidth = false,
  className = "",
  children,
  ...rest
}: ButtonComponentProps) {
  const cls = classes(variant, size, fullWidth, className);

  if ("href" in rest && typeof rest.href === "string") {
    const linkProps = rest as Omit<ComponentPropsWithoutRef<typeof Link>, "className">;
    return (
      <Link className={cls} {...linkProps}>
        {children}
      </Link>
    );
  }

  const buttonProps = rest as Omit<ComponentPropsWithoutRef<"button">, "className">;
  return (
    <button className={cls} {...buttonProps}>
      {children}
    </button>
  );
}

/** Sugar untuk aksi destruktif solid. */
export function DangerButton(props: Omit<ButtonProps, "variant">) {
  return <Button variant="danger" {...props} />;
}
