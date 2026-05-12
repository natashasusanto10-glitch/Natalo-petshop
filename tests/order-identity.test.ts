import assert from "node:assert/strict";
import test from "node:test";
import { InvalidCustomerSessionError, resolveOrderIdentity } from "@/lib/order-identity";

const checkout = {
  customerName: "User A Checkout Contact",
  customerPhone: "081222222222",
  customerEmail: "user-b@example.com",
};

test("logged-in checkout binds order identity to the session user, not checkout contact", async () => {
  let lookedUpGuest = false;
  let createdGuest = false;

  const result = await resolveOrderIdentity({
    sessionUserId: "user-a",
    checkout,
    async findSessionUser(userId) {
      return { id: userId };
    },
    async findGuestUser() {
      lookedUpGuest = true;
      return { id: "user-b" };
    },
    async createGuestUser() {
      createdGuest = true;
      return { id: "new-user" };
    },
  });

  assert.equal(result.effectiveUserId, "user-a");
  assert.equal(result.source, "session");
  assert.equal(lookedUpGuest, false);
  assert.equal(createdGuest, false);
});

test("invalid logged-in session is rejected instead of falling back to checkout contact", async () => {
  await assert.rejects(
    resolveOrderIdentity({
      sessionUserId: "missing-user",
      checkout,
      async findSessionUser() {
        return null;
      },
      async findGuestUser() {
        return { id: "user-b" };
      },
      async createGuestUser() {
        return { id: "new-user" };
      },
    }),
    InvalidCustomerSessionError,
  );
});

test("guest checkout keeps existing lookup/create ownership flow", async () => {
  let createdGuest = false;

  const result = await resolveOrderIdentity({
    sessionUserId: null,
    checkout,
    async findSessionUser() {
      throw new Error("session lookup should not run for guest checkout");
    },
    async findGuestUser({ phone, email }) {
      assert.equal(phone, checkout.customerPhone);
      assert.equal(email, checkout.customerEmail);
      return null;
    },
    async createGuestUser(input) {
      createdGuest = true;
      assert.equal(input.customerPhone, checkout.customerPhone);
      assert.equal(input.customerEmail, checkout.customerEmail);
      return { id: "guest-user" };
    },
  });

  assert.equal(result.effectiveUserId, "guest-user");
  assert.equal(result.source, "guest");
  assert.equal(createdGuest, true);
});
