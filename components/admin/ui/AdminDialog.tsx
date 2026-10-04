"use client";

import { useEffect, useId, useRef, useState, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { adminMotionAllowed } from "./Motion";

export function AdminDialog({
  open,
  title,
  onClose,
  children,
  footer,
  busy = false,
  className = "",
  side = false,
}: {
  open: boolean;
  title: string;
  onClose(): void;
  children: ReactNode;
  footer?: ReactNode;
  busy?: boolean;
  className?: string;
  side?: boolean;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  const titleId = useId();
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);
  const closeRef = useRef(onClose);
  closeRef.current = onClose;
  const previousFocus = useRef<HTMLElement | null>(null);
  const bodyOverflow = useRef<string | null>(null);
  const restore = () => {
    if (bodyOverflow.current !== null) {
      document.body.style.overflow = bodyOverflow.current;
      bodyOverflow.current = null;
    }
    previousFocus.current?.focus({ preventScroll: true });
    previousFocus.current = null;
  };
  useEffect(() => {
    const dialog = ref.current;
    if (!dialog) return;
    if (!open) {
      if (!dialog.open) return;
      const close = () => {
        dialog.close();
        restore();
      };
      if (!adminMotionAllowed()) {
        close();
        return;
      }
      const animation = dialog.animate(
        [
          { opacity: 1, transform: side ? "translateX(0)" : "scale(1)" },
          { opacity: 0, transform: side ? "translateX(24px)" : "scale(.98)" },
        ],
        { duration: 120, easing: "ease-in" }
      );
      void animation.finished.then(close).catch(() => {});
      return () => animation.cancel();
    }
    if (!dialog.open) {
      previousFocus.current = document.activeElement as HTMLElement | null;
      bodyOverflow.current = document.body.style.overflow;
      dialog.showModal();
      document.body.style.overflow = "hidden";
      dialog
        .querySelector<HTMLElement>(
          "[data-dialog-autofocus],input:not([disabled]),textarea:not([disabled]),select:not([disabled])"
        )
        ?.focus({ preventScroll: true });
    }
    const animation = adminMotionAllowed()
      ? dialog.animate(
          [
            { opacity: 0, transform: side ? "translateX(24px)" : "scale(.98)" },
            { opacity: 1, transform: side ? "translateX(0)" : "scale(1)" },
          ],
          { duration: 200, easing: "cubic-bezier(.2,.8,.2,1)" }
        )
      : null;
    return () => animation?.cancel();
  }, [open, mounted, side]);
  useEffect(() => () => restore(), []);
  if (!mounted) return null;
  return createPortal(
    <dialog
      ref={ref}
      className={`admin-dialog ${className}`}
      aria-labelledby={titleId}
      aria-busy={busy}
      onCancel={(event) => {
        event.preventDefault();
        if (!busy) closeRef.current();
      }}
      onClick={(event) => {
        if (event.target !== event.currentTarget || busy) return;
        const r = event.currentTarget.getBoundingClientRect();
        if (
          event.clientX < r.left ||
          event.clientX > r.right ||
          event.clientY < r.top ||
          event.clientY > r.bottom
        )
          closeRef.current();
      }}
    >
      <header>
        <h2 id={titleId}>{title}</h2>
        <button
          type="button"
          aria-label="Tutup dialog"
          onClick={onClose}
          disabled={busy}
          className="admin-icon-button"
        >
          ×
        </button>
      </header>
      <div className="admin-dialog-body">{children}</div>
      {footer && <footer>{footer}</footer>}
    </dialog>,
    document.body
  );
}
