# Direct variant photo upload — 7 October 2026

## Requested flow

The plus button opens the device picker. Choosing a photo starts the shared compressed admin upload without opening the crop dialog. A local thumbnail shows upload progress; the product receives only a verified remote URL. Pencil and delete controls appear after a saved thumbnail exists and remain visible on desktop and touch devices. The pencil opens the crop editor. Clicking the thumbnail opens preview. Delete confirms removal from the product draft.

## Review

- Picker intent distinguishes initial upload from replacing the source inside the crop editor.
- Initial upload has no canvas crop/export stage. Compression, format and size validation continue through the shared uploader.
- Busy guards prevent concurrent selections, edit and deletion during upload. The existing parent upload guard blocks product saving until completion.
- A failed direct upload keeps the selected file for retry. A successful upload followed by failed image verification keeps its URL, so retry only checks image loading.
- Existing images remain unchanged when a replacement fails.
- Removing an image clears pending retries and crop caches, preventing a previously failed attempt from restoring a deleted image.
- Temporary preview object URLs are revoked on replacement, completion or unmount.
- Crop editing, zoom, rotation, keyboard movement, save verification, and cached crop retries remain available through the pencil.

Targeted TypeScript, ESLint, and whitespace checks passed. No browser interaction or production upload was performed. Actual network throughput and the original intermittent failure remain unverified. This change reduces the required interaction steps; it does not claim Shopee-equivalent transfer speed.

Review completed locally before release. Commit and production deployment status are reported separately in the release conversation.
