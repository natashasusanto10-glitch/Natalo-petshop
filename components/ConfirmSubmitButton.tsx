"use client";

import { useRef, useState } from "react";
import { ConfirmDialog } from "@/components/admin/ui";

interface Props {
  message: string;
  className?: string;
  children: React.ReactNode;
  /** Judul dialog (opsional, default "Konfirmasi"). */
  title?: string;
  /** Label tombol konfirmasi (opsional, default "Ya, lanjut"). */
  confirmLabel?: string;
}

/**
 * Tombol submit yang meminta konfirmasi lewat modal berstyle (ConfirmDialog)
 * sebelum men-submit form induknya — pengganti window.confirm. API sama
 * (message/className/children), jadi semua call-site lama otomatis naik kelas.
 *
 * Alur: klik → preventDefault + buka modal. Klik "Ya" → form.requestSubmit()
 * dengan tombol ini sebagai submitter (name/value tetap terkirim).
 */
export function ConfirmSubmitButton({
  message,
  className,
  children,
  title,
  confirmLabel,
}: Props) {
  const [open, setOpen] = useState(false);
  const btnRef = useRef<HTMLButtonElement>(null);

  return (
    <>
      <button
        ref={btnRef}
        type="submit"
        className={className}
        onClick={(e) => {
          e.preventDefault();
          setOpen(true);
        }}
      >
        {children}
      </button>
      <ConfirmDialog
        open={open}
        title={title}
        message={message}
        confirmLabel={confirmLabel ?? "Ya, lanjut"}
        variant="danger"
        onCancel={() => setOpen(false)}
        onConfirm={() => {
          setOpen(false);
          btnRef.current?.form?.requestSubmit(btnRef.current);
        }}
      />
    </>
  );
}
