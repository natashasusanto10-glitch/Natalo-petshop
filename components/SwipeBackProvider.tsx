"use client";

import { usePathname, useRouter } from "next/navigation";
import {
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { createPortal } from "react-dom";
import { getSwipeBackRouteConfig } from "@/lib/swipe-back-routes";

type Props = {
  children: ReactNode;
};

type PageSnapshot = {
  node: HTMLElement;
  pathname: string;
  scrollY: number;
};

type GestureState = {
  active: boolean;
  locked: boolean;
  committing: boolean;
  startX: number;
  startY: number;
  lastX: number;
  lastT: number;
  x: number;
  raf: number | null;
};

const EDGE_SIZE = 28;
const STRICT_EDGE_SIZE = 12;
const DIRECTION_LOCK_DISTANCE = 8;
const VERTICAL_CANCEL_DISTANCE = 42;
const COMMIT_DISTANCE_RATIO = 0.35;
const MIN_COMMIT_DISTANCE = 48;
const COMMIT_VELOCITY = 0.55;
const SNAP_BACK_MS = 220;
const COMMIT_MS = 240;
const EASING = "cubic-bezier(0.32, 0.72, 0, 1)";

const EMPTY_GESTURE: GestureState = {
  active: false,
  locked: false,
  committing: false,
  startX: 0,
  startY: 0,
  lastX: 0,
  lastT: 0,
  x: 0,
  raf: null,
};

function canUseDOM() {
  return typeof window !== "undefined" && typeof document !== "undefined";
}

function isInternalHref(href: string | null): href is string {
  return Boolean(href && href.startsWith("/") && !href.startsWith("//"));
}

function normalizePathname(pathname: string): string {
  if (pathname.length > 1 && pathname.endsWith("/")) {
    return pathname.slice(0, -1);
  }
  return pathname;
}

function shouldIgnoreSwipe(target: EventTarget | null, startX: number): boolean {
  if (!canUseDOM()) return true;
  if (!(target instanceof HTMLElement)) return false;

  if (
    target.closest(
      [
        "input",
        "textarea",
        "select",
        "button",
        "a",
        "[role='button']",
        '[role="button"]',
        "[contenteditable='true']",
        '[contenteditable="true"]',
        "[data-no-swipe-back='true']",
        '[data-no-swipe-back="true"]',
        "[data-modal='true']",
        '[data-modal="true"]',
        "[data-drawer='true']",
        '[data-drawer="true"]',
      ].join(","),
    )
  ) {
    return true;
  }

  const horizontalGestureTarget = target.closest(
    [
      "[data-horizontal-scroll='true']",
      '[data-horizontal-scroll="true"]',
      "[data-carousel='true']",
      '[data-carousel="true"]',
      ".swiper",
      ".swiper-wrapper",
      ".swiper-slide",
    ].join(","),
  );

  return Boolean(horizontalGestureTarget && startX > STRICT_EDGE_SIZE);
}

function isBodyOverlayOpen(): boolean {
  if (!canUseDOM()) return false;
  const cls = document.body.classList;
  return (
    cls.contains("modal-open") ||
    cls.contains("bottom-sheet-open") ||
    cls.contains("voucher-modal-open") ||
    cls.contains("nat-modal-open") ||
    cls.contains("top-drawer-open") ||
    cls.contains("product-image-viewer-open")
  );
}

function createPageSnapshot(
  source: HTMLElement | null,
  pathname: string,
): PageSnapshot | null {
  if (!canUseDOM() || !source) return null;
  const clone = source.cloneNode(true) as HTMLElement;
  clone.setAttribute("aria-hidden", "true");
  clone.setAttribute("inert", "");
  clone.querySelectorAll("script").forEach((script) => script.remove());
  clone.querySelectorAll("video").forEach((video) => {
    video.removeAttribute("autoplay");
    video.setAttribute("muted", "");
  });

  return {
    node: clone,
    pathname,
    scrollY: window.scrollY || document.documentElement.scrollTop || 0,
  };
}

export function SwipeBackProvider({ children }: Props) {
  const router = useRouter();
  const pathname = usePathname();
  const currentPageRef = useRef<HTMLDivElement>(null);
  const previousLayerRef = useRef<HTMLDivElement>(null);
  const pendingSnapshotRef = useRef<PageSnapshot | null>(null);
  const previousSnapshotRef = useRef<PageSnapshot | null>(null);
  const currentPathRef = useRef(pathname ?? "/");
  const gestureRef = useRef<GestureState>({ ...EMPTY_GESTURE });
  const routeConfigRef = useRef(getSwipeBackRouteConfig(pathname));

  const [confirmOpen, setConfirmOpen] = useState(false);
  const [confirmTitle, setConfirmTitle] = useState("Keluar dari halaman ini?");
  const [confirmMessage, setConfirmMessage] = useState(
    "Data yang belum disimpan mungkin hilang.",
  );

  useEffect(() => {
    routeConfigRef.current = getSwipeBackRouteConfig(pathname);
  }, [pathname]);

  useEffect(() => {
    if (!pathname) return;
    const previousPath = currentPathRef.current;
    if (pathname === previousPath) return;

    if (pendingSnapshotRef.current) {
      previousSnapshotRef.current = pendingSnapshotRef.current;
      pendingSnapshotRef.current = null;
    }

    currentPathRef.current = pathname;
    resetGestureStyles();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pathname]);

  useEffect(() => {
    if (!canUseDOM()) return;

    function handleClick(event: MouseEvent) {
      const anchor = (event.target as HTMLElement | null)?.closest?.("a");
      if (!anchor || !(anchor instanceof HTMLAnchorElement)) return;
      if (event.button !== 0) return;
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      if (anchor.target && anchor.target !== "_self") return;
      if (anchor.hasAttribute("download")) return;
      if (anchor.getAttribute("rel")?.includes("external")) return;

      const href = anchor.getAttribute("href");
      if (!isInternalHref(href)) return;

      const targetUrl = new URL(href, window.location.origin);
      const nextPath = normalizePathname(targetUrl.pathname);
      const currentPath = normalizePathname(window.location.pathname);
      if (nextPath === currentPath) return;

      pendingSnapshotRef.current = createPageSnapshot(
        currentPageRef.current,
        currentPath,
      );
    }

    document.addEventListener("click", handleClick, true);
    return () => document.removeEventListener("click", handleClick, true);
  }, []);

  useEffect(() => {
    if (!canUseDOM()) return;
    const page = currentPageRef.current;
    if (!page) return;

    function onTouchStart(event: TouchEvent) {
      const routeConfig = routeConfigRef.current;
      if (!routeConfig.enableSwipeBack) return;
      if (window.history.length <= 1) return;
      if (!previousSnapshotRef.current) return;
      if (event.touches.length !== 1) return;
      if (isBodyOverlayOpen()) return;

      const touch = event.touches[0];
      if (touch.clientX > EDGE_SIZE) return;
      if (shouldIgnoreSwipe(event.target, touch.clientX)) return;

      gestureRef.current = {
        ...EMPTY_GESTURE,
        active: true,
        startX: touch.clientX,
        startY: touch.clientY,
        lastX: touch.clientX,
        lastT: event.timeStamp,
      };

      preparePreviousLayer();
    }

    function onTouchMove(event: TouchEvent) {
      const gesture = gestureRef.current;
      if (!gesture.active || gesture.committing) return;
      if (event.touches.length !== 1) return;

      const touch = event.touches[0];
      const deltaX = Math.max(0, touch.clientX - gesture.startX);
      const deltaY = Math.abs(touch.clientY - gesture.startY);

      if (!gesture.locked) {
        if (
          deltaY > VERTICAL_CANCEL_DISTANCE ||
          (deltaY > DIRECTION_LOCK_DISTANCE && deltaY > deltaX * 1.15)
        ) {
          cancelWithoutAnimation();
          return;
        }

        if (deltaX < DIRECTION_LOCK_DISTANCE || deltaX <= deltaY) {
          return;
        }

        gesture.locked = true;
        document.body.dataset.swipeBackGesture = "active";
        lockCurrentPage();
      }

      event.preventDefault();
      gesture.x = deltaX;
      gesture.lastX = touch.clientX;
      gesture.lastT = event.timeStamp;

      if (gesture.raf === null) {
        gesture.raf = window.requestAnimationFrame(() => {
          gesture.raf = null;
          updateGestureVisuals(gesture.x);
        });
      }
    }

    function onTouchEnd(event: TouchEvent) {
      const gesture = gestureRef.current;
      if (!gesture.active) return;
      if (gesture.raf !== null) {
        window.cancelAnimationFrame(gesture.raf);
        gesture.raf = null;
      }

      const touch = event.changedTouches[0];
      const x = Math.max(0, touch.clientX - gesture.startX);
      const elapsed = Math.max(1, event.timeStamp - gesture.lastT);
      const velocity = (touch.clientX - gesture.lastX) / elapsed;
      const width = window.innerWidth || 1;
      const shouldCommit =
        x > Math.max(MIN_COMMIT_DISTANCE, width * COMMIT_DISTANCE_RATIO) ||
        (x > MIN_COMMIT_DISTANCE && velocity > COMMIT_VELOCITY);

      if (!gesture.locked) {
        cancelWithoutAnimation();
        return;
      }

      if (!shouldCommit) {
        animateCancel(x);
        return;
      }

      const needsConfirm = document.body.dataset.swipeBackConfirm === "true";
      if (needsConfirm) {
        const customTitle = document.body.dataset.swipeBackConfirmTitle;
        const customMsg = document.body.dataset.swipeBackConfirmMessage;
        if (customTitle) setConfirmTitle(customTitle);
        if (customMsg) setConfirmMessage(customMsg);
        animateCancel(x, () => setConfirmOpen(true));
        return;
      }

      animateCommit(x);
    }

    function onTouchCancel() {
      const gesture = gestureRef.current;
      if (!gesture.active) return;
      if (gesture.locked) {
        animateCancel(gesture.x);
      } else {
        cancelWithoutAnimation();
      }
    }

    page.addEventListener("touchstart", onTouchStart, { passive: true });
    page.addEventListener("touchmove", onTouchMove, { passive: false });
    page.addEventListener("touchend", onTouchEnd, { passive: true });
    page.addEventListener("touchcancel", onTouchCancel, { passive: true });

    return () => {
      page.removeEventListener("touchstart", onTouchStart);
      page.removeEventListener("touchmove", onTouchMove);
      page.removeEventListener("touchend", onTouchEnd);
      page.removeEventListener("touchcancel", onTouchCancel);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function preparePreviousLayer() {
    const layer = previousLayerRef.current;
    const snapshot = previousSnapshotRef.current;
    if (!layer || !snapshot) return;

    const clone = snapshot.node.cloneNode(true) as HTMLElement;
    clone.style.transform = `translate3d(0, ${-snapshot.scrollY}px, 0)`;
    clone.style.pointerEvents = "none";
    clone.style.userSelect = "none";

    layer.replaceChildren(clone);
    layer.style.display = "block";
    layer.style.opacity = "0.72";
    layer.style.transform = "translate3d(-24px, 0, 0) scale(0.98)";
    layer.style.transition = "none";
    layer.style.willChange = "transform, opacity";
  }

  function lockCurrentPage() {
    const page = currentPageRef.current;
    if (!page) return;
    page.style.position = "relative";
    page.style.zIndex = "2";
    page.style.willChange = "transform";
    page.style.transition = "none";
    page.style.boxShadow = "-18px 0 36px rgba(15, 23, 42, 0.16)";
  }

  function updateGestureVisuals(x: number) {
    const page = currentPageRef.current;
    const layer = previousLayerRef.current;
    if (!page || !layer) return;

    const width = window.innerWidth || 1;
    const progress = Math.min(1, x / width);
    const previousOffset = -24 + 24 * progress;
    const previousScale = 0.98 + 0.02 * progress;
    const previousOpacity = 0.72 + 0.28 * progress;

    page.style.transform = `translate3d(${x}px, 0, 0)`;
    layer.style.transform = `translate3d(${previousOffset}px, 0, 0) scale(${previousScale})`;
    layer.style.opacity = String(previousOpacity);
  }

  function animateCancel(fromX: number, onDone?: () => void) {
    const page = currentPageRef.current;
    const layer = previousLayerRef.current;
    if (!page || !layer) {
      resetGestureStyles();
      onDone?.();
      return;
    }

    updateGestureVisuals(fromX);
    page.style.transition = `transform ${SNAP_BACK_MS}ms ${EASING}, box-shadow ${SNAP_BACK_MS}ms ${EASING}`;
    layer.style.transition = `transform ${SNAP_BACK_MS}ms ${EASING}, opacity ${SNAP_BACK_MS}ms ${EASING}`;

    runAfterTransition(page, SNAP_BACK_MS, () => {
      resetGestureStyles();
      onDone?.();
    });

    window.requestAnimationFrame(() => {
      page.style.transform = "translate3d(0, 0, 0)";
      page.style.boxShadow = "none";
      layer.style.transform = "translate3d(-24px, 0, 0) scale(0.98)";
      layer.style.opacity = "0";
    });
  }

  function animateCommit(fromX: number) {
    const gesture = gestureRef.current;
    const page = currentPageRef.current;
    const layer = previousLayerRef.current;
    if (!page || !layer) {
      performBack();
      return;
    }

    gesture.committing = true;
    const width = window.innerWidth || 1;

    updateGestureVisuals(fromX);
    document.documentElement.dataset.interactiveSwipeBack = "committing";
    page.style.transition = `transform ${COMMIT_MS}ms ${EASING}, box-shadow ${COMMIT_MS}ms ${EASING}`;
    layer.style.transition = `transform ${COMMIT_MS}ms ${EASING}, opacity ${COMMIT_MS}ms ${EASING}`;

    runAfterTransition(page, COMMIT_MS, () => {
      performBack();
      window.setTimeout(() => {
        if (gestureRef.current.committing) resetGestureStyles();
      }, 650);
    });

    window.requestAnimationFrame(() => {
      page.style.transform = `translate3d(${width}px, 0, 0)`;
      page.style.boxShadow = "-24px 0 44px rgba(15, 23, 42, 0.12)";
      layer.style.transform = "translate3d(0, 0, 0) scale(1)";
      layer.style.opacity = "1";
    });
  }

  function cancelWithoutAnimation() {
    resetGestureStyles();
  }

  function resetGestureStyles() {
    const gesture = gestureRef.current;
    if (gesture.raf !== null && canUseDOM()) {
      window.cancelAnimationFrame(gesture.raf);
    }
    gestureRef.current = { ...EMPTY_GESTURE };

    const page = currentPageRef.current;
    if (page) {
      page.style.position = "";
      page.style.zIndex = "";
      page.style.willChange = "";
      page.style.transition = "";
      page.style.transform = "";
      page.style.boxShadow = "";
    }

    const layer = previousLayerRef.current;
    if (layer) {
      layer.style.display = "none";
      layer.style.opacity = "";
      layer.style.transform = "";
      layer.style.transition = "";
      layer.style.willChange = "";
      layer.replaceChildren();
    }

    if (canUseDOM()) {
      delete document.body.dataset.swipeBackGesture;
      delete document.documentElement.dataset.interactiveSwipeBack;
    }
  }

  function performBack() {
    document.documentElement.dataset.navDirection = "pop";
    if (window.history.length > 1) {
      router.back();
    } else {
      router.push("/");
    }
  }

  function handleConfirm() {
    setConfirmOpen(false);
    performBack();
  }

  function handleCancel() {
    setConfirmOpen(false);
  }

  return (
    <>
      <div className="relative min-h-[100dvh] overflow-x-clip">
        <div
          ref={previousLayerRef}
          aria-hidden="true"
          className="pointer-events-none fixed inset-0 z-[1] hidden overflow-hidden bg-white"
        />
        <div ref={currentPageRef} className="relative z-[2] min-h-[100dvh]">
          {children}
        </div>
      </div>

      {confirmOpen &&
        canUseDOM() &&
        createPortal(
          <ExitConfirmModal
            title={confirmTitle}
            message={confirmMessage}
            onCancel={handleCancel}
            onConfirm={handleConfirm}
          />,
          document.body,
        )}
    </>
  );
}

function runAfterTransition(
  element: HTMLElement,
  durationMs: number,
  callback: () => void,
) {
  let done = false;
  const finish = () => {
    if (done) return;
    done = true;
    element.removeEventListener("transitionend", finish);
    window.clearTimeout(timeout);
    callback();
  };
  const timeout = window.setTimeout(finish, durationMs + 80);
  element.addEventListener("transitionend", finish);
}

function ExitConfirmModal({
  title,
  message,
  onCancel,
  onConfirm,
}: {
  title: string;
  message: string;
  onCancel: () => void;
  onConfirm: () => void;
}) {
  useEffect(() => {
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onCancel();
    }
    document.addEventListener("keydown", onKey);
    return () => {
      document.body.style.overflow = prev;
      document.removeEventListener("keydown", onKey);
    };
  }, [onCancel]);

  return (
    <div
      className="fixed inset-0 z-[9999] flex items-center justify-center px-4"
      role="dialog"
      aria-modal="true"
    >
      <button
        type="button"
        aria-label="Tutup"
        onClick={onCancel}
        className="absolute inset-0 animate-in fade-in bg-black/30 backdrop-blur-sm duration-200"
      />
      <div className="relative w-full max-w-sm animate-in fade-in zoom-in-95 rounded-2xl bg-white p-5 shadow-xl duration-200">
        <h3 className="text-center text-lg font-bold text-slate-900">{title}</h3>
        <p className="mt-2 text-center text-sm leading-6 text-slate-500">
          {message}
        </p>
        <div className="mt-6 grid grid-cols-2 gap-3">
          <button
            type="button"
            onClick={onCancel}
            className="h-11 rounded-xl border border-slate-200 bg-white text-sm font-semibold text-slate-700 transition active:scale-[0.98]"
          >
            Tetap di Halaman
          </button>
          <button
            type="button"
            onClick={onConfirm}
            className="h-11 rounded-xl bg-red-500 text-sm font-semibold text-white transition active:scale-[0.98] active:bg-red-600"
          >
            Keluar
          </button>
        </div>
      </div>
    </div>
  );
}

export default SwipeBackProvider;
