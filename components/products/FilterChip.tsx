type Props = {
  label: string;
  onRemove: () => void;
};

export function FilterChip({ label, onRemove }: Props) {
  return (
    <button
      type="button"
      onClick={onRemove}
      className="inline-flex h-7 max-w-full items-center gap-1 rounded-full bg-natalo-50 px-2.5 text-xs font-extrabold text-natalo-700 active:bg-natalo-100"
    >
      <span className="truncate">{label}</span>
      <svg
        viewBox="0 0 24 24"
        className="h-3.5 w-3.5 shrink-0"
        fill="none"
        stroke="currentColor"
        strokeWidth="2.5"
        strokeLinecap="round"
        aria-hidden="true"
      >
        <path d="M6 6l12 12M18 6L6 18" />
      </svg>
    </button>
  );
}
