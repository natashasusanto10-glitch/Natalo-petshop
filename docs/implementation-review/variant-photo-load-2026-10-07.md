# Variant photo loading

The supplied screenshot shows the browser's broken-image icon and variant alt text, confirming an image load failure. The exact failed image URL was not available: the screenshot's 9801 product is not present in the production product search. A storage/CDN outage or delay has not been independently established.

The existing flow applied the uploaded URL immediately and had no thumbnail load error state. The updated flow checks that the returned image URL can load with nonzero natural dimensions before replacing the variant photo. The check allows three attempts with a four-second timeout per attempt and short delays. Failure keeps the editor and previous variant URL intact and displays an error; it does not silently accept a broken image.

Existing thumbnails that fail to load show an explicit replacement action instead of the browser's broken-image icon. The URL stored on the variant is still the original CDN URL, never a temporary blob URL. Upload busy state remains active while verifying the image, and server upload/compression logic is unchanged.

Compression remains: square JPEG export capped at 1200 px and quality 0.88; shared admin upload compression for files over 300 KB with a 1600 px maximum/quality 0.85, only using a smaller result; final size cap 2 MB.

Review covered timeout cleanup, retries, preserving the previous image on failure, image error state keyed to its URL and preventing an invalid upload result from becoming the variant photo. No production product or image data was changed during diagnosis. Production upload behavior with the original failing file still needs confirmation after deployment.
