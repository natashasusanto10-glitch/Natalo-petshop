# Product admin video preparation — 8 October 2026

## Change

ProductVideoDraft no longer encodes every video before upload. A non-empty MP4, MOV or WebM up to the existing 200 MB source limit, with valid browser-readable metadata, 10–60 second selected duration, and dimensions within 3840×2160 (including portrait) can use the original file when the entire video is selected. That branch does not import or load FFmpeg. Existing TUS uploads target the separate product Bunny library; final encoding remains Bunny's responsibility.

Bunny supports these input containers and dimensions: https://docs.bunny.net/docs/stream-best-practices . The effective encoder profile depends on the existing product library configuration and was not changed.

## Trimming and fallback

- Only selected ranges load the stream-copy trimmer. It preserves the MP4/MOV/WebM container and copies the first video stream and optional audio without re-encoding.
- The trimmer owns its worker, file system, fetch cancellation, timeout and blob URLs. It does not reset the shared Feed FFmpeg worker.
- A 60 second deadline includes worker loading, file reads, trim and output reads. Timeout stops the worker and requests; it reports a trim error rather than silently starting a second heavy encode.
- Stream-copy results are checked against 10–60 second limits and the requested length (0.5 second tolerance). Unsupported copy or unsuitable duration uses the existing compression utility as a fallback. Sources above supported input dimensions also require that fallback.
- Full compression can still take up to its existing 90 second limit on that exceptional path. It is no longer used for every unchanged video.
- Prepared results remain cached until selection or trim changes, as in the existing component.

## Review

Reviewed complete-file bypass, selection bounds, format/size/dimension validation, trim cleanup, post-timeout late callbacks, container MIME, fallback behavior, prepared caching and duration propagation. POST and PATCH video calls now receive the measured prepared duration; TUS metadata uses the prepared file's actual MIME type. UI distinguishes checking, trimming, fallback preparation and upload.

Only the product component and a product-specific preparation helper were changed for this work. Existing unrelated local edits in ProductVideoDraft were preserved. Shared Feed files and Flutter were not edited.

TypeScript, targeted ESLint and whitespace checks passed. No test suite, browser encoding run, device run, live Bunny upload or production save was performed. The original user's 50 second file was not supplied, so its codec, dimensions and network behavior remain unverified. A larger original file may take longer to transfer even though browser preparation is faster. TUS transient retries within one active upload remain existing behavior; this change does not add resume after page reload or after the existing failure compensation deletes the video.

Review completed locally before release. Commit and production deployment status are reported separately in the release conversation.
