"use client";

import { useRef, useState } from "react";

type PasswordInputProps = {
  value?: string;
  onChange?: (event: React.ChangeEvent<HTMLInputElement>) => void;
  name?: string;
  required?: boolean;
  minLength?: number;
  placeholder?: string;
  autoComplete?: string;
  disabled?: boolean;
  className?: string;
};

export function PasswordInput({
  value,
  onChange,
  name,
  required,
  minLength,
  placeholder,
  autoComplete,
  disabled,
  className,
}: PasswordInputProps) {
  const [visible, setVisible] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  // Toggle handler — dipakai untuk semua event (touch & click)
  // iOS Safari: kalau focus pindah ke input, cursor position di-preserve.
  function toggle() {
    const el = inputRef.current;
    const cursor = el?.selectionStart ?? null;
    setVisible((current) => !current);
    // Kembalikan focus + cursor ke input setelah React re-render
    requestAnimationFrame(() => {
      if (el) {
        el.focus();
        if (cursor !== null) {
          try {
            el.setSelectionRange(cursor, cursor);
          } catch {
            // setSelectionRange tidak didukung untuk semua type, abaikan
          }
        }
      }
    });
  }

  return (
    <div className="relative mt-1">
      <input
        ref={inputRef}
        type={visible ? "text" : "password"}
        name={name}
        value={value}
        onChange={onChange}
        required={required}
        minLength={minLength}
        placeholder={placeholder}
        autoComplete={autoComplete}
        disabled={disabled}
        className={`${className ?? ""} mt-0 pr-12 password-input-no-native-reveal`}
      />
      <button
        type="button"
        disabled={disabled}
        aria-label={visible ? "Sembunyikan password" : "Tampilkan password"}
        aria-pressed={visible}
        // SIMPLE: hanya onClick — paling reliable cross-browser termasuk iOS Safari.
        // Tidak ada onMouseDown/onTouchEnd preventDefault yang bisa memblokir click di iOS.
        onClick={toggle}
        className="absolute right-1 top-1/2 z-10 flex h-11 w-11 -translate-y-1/2 cursor-pointer items-center justify-center text-[#999] transition hover:text-[#1E88E5] active:text-[#1E88E5] disabled:cursor-not-allowed disabled:opacity-40"
        style={{
          touchAction: "manipulation",
          WebkitTapHighlightColor: "transparent",
          // Pastikan tombol bisa di-tap (override apapun dari parent)
          pointerEvents: "auto",
        }}
      >
        {visible ? <EyeOpenIcon /> : <EyeClosedIcon />}
      </button>
    </div>
  );
}

function EyeOpenIcon() {
  return (
    <svg
      aria-hidden="true"
      className="pointer-events-none h-5 w-5"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.8}
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M2.5 12s3.5-6 9.5-6 9.5 6 9.5 6-3.5 6-9.5 6-9.5-6-9.5-6Z" />
      <circle cx="12" cy="12" r="3" fill="currentColor" stroke="none" />
      <path d="M7 4.8 5.8 2.9" />
      <path d="M10 3.6 9.6 1.5" />
      <path d="M14 3.6 14.4 1.5" />
      <path d="M17 4.8 18.2 2.9" />
    </svg>
  );
}

function EyeClosedIcon() {
  return (
    <svg
      aria-hidden="true"
      className="pointer-events-none h-5 w-5"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.8}
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M4 13.5c2.2 2.2 4.9 3.3 8 3.3s5.8-1.1 8-3.3" />
      <path d="M7 16.2 5.6 18.4" />
      <path d="M10.2 17.3 9.7 19.8" />
      <path d="M13.8 17.3 14.3 19.8" />
      <path d="M17 16.2 18.4 18.4" />
    </svg>
  );
}
