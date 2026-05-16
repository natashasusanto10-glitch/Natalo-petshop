"use client";

import {
  useEffect,
  useRef,
  useState,
  type MouseEvent,
  type ReactNode,
  type TouchEvent,
} from "react";
import { Drawer } from "vaul";

interface Props {
  open: boolean;
  onClose: () => void;
  title?: string;
  children: ReactNode;
  /** Tombol di footer, optional. Misal "Apply" / "Reset" */
  footer?: ReactNode;
  variant?: "light" | "dark";
}

const DRAG_CLOSE_THRESHOLD = 120;
const SNAP_BACK_MS = 320;
// iOS Core Animation spring curve dengan slight overshoot — bikin snap-back
// terasa "physical" mirip native sheet, bukan ease-out flat.
const SNAP_BACK_EASE = "cubic-bezier(0.34, 1.26, 0.64, 1)";

let scrollLockCount = 0;
let scrollLockSnapshot: {
  scrollX: number;
  scrollY: number;
  body: Partial<CSSStyleDeclaration>;
  html: Partial<CSSStyleDeclaration>;
} | null = null;

function lockPageScroll() {
  if (scrollLockCount === 0) {
    const body = document.body;
    const html = document.documentElement;
    const scrollX = window.scrollX;
    const scrollY = window.scrollY;

    scrollLockSnapshot = {
      scrollX,
      scrollY,
      body: {
        overflow: body.style.overflow,
        overscrollBehavior: body.style.overscrollBehavior,
        position: body.style.position,
        top: body.style.top,
        left: body.style.left,
        right: body.style.right,
        width: body.style.width,
        height: body.style.height,
        touchAction: body.style.touchAction,
      },
      html: {
        overflow: html.style.overflow,
        overscrollBehavior: html.style.overscrollBehavior,
      },
    };

    body.style.overflow = "hidden";
    body.style.overscrollBehavior = "none";
    body.style.position = "fixed";
    body.style.top = `-${scrollY}px`;
    body.style.left = `-${scrollX}px`;
    body.style.right = "0";
    body.style.width = "100%";
    body.style.height = "100dvh";
    body.style.touchAction = "none";
    html.style.overflow = "hidden";
    html.style.overscrollBehavior = "none";
    body.classList.add("nat-modal-open", "bottom-sheet-open", "nat-scroll-locked");
    html.classList.add("nat-scroll-locked");
  }

  scrollLockCount += 1;
}

function unlockPageScroll() {
  scrollLockCount = Math.max(0, scrollLockCount - 1);
  if (scrollLockCount > 0 || !scrollLockSnapshot) return;

  const { body, html, scrollX, scrollY } = scrollLockSnapshot;
  Object.assign(document.body.style, body);
  Object.assign(document.documentElement.style, html);
  document.body.classList.remove("nat-modal-open", "bottom-sheet-open", "nat-scroll-locked");
  document.documentElement.classList.remove("nat-scroll-locked");
  window.scrollTo(scrollX, scrollY);
  scrollLockSnapshot = null;
}

/**
 * Bottom sheet drawer dari bawah - mobile-friendly.
 * Backdrop klik untuk close. Esc juga close.
 * Body scroll di-lock saat open, including iOS fixed-position locking.
 */
