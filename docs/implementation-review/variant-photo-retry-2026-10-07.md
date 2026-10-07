# Variant photo upload retry review — 7 October 2026

## Evidence and limits

The supplied screen photo shows a loaded crop source and preview, followed by a generic save/load error. It does not identify whether canvas export, POST /api/admin/upload, or reading the returned image URL failed. Available production log queries returned no matching records; this does not prove upload success. The original file and failure response are still needed to reproduce the reported incident.

## Changes

- Keep the exported crop while the editor stays open. Retry does not export the same crop again.
- Keep a confirmed upload URL. If image verification fails, retry checks that URL instead of uploading another copy.
- Cache identity includes editor revision, zoom, rotation, position, and aspect ratio. Changing the crop invalidates reuse; opening another source resets both caches.
- Separate processing, upload, and image loading errors. Upload failures retain the underlying error message.
- Announce processing, uploading, and verification through a live status region.
- Retry public UploadThing image loads with a unique query after the first failed attempt, avoiding a cached failed response. URLs with existing query parameters are unchanged.
- Persist the original uploaded URL. The current field uses the URL that actually loaded for its thumbnail and preview.
- Apply a replacement only after image verification succeeds. The crop and existing photo remain available on failure.
- Raise image-load timeout from 4 seconds to 10 seconds per attempt (three attempts), so a slow image response has more time to complete. Stop timed-out image loads before retrying.
- Shared admin upload errors include HTTP status, explicit expired-session and request-size messages, and validation of the returned HTTPS URL. Invalid response bodies do not silently become broken image URLs.

The follow-up attachment is a photo of Windows file Properties, showing chicken.jpg at 343,559 bytes (335 KB), not the original image file. This source size is below the 2 MB limit, but the actual exported crop size and network responses are unknown. The reported intermittent behavior is compatible with an image-load timeout; this is a hypothesis, not a confirmed incident cause.

## Review

Reviewed cache invalidation, retry branches, busy guards, canonical URL persistence, and preview rendering. Existing canvas dimensions and JPEG compression remain unchanged: square export up to 1200 pixels at JPEG quality 0.88. Exports within 2 MB go directly to the shared upload request without a second encode; oversized exports still use the shared compressor and 2 MB size check.

ProductMediaRail now displays local thumbnails immediately while each file is uploading. These temporary blob URLs are display-only and never enter the product's saved image URLs. Pending slots are removed by the original file index as requests settle; URLs are released when the batch ends or the component unmounts. Existing upload concurrency and parent save guard remain unchanged. No throughput measurements or claims of matching Shopee speed were made.

TypeScript and targeted ESLint passed. No browser upload reproduction or production save was performed. This change corrects retry behavior and diagnosis; it does not establish the original incident's root cause or prove production upload reliability.

Review completed locally before commit and deployment. Production deployment status is reported separately in the release conversation.
