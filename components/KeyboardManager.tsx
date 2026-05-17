"use client";

import { useEffect } from "react";

const KEYBOARD_THRESHOLD_PX = 80;
const TEXT_INPUT_SELECTOR =
  "input:not([type='hidden']):not([readonly]):not([disabled]), textarea:not([readonly]):not([disabled]), select:not([disabled]), [contenteditable='true'], [contenteditable='']";
const SELF_MANAGED_KEYBOARD_SELECTOR =
  ".feed-comment-sheet, .feed-comment-composer, .voucher-sheet";

function getFocusedTextInput() {
  const active = document.activeElement;
  if (!(active instanceof HTMLElement)) return null;
  if (!active.matches(TEXT_INPUT_SELECTOR)) return null;
  return active;
}

/**
 * Keyboard manager untuk shell native. Feed/Reels comment sheet mengatur
 * keyboard inset sendiri, tetapi WebView scroll harus tetap aktif untuk
 * halaman normal seperti Produk, Akun, Cart, dan Checkout.
 */
export function KeyboardManager() {
  useEffect(() => {
    if (typeof window === "undefined") return;

    const root = document.documentElement;
    const body = document.body;
    const visualViewport = window.visualViewport;
    const isTouchLike =
      window.matchMedia?.("(pointer: coarse)")?.matches ||
      navigator.maxTouchPoints > 0;
    let cancelled = false;
    let pluginKeyboardHeight = 0;
    let baselineHeight = Math.max(window.innerHeight, visualViewport?.height ?? 0);
    let scrollTimerA = 0;
    let scrollTimerB = 0;
    let removeKeyboardListeners: (() => void) | null = null;

    function clearScrollTimers() {
      if (scrollTimerA) window.clearTimeout(scrollTimerA);
      if (scrollTimerB) window.clearTimeout(scrollTimerB);
      scrollTimerA = 0;
      scrollTimerB = 0;
    }

    function setKeyboardInset(height: number) {
      if (cancelled) return;

      const keyboardHeight = height > KEYBOARD_THRESHOLD_PX ? Math.round(height) : 0;
      root.style.setProperty("--nat-app-keyboard-inset", `${keyboardHeight}px`);
      body.classList.toggle("nat-keyboard-open", keyboardHeight > 0);
      root.toggleAttribute("data-nat-keyboard-open", keyboardHeight > 0);

      if (keyboardHeight > 0) {
        scheduleFocusedInputIntoView();
      }
    }

    function estimateViewportKeyboardInset() {
      const viewportHeight = visualViewport?.height ?? window.innerHeight;
      const viewportOffsetTop = visualViewport?.offsetTop ?? 0;
      baselineHeight = Math.max(baselineHeight, window.innerHeight, viewportHeight);
      const overlayInset = visualViewport
        ? Math.max(0, window.innerHeight - viewportHeight - viewportOffsetTop)
        : 0;
      const viewportLoss = Math.max(0, baselineHeight - viewportHeight);
      return Math.max(overlayInset, viewportLoss);
    }

    function updateViewportKeyboardInset() {
      if (!isTouchLike) {
        setKeyboardInset(0);
        return;
      }
      if (pluginKeyboardHeight > KEYBOARD_THRESHOLD_PX) return;
      setKeyboardInset(estimateViewportKeyboardInset());
    }

    function scheduleFocusedInputIntoView() {
      clearScrollTimers();

      const scrollFocusedInput = () => {
        const focused = getFocusedTextInput();
        if (!focused || focused.closest(SELF_MANAGED_KEYBOARD_SELECTOR)) return;
        focused.scrollIntoView({
          behavior: "smooth",
          block: "center",
          inline: "nearest",
        });
      };

      scrollTimerA = window.setTimeout(scrollFocusedInput, 90);
      scrollTimerB = window.setTimeout(scrollFocusedInput, 320);
    }

    function handleFocusIn() {
      if (!isTouchLike && pluginKeyboardHeight <= KEYBOARD_THRESHOLD_PX) return;
      if (
        pluginKeyboardHeight > KEYBOARD_THRESHOLD_PX ||
        estimateViewportKeyboardInset() > KEYBOARD_THRESHOLD_PX
      ) {
        scheduleFocusedInputIntoView();
      }
    }

    updateViewportKeyboardInset();
    visualViewport?.addEventListener("resize", updateViewportKeyboardInset);
    visualViewport?.addEventListener("scroll", updateViewportKeyboardInset);
    window.addEventListener("resize", updateViewportKeyboardInset);
    document.addEventListener("focusin", handleFocusIn);

    (async () => {
      try {
        const [{ Capacitor }, { Keyboard, KeyboardResize }] = await Promise.all([
          import("@capacitor/core"),
          import("@capacitor/keyboard"),
        ]);

        if (Capacitor.getPlatform() !== "ios") return;

        await Keyboard.setResizeMode({ mode: KeyboardResize.None });
        await Keyboard.setScroll({ isDisabled: false });

        const willShow = await Keyboard.addListener("keyboardWillShow", (info) => {
          pluginKeyboardHeight = Math.max(0, Math.round(info.keyboardHeight));
          setKeyboardInset(pluginKeyboardHeight);
        });
        const didShow = await Keyboard.addListener("keyboardDidShow", (info) => {
          pluginKeyboardHeight = Math.max(0, Math.round(info.keyboardHeight));
          setKeyboardInset(pluginKeyboardHeight);
        });
        const willHide = await Keyboard.addListener("keyboardWillHide", () => {
          pluginKeyboardHeight = 0;
          setKeyboardInset(0);
        });
        const didHide = await Keyboard.addListener("keyboardDidHide", () => {
          pluginKeyboardHeight = 0;
          setKeyboardInset(0);
        });
        removeKeyboardListeners = () => {
          void willShow.remove();
          void didShow.remove();
          void willHide.remove();
          void didHide.remove();
        };

        if (process.env.NODE_ENV !== "production") {
          // Membantu validasi di TestFlight/devtools tanpa mengubah UX.
          console.log("Keyboard resize mode:", await Keyboard.getResizeMode());
        }
      } catch {
        // Web / non-Capacitor — silent no-op.
      }
    })();

    return () => {
      cancelled = true;
      visualViewport?.removeEventListener("resize", updateViewportKeyboardInset);
      visualViewport?.removeEventListener("scroll", updateViewportKeyboardInset);
      window.removeEventListener("resize", updateViewportKeyboardInset);
      document.removeEventListener("focusin", handleFocusIn);
      removeKeyboardListeners?.();
      clearScrollTimers();
      root.style.removeProperty("--nat-app-keyboard-inset");
      root.removeAttribute("data-nat-keyboard-open");
      body.classList.remove("nat-keyboard-open");
    };
  }, []);

  return null;
}