export function BottomSheet({
  open,
  onClose,
  title,
  children,
  footer,
  variant = "light",
}: Props) {
  const sheetRef = useRef<HTMLDivElement | null>(null);
  const dragStartYRef = useRef(0);
  const dragYRef = useRef(0);
  const isDraggingRef = useRef(false);
  const snapBackTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [dragY, setDragY] = useState(0);
  const [isDragging, setIsDragging] = useState(false);
  const [isSnappingBack, setIsSnappingBack] = useState(false);

  useEffect(() => {
    if (!open) return;
    lockPageScroll();
    return unlockPageScroll;
  }, [open]);

  useEffect(() => {
    if (!open) return;
    function handler(e: KeyboardEvent) {
      if (e.key === "Escape") onClose();
    }
    document.addEventListener("keydown", handler);
    return () => document.removeEventListener("keydown", handler);
  }, [open, onClose]);

  useEffect(() => {
    if (!open) {
      setDragY(0);
      dragYRef.current = 0;
      isDraggingRef.current = false;
      setIsDragging(false);
      setIsSnappingBack(false);
    }
  }, [open]);

  useEffect(() => {
    if (!isDragging) return;

    function handleMouseMove(event: globalThis.MouseEvent) {
      updateDrag(event.clientY);
      if (dragYRef.current > 0) event.preventDefault();
    }

    function handleMouseUp() {
      finishDrag();
    }

    document.addEventListener("mousemove", handleMouseMove, { passive: false });
    document.addEventListener("mouseup", handleMouseUp);
    return () => {
      document.removeEventListener("mousemove", handleMouseMove);
      document.removeEventListener("mouseup", handleMouseUp);
    };
  }, [isDragging]);

  useEffect(() => {
    return () => {
      if (snapBackTimerRef.current) clearTimeout(snapBackTimerRef.current);
    };
  }, []);

  function beginDrag(target: EventTarget | null, clientY: number) {
    if (target instanceof HTMLElement && target.closest("button")) return;

    if (snapBackTimerRef.current) clearTimeout(snapBackTimerRef.current);
    dragStartYRef.current = clientY;
    isDraggingRef.current = true;
    setIsDragging(true);
    setIsSnappingBack(false);
    dragYRef.current = 0;
    setDragY(0);
  }

  function updateDrag(clientY: number) {
    if (!isDraggingRef.current) return;
    const nextDragY = Math.max(0, clientY - dragStartYRef.current);
    dragYRef.current = nextDragY;
    setDragY(nextDragY);
  }

  function finishDrag() {
    if (!isDraggingRef.current) return;
    isDraggingRef.current = false;
    setIsDragging(false);

    const sheetHeight = sheetRef.current?.getBoundingClientRect().height ?? DRAG_CLOSE_THRESHOLD;
    const closeThreshold = Math.min(DRAG_CLOSE_THRESHOLD, sheetHeight * 0.3);

    if (dragYRef.current >= closeThreshold) {
      onClose();
      return;
    }

    setIsSnappingBack(true);
    dragYRef.current = 0;
    setDragY(0);
    snapBackTimerRef.current = setTimeout(() => setIsSnappingBack(false), SNAP_BACK_MS);
  }

  function handleMouseDown(event: MouseEvent<HTMLDivElement>) {
    if (event.button !== 0) return;
    beginDrag(event.target, event.clientY);
  }

  function handleTouchStart(event: TouchEvent<HTMLDivElement>) {
    const touch = event.touches[0];
    if (!touch) return;
    beginDrag(event.target, touch.clientY);
  }

  function handleTouchMove(event: TouchEvent<HTMLDivElement>) {
    const touch = event.touches[0];
    if (!touch) return;
    updateDrag(touch.clientY);
    if (dragYRef.current > 0 && event.cancelable) event.preventDefault();
  }

  if (!open || typeof document === "undefined") return null;

  const isDark = variant === "dark";

  return (
    <Drawer.Root
      open={open}
      onOpenChange={(nextOpen) => {
        if (!nextOpen) onClose();
      }}
      direction="bottom"
      modal
      dismissible={false}
      handleOnly
      closeThreshold={0.3}
      scrollLockTimeout={350}
      noBodyStyles
    >
      <Drawer.Portal>
        <Drawer.Overlay
          data-no-pull
          data-no-swipe-back="true"
          className="nat-bottom-sheet-overlay fixed inset-0 z-[2000] bg-black/45"
          onClick={onClose}
        />
        <Drawer.Content
          ref={sheetRef}
          data-no-pull
          data-no-swipe-back="true"
          aria-describedby={undefined}
          className={`nat-bottom-sheet fixed inset-x-0 bottom-0 z-[2001] ml-auto mr-auto flex w-full max-w-2xl flex-col overflow-hidden rounded-t-3xl outline-none ${
            isDark
              ? "bg-[#0B0F14] text-white shadow-[0_-18px_45px_rgba(0,0,0,0.45)]"
              : "bg-white shadow-2xl"
          }`}
          onOpenAutoFocus={(event) => event.preventDefault()}
          style={{
            maxHeight: "min(90dvh, calc(100dvh - env(safe-area-inset-top)))",
            touchAction: "pan-y",
            transform:
              isDragging || isSnappingBack ? `translate3d(0, ${dragY}px, 0)` : undefined,
            transition: isDragging
              ? "none"
              : isSnappingBack
                ? `transform ${SNAP_BACK_MS}ms ${SNAP_BACK_EASE}`
                : undefined,
          }}
        >
          <div
            className="nat-bottom-sheet-drag-zone shrink-0 px-5 pb-3 pt-2"
            onMouseDown={handleMouseDown}
            onTouchStart={handleTouchStart}
            onTouchMove={handleTouchMove}
            onTouchEnd={finishDrag}
            onTouchCancel={finishDrag}
          >
            <div className="flex justify-center py-2">
              <div
                className={`h-1.5 w-10 rounded-full ${
                  isDark ? "bg-zinc-600" : "bg-zinc-300"
                }`}
              />
            </div>

            {title && (
              <div className="flex items-center justify-between gap-4">
                <Drawer.Title
                  className={`text-lg font-black ${
                    isDark ? "text-white" : "text-zinc-950"
                  }`}
                >
                  {title}
                </Drawer.Title>
                <button
                  type="button"
                  aria-label="Tutup"
                  onClick={onClose}
                  className={`grid h-9 w-9 shrink-0 place-items-center rounded-full transition ${
                    isDark
                      ? "text-zinc-300 hover:bg-white/10 hover:text-white active:bg-white/10"
                      : "text-zinc-400 hover:bg-zinc-100 hover:text-zinc-950 active:bg-zinc-100"
                  }`}
                >
                  <svg
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="2.3"
                    className="h-5 w-5"
                    aria-hidden="true"
                  >
                    <path d="M18 6 6 18" strokeLinecap="round" />
                    <path d="m6 6 12 12" strokeLinecap="round" />
                  </svg>
                </button>
              </div>
            )}
          </div>

          <div
            className={`nat-bottom-sheet-scroll min-h-0 flex-1 overflow-y-auto border-t p-5 ${
              isDark
                ? "border-[#242B33] bg-[#0B0F14]"
                : "border-zinc-100 bg-white"
            }`}
          >
            {children}
          </div>

          {footer && (
            <div
              className={`sticky bottom-0 z-10 shrink-0 border-t px-4 pt-4 [padding-bottom:calc(16px+env(safe-area-inset-bottom))] ${
                isDark
                  ? "border-[#242B33] bg-[#0B0F14]"
                  : "border-zinc-100 bg-white"
              }`}
            >
              {footer}
            </div>
          )}
        </Drawer.Content>
      </Drawer.Portal>
    </Drawer.Root>
  );
}
