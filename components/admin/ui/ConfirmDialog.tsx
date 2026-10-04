"use client";
import { AdminDialog } from "./AdminDialog";
import { Button } from "./Button";

export function ConfirmDialog({
  open,
  title = "Konfirmasi",
  message,
  confirmLabel = "Ya, lanjut",
  cancelLabel = "Batal",
  variant = "danger",
  onConfirm,
  onCancel,
  busy = false,
  error,
}: {
  open: boolean;
  title?: string;
  message: string;
  confirmLabel?: string;
  cancelLabel?: string;
  variant?: "danger" | "primary";
  onConfirm(): void;
  onCancel(): void;
  busy?: boolean;
  error?: string;
}) {
  return (
    <AdminDialog
      open={open}
      title={title}
      onClose={onCancel}
      busy={busy}
      footer={
        <>
          <Button
            type="button"
            variant="secondary"
            data-dialog-autofocus
            autoFocus
            onClick={onCancel}
            disabled={busy}
          >
            {cancelLabel}
          </Button>
          <Button
            type="button"
            variant={variant}
            onClick={onConfirm}
            disabled={busy}
            aria-busy={busy}
          >
            {busy ? "Memproses…" : confirmLabel}
          </Button>
        </>
      }
    >
      <p className="whitespace-pre-line text-sm leading-relaxed text-slate-600">
        {message}
      </p>
      {error && (
        <p role="alert" className="mt-3 text-sm text-red-700">
          {error}
        </p>
      )}
    </AdminDialog>
  );
}
