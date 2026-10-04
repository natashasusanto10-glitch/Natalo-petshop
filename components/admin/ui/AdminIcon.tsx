/** Compact decorative symbols shared by operational admin cards. */
export function AdminIcon({ name }: { name: string }) {
  const paths: Record<string, string> = {
    "🏷": "M20 13l-7 7-10-10V3h7l10 10ZM7 7h.01",
    "🎫": "M3 7h18v4a2 2 0 0 0 0 4v4H3v-4a2 2 0 0 0 0-4V7ZM14 7v12",
    "⚡": "m13 2-9 12h7l-1 8 10-12h-7l0-8Z",
    "📦": "m3 7 9-4 9 4v10l-9 4-9-4V7Zm0 0 9 4 9-4M12 11v10",
  };
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d={paths[name] ?? paths["📦"]} />
    </svg>
  );
}
