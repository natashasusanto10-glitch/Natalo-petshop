"use client";

import { useEffect, useState } from "react";

const PROFILE_PHOTO_EVENT = "account-profile-photo-updated";

export function profilePhotoStorageKey(userId: string) {
  return `account:profilePhoto:${userId}`;
}

export function dispatchProfilePhotoUpdated() {
  window.dispatchEvent(new Event(PROFILE_PHOTO_EVENT));
}

type Props = {
  userId: string;
  name: string;
  size?: "sm" | "md" | "lg" | "xl";
  className?: string;
};

const SIZE_CLASS = {
  sm: "h-10 w-10 text-sm",
  md: "h-14 w-14 text-xl",
  lg: "h-20 w-20 text-3xl",
  xl: "h-28 w-28 text-4xl",
};

export function AccountProfileAvatar({
  userId,
  name,
  size = "md",
  className = "",
}: Props) {
  const [photoUrl, setPhotoUrl] = useState<string | null>(null);
  const initial = name.trim().charAt(0).toUpperCase() || "N";

  useEffect(() => {
    function syncPhoto() {
      try {
        setPhotoUrl(localStorage.getItem(profilePhotoStorageKey(userId)));
      } catch {
        setPhotoUrl(null);
      }
    }

    syncPhoto();
    window.addEventListener(PROFILE_PHOTO_EVENT, syncPhoto);
    window.addEventListener("storage", syncPhoto);
    return () => {
      window.removeEventListener(PROFILE_PHOTO_EVENT, syncPhoto);
      window.removeEventListener("storage", syncPhoto);
    };
  }, [userId]);

  return (
    <span
      className={`relative grid shrink-0 place-items-center overflow-hidden rounded-full bg-white/18 font-black text-white ring-1 ring-white/20 ${SIZE_CLASS[size]} ${className}`}
    >
      {photoUrl ? (
        <img
          src={photoUrl}
          alt={name}
          className="h-full w-full object-cover"
        />
      ) : (
        initial
      )}
    </span>
  );
}
