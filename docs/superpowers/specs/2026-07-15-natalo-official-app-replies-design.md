# Natalo Official Replies from the Customer App

## Goal

Allow authorized Natalo staff to use the existing Natalo mobile application
and reply to feed comments with the single public identity **Natalo Official**.
The customer-facing feed, comment sheet, reply thread, likes, and notifications
remain the existing shared experience.

## Product decision

There is no separate staff comment inbox or dedicated reply composer. An
authorized staff member signs in to the Natalo application, opens Feed, and
uses the ordinary comment/reply controls. The backend derives the public
identity; Flutter never sends or chooses an official flag.

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

## Authorization and data ownership

- Introduce/require a server-side permission such as `canReplyOfficial` for
  staff who may speak for Natalo.
- The comment create endpoint resolves authorization from the authenticated
  session and selects the configured Natalo Official account server-side.
- The endpoint writes `isAdminOfficial: true` and the official account as the
  public author only when that permission is present.
- Persist the staff actor separately for internal audit (`actorStaffId`, or an
  equivalent append-only audit record), including post ID, target comment ID,
  created comment ID, and timestamp.
- Requests from a customer, or staff without the permission, cannot set the
  public official identity or `isAdminOfficial` through request JSON.
- If no active official account can be resolved, fail with a clear 409/503-style
  application error. Never fall back silently to the staff member's identity.

## API and client flow

1. Flutter sends the current comment request exactly as today: content and an
   optional `parentCommentId`.
2. The API validates authentication, post/comment visibility, rate limits, and
   thread depth.
3. The API checks official-reply permission. If permitted, it substitutes the
   configured public author, marks the record official, and writes audit data.
4. The API serializes the new `FeedComment` using the existing
   `isAdminOfficial` field.
5. Existing optimistic UI inserts the reply into the shared comment session.
   Existing sync/refetch paths reconcile other surfaces and devices.
6. Existing reply notification delivery uses the public official identity.

## Failure handling

- Permission failure returns 403 and leaves the draft intact in Flutter.
- Official-account configuration failure returns an explicit retryable error;
  no comment is created.
- Normal network failures retain current optimistic rollback behavior.
- Deleted/hidden parent comments retain existing server validation and cannot
  receive an official orphan reply.

## Verification

- Backend tests: customer cannot forge official identity; unauthorized staff is
  rejected; authorized staff creates an official reply; official account outage
  creates no comment; audit fields are written.
- API tests: reply notification identifies Natalo Official and respects current
  self-notification protections.
- Flutter tests: official reply renders with the expected author and badge;
  normal user comments retain their current rendering; failure keeps the draft.
- Manual E2E: one customer and one authorized staff login in the same Natalo
  app, including reply, like, notification, reload, and audit review.
