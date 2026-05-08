import { z } from "zod";

export const cartItemSchema = z.object({
  productId: z.string(),
  variantId: z.string().nullable().optional(),
  variantLabel: z.string().nullable().optional(),
  name: z.string(),
  price: z.number().int().nonnegative(),
  quantity: z.number().int().positive(),
  weightGram: z.number().int().positive().default(500),
});

export const createOrderSchema = z.object({
  customerName: z.string().min(2),
  customerPhone: z.string().min(8),
  customerEmail: z.string().email().optional().or(z.literal("")),
  shippingAddress: z.string().min(10),
  shippingCity: z.string().optional(),
  shippingPostalCode: z.string().optional(),
  shippingLatitude: z.number().nullable().optional(),
  shippingLongitude: z.number().nullable().optional(),
  shippingPinpointAddress: z.string().nullable().optional(),
  courierCode: z.string().optional(),
  courierService: z.string().optional(),
  shippingCost: z.number().int().nonnegative().default(0),
  voucherCode: z.string().optional(),
  notes: z.string().optional(),
  paymentProvider: z.enum(["MANUAL", "MIDTRANS", "XENDIT"]).default("MANUAL"),
  // Untuk TT manual: bank tujuan transfer
  manualBank: z.enum(["BCA_NATASHA", "BCA_NL_PET"]).optional(),
  items: z.array(cartItemSchema).min(1),
});
