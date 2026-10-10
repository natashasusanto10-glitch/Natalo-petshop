# Variant image delivery review — 10 October 2026

## Observed evidence

The user still sees the explicit upload-success/image-load-failure message. A read-only UploadThing query found the latest product uploads TUNA.jpg (225,931 bytes) and TUNA CHICKEN.jpg (188,750 bytes) in Uploaded state. Their public CDN URLs returned HTTP 206 and image/jpeg on range reads from the investigation environment. Full GETs returned HTTP 200, matching object sizes and JPEG metadata of 1024×1024; elapsed times here were 639 ms and 406 ms. These are diagnostic measurements from this environment, not measurements of the user's browser. This confirms those objects exist and the CDN can serve them here. It does not identify the user's browser failure mechanism (network, DNS, extensions, regional availability, or another client condition). No user browser was connected. Production upload log queries returned no matching records.

## Change

- Upload completion now depends only on the storage-confirmed HTTPS URL. The blocking image verification loop and “Memeriksa foto” phase are removed from both direct upload and crop save.
- Admin thumbnails first use the authenticated same-origin image route; if that fails, they try the original CDN URL. A display error offers “Muat ulang foto” and never re-uploads the saved object or prevents product saving.
- The fallback reads only public /f/ keys on the exact UploadThing app subdomain derived from the configured token. It rejects signed/query URLs, arbitrary hosts, ports, credentials, hashes, and redirects.
- Server reads are bounded to 10 seconds and 2 MB including streamed bytes. MIME and image signatures are validated before responding. Non-image responses and upstream failures return errors, never a fake success thumbnail.
- Only ADMIN sessions can access the route; responses are private-cacheable and nosniff. The server read deadline is 10 seconds, within a 20 second function budget. No upstream credentials, cookies or tokens are forwarded to the CDN or returned to the client.
- Product state keeps the original canonical CDN URL; only admin preview uses the fallback URL. This prevents persisting an admin-only link into the Flutter or customer catalog.
- Existing thumbnails use the same loading path. The crop editor can use that preview without requesting the CDN directly from the browser.
- Failed upload messages use a short inline status with Retry and Details. The complete message and Choose another photo action move into a dialog so the 80 pixel image column no longer becomes a tall text block.
- Local thumbnails remain visible while the remote preview loads. They are not treated as evidence of remote image availability; storage confirmation is the upload-success criterion. Blob URLs are released on remote load, definitive display failure, replacement, removal or unmount. Removing a photo clears pending preview identity.

## Limits

This supports admin image delivery when the browser cannot reach the CDN but Natalo's server can. It cannot fix a deleted/private/corrupt object or a customer-side CDN issue outside admin. Product saving can now proceed after confirmed storage upload even if thumbnail loading fails, as requested. This request did not change Feed, Flutter or storage ACLs. No production product save/upload was performed.

TypeScript, targeted ESLint and whitespace checks passed. Reviewed preview identity, blob cleanup, direct/crop success branches, retry scope, canonical URL persistence, parent busy guards, admin authorization, strict upstream host/path matching, redirect rejection and bounded response reads. Browser reproduction remains unavailable. Release was subsequently requested; deployment status is reported separately in the release conversation.
