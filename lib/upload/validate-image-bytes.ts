const SIGNATURES = {
  jpeg: [0xff, 0xd8, 0xff],
  png: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
  gif87a: [0x47, 0x49, 0x46, 0x38, 0x37, 0x61],
  gif89a: [0x47, 0x49, 0x46, 0x38, 0x39, 0x61],
};

function startsWith(bytes: Uint8Array, signature: number[]) {
  if (bytes.length < signature.length) return false;
  return signature.every((value, index) => bytes[index] === value);
}

function isWebp(bytes: Uint8Array) {
  if (bytes.length < 12) return false;
  const riff =
    bytes[0] === 0x52 &&
    bytes[1] === 0x49 &&
    bytes[2] === 0x46 &&
    bytes[3] === 0x46;
  const webp =
    bytes[8] === 0x57 &&
    bytes[9] === 0x45 &&
    bytes[10] === 0x42 &&
    bytes[11] === 0x50;
  return riff && webp;
}

export function validateImageMagicBytes(buffer: Buffer, mimeType: string) {
  const bytes = new Uint8Array(buffer);

  if (mimeType === "image/jpeg") return startsWith(bytes, SIGNATURES.jpeg);
  if (mimeType === "image/png") return startsWith(bytes, SIGNATURES.png);
  if (mimeType === "image/webp") return isWebp(bytes);
  if (mimeType === "image/gif") {
    return startsWith(bytes, SIGNATURES.gif87a) || startsWith(bytes, SIGNATURES.gif89a);
  }

  return false;
}
