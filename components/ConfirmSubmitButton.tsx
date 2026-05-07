"use client";

interface Props {
  message: string;
  className?: string;
  children: React.ReactNode;
}

/**
 * Tombol submit yang menampilkan window.confirm() sebelum form dikirim.
 * Pakai sebagai child di dalam <form action={...}>.
 */
export function ConfirmSubmitButton({ message, className, children }: Props) {
  return (
    <button
      type="submit"
      className={className}
      onClick={(e) => {
        if (!confirm(message)) e.preventDefault();
      }}
    >
      {children}
    </button>
  );
}
