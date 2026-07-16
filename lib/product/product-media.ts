export function canRemoveImage(images: string[]): boolean { return images.length > 1; }

export function removeImageAt(images: string[], index: number): string[] {
  if (index < 0 || index >= images.length || !canRemoveImage(images)) return [...images];
  return images.filter((_, i) => i !== index);
}

export function reorderImages(images: string[], from: number, to: number): string[] {
  if (from < 0 || from >= images.length || to < 0 || to >= images.length || from === to) return [...images];
  const next = [...images];
  const [moved] = next.splice(from, 1);
  next.splice(to, 0, moved);
  return next;
}
