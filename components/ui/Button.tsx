import Link from "next/link";
import type { ReactNode, MouseEventHandler } from "react";

type Variant = "primary" | "secondary" | "ghost";
type Size = "sm" | "md";

const VARIANTS: Record<Variant, string> = {
  primary: "bg-natalo-500 text-white hover:bg-natalo-600 active:scale-[0.98]",
  secondary: "bg-natalo-50 text-natalo-700 hover:bg-natalo-100 active:scale-[0.98]",
  ghost: "bg-transparent text-natalo-600 hover:bg-natalo-50",
};

const SIZES: Record<Size, string> = {
  sm: "h-9 px-3 text-sm",
  md: "h-11 px-5 text-sm",
};

type Props = {
  children: ReactNode;
  variant?: Variant;
  size?: Size;
  href?: string;
  type?: "button" | "submit";
  className?: string;
  onClick?: MouseEventHandler<HTMLButtonElement | HTMLAnchorElement>;
  disabled?: boolean;
  "aria-label"?: string;
};

export function Button({
  children,
  variant = "primary",
  size = "md",
  href,
  type = "button",
  className = "",
  onClick,
  disabled = false,
  ...rest
}: Props) {
  const cls = `inline-flex items-center justify-center gap-1.5 rounded-full font-bold transition disabled:cursor-not-allowed disabled:opacity-50 ${VARIANTS[variant]} ${SIZES[size]} ${className}`;
  if (href && !disabled) {
    return (
      <Link href={href} className={cls} onClick={onClick as MouseEventHandler<HTMLAnchorElement>} {...rest}>
        {children}
      </Link>
    );
  }
  return (
    <button type={type} className={cls} onClick={onClick as MouseEventHandler<HTMLButtonElement>} disabled={disabled} {...rest}>
      {children}
    </button>
  );
}
