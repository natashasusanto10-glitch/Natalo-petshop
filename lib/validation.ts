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
  orderType: z.enum(["DELIVERY", "SELF_PICKUP"]).default("DELIVERY"),
  shippingMethod: z.enum(["DELIVERY", "SELF_PICKUP"]).default("DELIVERY"),
  shippingAddress: z.string().optional().default(""),
  shippingCity: z.string().optional(),
  shippingPostalCode: z.string().optional(),
  shippingLatitude: z.number().nullable().optional(),
  shippingLongitude: z.number().nullable().optional(),
  shippingPinpointAddress: z.string().nullable().optional(),
  shippingAreaId: z.string().optional().default(""),
  shippingAreaLabel: z.string().optional(),
  shippingProvinceName: z.string().optional(),
  shippingDistrictName: z.string().optional(),
  courierCode: z.string().optional(),
  courierService: z.string().optional(),
  shippingCost: z.number().int().nonnegative().default(0),
  // Legacy customer voucher field.
  voucherCode: z.string().optional(),
  // 4 voucher slots: product discount, free shipping, loyalty claim, and
  // seller/admin manual-private code.
  productVoucherCode: z.string().optional(),
  shippingVoucherCode: z.string().optional(),
  loyaltyVoucherCode: z.string().optional(),
  manualVoucherCode: z.string().optional(),
  notes: z.string().optional(),
  paymentProvider: z.enum(["MANUAL", "MIDTRANS"]).default("MANUAL"),
  // Untuk TT manual: bank tujuan transfer
  manualBank: z.enum(["BCA_NATASHA", "BCA_NL_PET"]).optional(),
  items: z.array(cartItemSchema).min(1),
}).superRefine((input, ctx) => {
  if (input.orderType === "SELF_PICKUP") return;

  if (input.shippingAddress.trim().length < 10) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["shippingAddress"],
      message: "Alamat pengiriman wajib diisi.",
    });
  }

  if (!input.shippingAreaId.trim()) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["shippingAreaId"],
      message: "Area pengiriman wajib dipilih.",
    });
  }
});
