// Slim API surface — scope sekarang hanya OTP register & OTP login.
// Fungsi-fungsi order (sendOrderCreated, sendPaymentConfirmed, dst.) sudah
// dihapus; notifikasi order pakai email + push notification.

export type WhatsAppSendResult = {
  ok: boolean;
  skipped?: boolean;
  retryScheduled?: boolean;
  reason?: string;
  error?: string;
  phone?: string;
  message?: string;
  response?: unknown;
};

export function formatWaPhone(value: unknown): string;
export function sendWA(phoneValue: unknown, message: string): Promise<WhatsAppSendResult>;
export function sendWAFireAndForget(phoneValue: unknown, message: string): void;
export function sendCustomMessage(phone: unknown, message: string): Promise<WhatsAppSendResult>;

export const WhatsAppService: {
  formatWaPhone: typeof formatWaPhone;
  sendWA: typeof sendWA;
  sendWAFireAndForget: typeof sendWAFireAndForget;
  sendCustomMessage: typeof sendCustomMessage;
};
