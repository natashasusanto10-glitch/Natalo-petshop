export function canRemoveImage(images: string[]): boolean { return images.length > 1; }

export function removeImageAt(images: string[], index: number): string[] {
  if (index < 0 || index >= images.length || !canRemoveImage(images)) return [...images];
  return images.filter((_, i) => i !== index);
}
