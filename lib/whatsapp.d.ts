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

export type WhatsAppOrder = Record<string, unknown> & {
  customerName?: string;
  customer_name?: string;
  customerPhone?: string;
  customer_phone?: string;
  orderNumber?: string;
  order_number?: string;
  order_id?: string;
  total?: number;
  grandTotal?: number;
  total_amount?: number;
  paymentUrl?: string | null;
  payment_url?: string | null;
  courierCode?: string | null;
  courierService?: string | null;
  courier?: string | null;
  trackingNumber?: string | null;
  tracking_number?: string | null;
  trackingUrl?: string | null;
  tracking_url?: string | null;
  cancelReason?: string | null;
  cancel_reason?: string | null;
  refundAmount?: number | null;
  refund_amount?: number | null;
  reviewUrl?: string | null;
  review_url?: string | null;
};

export function formatWaPhone(value: unknown): string;
export function sendWA(phoneValue: unknown, message: string): Promise<WhatsAppSendResult>;
export function sendWAFireAndForget(phoneValue: unknown, message: string): void;
export function buildOrderMessage(type: string, order: WhatsAppOrder): string;
export function buildAdminOrderCreatedMessage(order: WhatsAppOrder): string;
export function sendCustomMessage(phone: unknown, message: string): Promise<WhatsAppSendResult>;
export function sendOrderCreated(order: WhatsAppOrder): Promise<WhatsAppSendResult>;
export function sendAdminOrderCreated(order: WhatsAppOrder): Promise<WhatsAppSendResult>;
export function sendPaymentConfirmed(order: WhatsAppOrder): Promise<WhatsAppSendResult>;
export function sendOrderShipped(order: WhatsAppOrder): Promise<WhatsAppSendResult>;
export function sendOrderCompleted(order: WhatsAppOrder): Promise<WhatsAppSendResult>;
export function sendOrderCancelled(order: WhatsAppOrder): Promise<WhatsAppSendResult>;

export const WhatsAppService: {
  formatWaPhone: typeof formatWaPhone;
  sendWA: typeof sendWA;
  sendWAFireAndForget: typeof sendWAFireAndForget;
  buildOrderMessage: typeof buildOrderMessage;
  buildAdminOrderCreatedMessage: typeof buildAdminOrderCreatedMessage;
  sendCustomMessage: typeof sendCustomMessage;
  sendOrderCreated: typeof sendOrderCreated;
  sendAdminOrderCreated: typeof sendAdminOrderCreated;
  sendPaymentConfirmed: typeof sendPaymentConfirmed;
  sendOrderShipped: typeof sendOrderShipped;
  sendOrderCompleted: typeof sendOrderCompleted;
  sendOrderCancelled: typeof sendOrderCancelled;
};
