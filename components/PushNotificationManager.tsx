"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import {
  getPushNavigationTarget,
  registerPushForCurrentUser,
} from "@/lib/push-client";

type MemberProfile = {
  id?: string;
  name?: string;
};

function promptKey(userId: string) {
  return `natalo-push-auto-prompted:${userId}`;
}

export function PushNotificationManager() {
  const router = useRouter();

  useEffect(() => {
    let cancelled = false;

    function trace(event: string, data?: Record<string, unknown>) {
      // Fire-and-forget diagnostic — visible di Vercel Logs `[push-trace]`
      // dengan event name "manager-*" untuk distinguish dari register-* logs.
      fetch("/api/debug/push-trace", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        credentials: "include",
        body: JSON.stringify({ event: `manager-${event}`, ...(data ?? {}) }),
      }).catch(() => {});
    }

    async function registerForLoggedInUser() {
      trace("fire-start");
      try {
        const res = await fetch("/api/auth/me", {
          cache: "no-store",
          credentials: "include",
        });
        const member = (await res.json()) as MemberProfile;
        if (cancelled) return;
        if (!member.id) {
          trace("no-member-id", { memberKeys: Object.keys(member ?? {}) });
          return;
        }
        trace("member-loaded", { hasName: !!member.name });

        const key = promptKey(member.id);
        const hasPrompted = localStorage.getItem(key) === "1";
        trace("calling-register", { hasPrompted });
        const result = await registerPushForCurrentUser({
          prompt: !hasPrompted,
        });
        trace("register-returned", { result });

        if (!cancelled && result !== "unsupported") {
          localStorage.setItem(key, "1");
        }
      } catch (err) {
        trace("fire-error", { error: String(err) });
        // Push registration should never block app boot/login.
      }
    }

    void registerForLoggedInUser();
    window.addEventListener("auth-updated", registerForLoggedInUser);
    window.addEventListener("app-refresh", registerForLoggedInUser);

    return () => {
      cancelled = true;
      window.removeEventListener("auth-updated", registerForLoggedInUser);
      window.removeEventListener("app-refresh", registerForLoggedInUser);
    };
  }, []);

  useEffect(() => {
    let cancelled = false;
    let remove: (() => void) | null = null;

    (async () => {
      try {
        const { Capacitor } = await import("@capacitor/core");
        if (!Capacitor.isNativePlatform()) return;

        const { PushNotifications } = await import(
          "@capacitor/push-notifications"
        );
        const handle = await PushNotifications.addListener(
          "pushNotificationActionPerformed",
          (event) => {
            const target = getPushNavigationTarget(event.notification.data);
            if (!target || cancelled) return;
            router.push(target);
          }
        );

        if (cancelled) {
          await handle.remove();
          return;
        }

        remove = () => {
          void handle.remove();
        };
      } catch {
        // Browser/PWA uses the service worker notificationclick handler.
      }
    })();

    return () => {
      cancelled = true;
      remove?.();
    };
  }, [router]);

  return null;
}
