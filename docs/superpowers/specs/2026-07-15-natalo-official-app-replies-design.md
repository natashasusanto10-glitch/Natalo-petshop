# Natalo Official Replies from the Customer App

## Goal

Verify and harden the existing behavior where an admin using the normal Natalo
mobile application can reply to feed comments with the single public identity
**Natalo Official**. The core flow already exists in the member-facing comment
endpoint and must not be rebuilt as a separate staff inbox.

## Product decision

There is no separate staff comment inbox or dedicated reply composer. An admin
signs in to the Natalo application, opens Feed, and uses the ordinary
comment/reply controls. The current backend derives the public identity from
`session.role === "ADMIN"`; Flutter never sends or chooses an official flag.

Web Admin remains the place for post and comment moderation, filtering, and
audit review. It is not the primary channel for replying to customers.

## Public behavior

- A customer comment and an official reply remain in the same existing
  one-level thread.
- A reply sent by an authorized staff account displays the author as **Natalo
  Official**, using the official avatar and verified/official treatment already
  supported by `isAdminOfficial`.
- The staff member's personal name and account are never exposed in the public
  comment payload.
- Customers can like an official reply and reply to it through existing
  controls.
- The owner of the target comment receives the existing reply notification,
  with Natalo Official as its public actor.

## Current authorization and hardening

- The current comment create endpoint resolves authorization from the
  authenticated session and writes `isAdminOfficial: true` when the session
  role is `ADMIN`.
- The current response masks an admin author with brand display name/photo, so
  the staff member's personal identity is not exposed publicly.
- The persisted `authorId` remains the logged-in staff account and provides an
  internal actor trail. A dedicated `canReplyOfficial` permission may replace
  the broad ADMIN check later if staff roles become more granular.
- Requests from a customer, or staff without the permission, cannot set the
  public official identity or `isAdminOfficial` through request JSON.
- Add regression tests so a request cannot forge the official flag and an
  admin response continues to hide the staff display identity.

## Existing API and client flow

1. Flutter sends the current comment request exactly as today: content and an
   optional `parentCommentId`.
2. The API validates authentication, post/comment visibility, rate limits, and
   thread depth.
3. The API checks the admin session role, marks the record official, and keeps
   the staff `authorId` for internal traceability.
4. The API serializes the new `FeedComment` using the existing
   `isAdminOfficial` field.
5. Existing optimistic UI inserts the reply into the shared comment session.
   Existing sync/refetch paths reconcile other surfaces and devices.
6. Existing reply notification delivery uses the public official identity.

## Failure handling to verify

- Customer requests remain ordinary comments and cannot elevate themselves.
- Admin session expiry returns 401 and leaves the draft intact in Flutter.
- Normal network failures retain current optimistic rollback behavior.
- Deleted/hidden parent comments retain existing server validation and cannot
  receive an official orphan reply.

## Verification

- Backend tests: customer cannot forge official identity; authorized admin
  creates an official reply; response masks staff name/photo; existing author
  ID remains available for internal audit.
- API tests: reply notification identifies Natalo Official and respects current
  self-notification protections.
- Flutter tests: official reply renders with the expected author and badge;
  normal user comments retain their current rendering; failure keeps the draft.
- Manual E2E: one customer and one authorized staff login in the same Natalo
  app, including reply, like, notification, reload, and audit review.
