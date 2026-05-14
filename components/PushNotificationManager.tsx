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

    async function registerForLoggedInUser() {
      try {
        const res = await fetch("/api/auth/me", {
          cache: "no-store",
          credentials: "include",
        });
        const member = (await res.json()) as MemberProfile;
        if (cancelled || !member.id) return;

        const key = promptKey(member.id);
        const hasPrompted = localStorage.getItem(key) === "1";
        const result = await registerPushForCurrentUser({
          prompt: !hasPrompted,
        });

        if (!cancelled && result !== "unsupported") {
          localStorage.setItem(key, "1");
        }
      } catch {
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
