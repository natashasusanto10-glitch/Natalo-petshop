import { FiShoppingCart } from "react-icons/fi";
import { IoBagOutline } from "react-icons/io5";

type PetCartIconProps = {
  className?: string;
  iconClassName?: string;
  pawClassName?: string;
  kind?: "bag" | "cart";
};

function PawMark({ className = "" }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="currentColor"
      aria-hidden="true"
      className={className}
    >
      <circle cx="7" cy="9" r="2.4" />
      <circle cx="12" cy="6.7" r="2.3" />
      <circle cx="17" cy="9" r="2.4" />
      <path d="M6.8 16.2c0-3 2.3-5.4 5.2-5.4s5.2 2.4 5.2 5.4c0 1.7-1.1 2.9-2.7 2.9-.8 0-1.5-.3-2-.7a.8.8 0 0 0-1 0c-.5.4-1.2.7-2 .7-1.6 0-2.7-1.2-2.7-2.9Z" />
    </svg>
  );
}

export function PetCartIcon({
  className = "h-5 w-5",
  iconClassName = "h-full w-full",
  pawClassName = "absolute -bottom-0.5 -right-1 h-3.5 w-3.5 rounded-full bg-white p-0.5 text-[#1E5FBF] shadow-sm",
  kind = "bag",
}: PetCartIconProps) {
  const Icon = kind === "bag" ? IoBagOutline : FiShoppingCart;

  return (
    <span className={`relative inline-grid place-items-center ${className}`} aria-hidden="true">
      <Icon className={iconClassName} />
      <PawMark className={pawClassName} />
    </span>
  );
}

export function EmptyCartPetIllustration({ className = "h-11 w-11" }: { className?: string }) {
  return (
    <svg viewBox="0 0 64 64" fill="none" aria-hidden="true" className={className}>
      <rect x="10" y="22" width="34" height="22" rx="8" fill="#DBEAFE" />
      <path
        d="M16 24h30l-3.2 18.2a4 4 0 0 1-4 3.3H20.7a4 4 0 0 1-3.9-3.3L14 18h-5"
        stroke="#1E5FBF"
        strokeWidth="3"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <path
        d="M24 22v-5.2a7 7 0 0 1 14 0V22"
        stroke="#1E5FBF"
        strokeWidth="3"
        strokeLinecap="round"
      />
      <circle cx="23" cy="51" r="3" fill="#1E5FBF" />
      <circle cx="39" cy="51" r="3" fill="#1E5FBF" />
      <path
        d="M42 18.5h10.5c1.4 0 2.5 1.1 2.5 2.5v19.5c0 1.4-1.1 2.5-2.5 2.5H45"
        fill="#EFF6FF"
      />
      <path
        d="M45.5 18.5h7c1.4 0 2.5 1.1 2.5 2.5v19.5c0 1.4-1.1 2.5-2.5 2.5H45"
        stroke="#60A5FA"
        strokeWidth="2.4"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <path d="M48 25h4.5M48 30h4.5" stroke="#93C5FD" strokeWidth="2" strokeLinecap="round" />
      <circle cx="25" cy="32" r="1.9" fill="#1E5FBF" />
      <circle cx="30.5" cy="29.5" r="1.8" fill="#1E5FBF" />
      <circle cx="36" cy="32" r="1.9" fill="#1E5FBF" />
      <path
        d="M24.8 38.3c0-3.1 2.5-5.5 5.7-5.5s5.7 2.4 5.7 5.5c0 1.7-1.1 2.8-2.8 2.8-.9 0-1.6-.3-2.2-.8a1.1 1.1 0 0 0-1.4 0c-.6.5-1.3.8-2.2.8-1.7 0-2.8-1.1-2.8-2.8Z"
        fill="#1E5FBF"
      />
    </svg>
  );
}
