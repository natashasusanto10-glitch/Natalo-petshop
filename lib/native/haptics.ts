"use client";

import { Haptics, ImpactStyle, NotificationType } from "@capacitor/haptics";

// Native UIImpactFeedbackGenerator (iOS) / VibratorManager (Android).
// Plugin sudah handle platform detection — call ini di web jadi no-op via
// try/catch, jadi aman dipanggil dari mana aja tanpa cek Capacitor.isNativePlatform().

export async function hapticTap() {
  try {
    await Haptics.impact({ style: ImpactStyle.Light });
  } catch {}
}

export async function hapticMedium() {
  try {
    await Haptics.impact({ style: ImpactStyle.Medium });
  } catch {}
}

export async function hapticHeavy() {
  try {
    await Haptics.impact({ style: ImpactStyle.Heavy });
  } catch {}
}

export async function hapticSuccess() {
  try {
    await Haptics.notification({ type: NotificationType.Success });
  } catch {}
}

export async function hapticWarning() {
  try {
    await Haptics.notification({ type: NotificationType.Warning });
  } catch {}
}

export async function hapticError() {
  try {
    await Haptics.notification({ type: NotificationType.Error });
  } catch {}
}
