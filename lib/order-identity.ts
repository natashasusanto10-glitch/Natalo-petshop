export type CheckoutIdentityInput = {
  customerName: string;
  customerPhone: string;
  customerEmail?: string | null;
};

export type OrderIdentityUser = {
  id: string;
};

export class InvalidCustomerSessionError extends Error {
  constructor() {
    super("Session customer tidak valid.");
  }
}

export async function resolveOrderIdentity({
  sessionUserId,
  checkout,
  findSessionUser,
  findGuestUser,
  createGuestUser,
}: {
  sessionUserId: string | null;
  checkout: CheckoutIdentityInput;
  findSessionUser(userId: string): Promise<OrderIdentityUser | null>;
  findGuestUser(input: {
    phone: string;
    email: string | null;
  }): Promise<OrderIdentityUser | null>;
  createGuestUser(input: CheckoutIdentityInput): Promise<OrderIdentityUser>;
}) {
  if (sessionUserId) {
    const sessionUser = await findSessionUser(sessionUserId);
    if (!sessionUser) throw new InvalidCustomerSessionError();

    return {
      effectiveUserId: sessionUser.id,
      source: "session" as const,
    };
  }

  const email = checkout.customerEmail || null;
  const guestUser =
    (await findGuestUser({ phone: checkout.customerPhone, email })) ||
    (await createGuestUser({ ...checkout, customerEmail: email }));

  return {
    effectiveUserId: guestUser.id,
    source: "guest" as const,
  };
}
