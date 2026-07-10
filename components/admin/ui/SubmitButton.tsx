"use client";

import type { ReactNode } from "react";
import { useFormStatus } from "react-dom";
import { Button, type ButtonSize, type ButtonVariant } from "./Button";

/**
 * Tombol submit dengan pending-state otomatis via useFormStatus(). Saat
 * <form action={serverAction}> sedang diproses, tombol otomatis disabled +
 * menampilkan teks pending. WAJIB dipakai sebagai descendant dari <form>
 * (Next.js server action) — di luar form, `pending` selalu false.
 */
export function SubmitButton({
  children,
  pendingText = "Menyimpan…",
  variant,
  size,
  fullWidth,
  className,
}: {
  children: ReactNode;
  pendingText?: string;
  variant?: ButtonVariant;
  size?: ButtonSize;
  fullWidth?: boolean;
  className?: string;
}) {
  const { pending } = useFormStatus();
  return (
    <Button
      type="submit"
      variant={variant}
      size={size}
      fullWidth={fullWidth}
      className={className}
      disabled={pending}
      aria-busy={pending}
    >
      {pending ? pendingText : children}
    </Button>
  );
}
