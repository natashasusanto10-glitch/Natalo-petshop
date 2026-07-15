export const ORDER_CONTEXT_SCHEMA_VERSION = 1 as const;

export type OrderContextV1 = {
  schemaVersion: typeof ORDER_CONTEXT_SCHEMA_VERSION;
  order: {
    orderNumber: string;
    status: string;
    paymentStatus: string;
    paymentProofStatus: string;
    total: number;
    itemCount: number;
    hasPaymentProof: boolean;
    proofVersion: number;
    createdAt: string;
  };
};

export type OrderContextSource = {
  orderNumber: string;
  status: string;
  paymentStatus: string;
  paymentProofStatus: string;
  total: number;
  itemCount: number;
  paymentProofUrl: string | null;
  paymentProofVersion: number;
  createdAt: Date;
};

export function buildOrderContextV1(source: OrderContextSource): OrderContextV1 {
  return {
    schemaVersion: ORDER_CONTEXT_SCHEMA_VERSION,
    order: {
      orderNumber: source.orderNumber,
      status: source.status,
      paymentStatus: source.paymentStatus,
      paymentProofStatus: source.paymentProofStatus,
      total: source.total,
      itemCount: source.itemCount,
      hasPaymentProof: Boolean(source.paymentProofUrl),
      proofVersion: source.paymentProofVersion,
      createdAt: source.createdAt.toISOString(),
    },
  };
}

export function isOrderContextV1(value: unknown): value is OrderContextV1 {
  if (!value || typeof value !== "object") return false;
  const root = value as Record<string, unknown>;
  if (root.schemaVersion !== ORDER_CONTEXT_SCHEMA_VERSION) return false;
  if (!root.order || typeof root.order !== "object") return false;
  const order = root.order as Record<string, unknown>;
  return (
    typeof order.orderNumber === "string" &&
    order.orderNumber.length > 0 &&
    typeof order.status === "string" &&
    typeof order.paymentStatus === "string" &&
    typeof order.paymentProofStatus === "string" &&
    typeof order.total === "number" &&
    Number.isSafeInteger(order.total) &&
    typeof order.itemCount === "number" &&
    Number.isSafeInteger(order.itemCount) &&
    typeof order.hasPaymentProof === "boolean" &&
    typeof order.proofVersion === "number" &&
    Number.isSafeInteger(order.proofVersion) &&
    typeof order.createdAt === "string"
  );
}

export function deterministicOrderMessageId(orderId: string): string {
  return `order_context_${orderId}`;
}
