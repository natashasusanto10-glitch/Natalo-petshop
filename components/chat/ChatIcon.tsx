export function ChatIcon({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.8}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      className={className}
    >
      <path d="M21 11.5a8.4 8.4 0 0 1-8.9 8.4 9.3 9.3 0 0 1-3.2-.6L3.5 21l1.4-4.6A8.2 8.2 0 0 1 3.4 11.5C3.4 6.8 7.3 3 12.2 3S21 6.8 21 11.5Z" />
      <circle cx="8.6" cy="11.6" r="0.6" fill="currentColor" />
      <circle cx="12.2" cy="11.6" r="0.6" fill="currentColor" />
      <circle cx="15.8" cy="11.6" r="0.6" fill="currentColor" />
    </svg>
  );
}
