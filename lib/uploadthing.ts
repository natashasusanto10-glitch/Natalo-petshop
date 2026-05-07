import { UTApi } from "uploadthing/server";

// Singleton UTApi client. Reads UPLOADTHING_TOKEN from env automatically.
// Get token from https://uploadthing.com → dashboard → API Keys.
export const utapi = new UTApi();

export type UploadResult = { url: string; key: string };

/**
 * Upload a single File to UploadThing and return its CDN URL + storage key.
 * Throws on any failure — caller should wrap in try/catch and return 500.
 */
export async function uploadToUT(file: File, prefix?: string): Promise<UploadResult> {
  const renamed = prefix
    ? new File([file], `${prefix}-${Date.now()}-${file.name}`, { type: file.type })
    : file;
  const res = await utapi.uploadFiles(renamed);
  if (res.error || !res.data) {
    throw new Error(res.error?.message ?? "Upload gagal");
  }
  return { url: res.data.ufsUrl, key: res.data.key };
}
