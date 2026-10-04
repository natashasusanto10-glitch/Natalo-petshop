"use client";

import { useEffect, useLayoutEffect, useRef, type ReactNode } from "react";
import { usePathname } from "next/navigation";

export function adminMotionAllowed() {
  return !window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}

export function AdminContentMotion({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!adminMotionAllowed()) return;
    const animation = ref.current?.animate([{ opacity: 0 }, { opacity: 1 }], {
      duration: 180,
      easing: "cubic-bezier(.2,.8,.2,1)",
    });
    return () => animation?.cancel();
  }, [pathname]);
  return (
    <div ref={ref} className="admin-content">
      {children}
    </div>
  );
}

/** Keyed DOM positions, never array indices, preserve continuity after reorder. */
export function LayoutMotion({
  children,
  revision,
  className = "",
}: {
  children: ReactNode;
  revision: unknown;
  className?: string;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const positions = useRef(new Map<string, DOMRect>());
  useLayoutEffect(() => {
    const items = Array.from(
      ref.current?.querySelectorAll<HTMLElement>("[data-motion-key]") ?? []
    );
    // Read the current animation offset before cancelling it. The saved rects
    // are layout destinations; adding this offset preserves the visible position
    // when a second reorder happens before the first animation has finished.
    const offsets = new Map(
      items.map((el) => {
        const transform = getComputedStyle(el).transform;
        const matrix =
          transform === "none" ? null : new DOMMatrixReadOnly(transform);
        return [
          el.dataset.motionKey!,
          { x: matrix?.m41 ?? 0, y: matrix?.m42 ?? 0 },
        ];
      })
    );
    items.forEach((el) =>
      el.getAnimations().forEach((animation) => animation.cancel())
    );
    const next = new Map(
      items.map((el) => [el.dataset.motionKey!, el.getBoundingClientRect()])
    );
    if (adminMotionAllowed())
      items.forEach((el) => {
        const key = el.dataset.motionKey!;
        const old = positions.current.get(key),
          now = next.get(key)!;
        const offset = offsets.get(key)!;
        const dx = old ? old.left + offset.x - now.left : 0;
        const dy = old ? old.top + offset.y - now.top : 0;
        if (dx || dy)
          el.animate(
            [
              { transform: `translate(${dx}px,${dy}px)` },
              { transform: "translate(0,0)" },
            ],
            { duration: 220, easing: "cubic-bezier(.2,.8,.2,1)" }
          );
      });
    positions.current = next;
  }, [revision]);
  return (
    <div ref={ref} className={className}>
      {children}
    </div>
  );
}
