"use client";

import { useEffect, useState } from "react";
import type { ReactNode } from "react";
import { profilePhotoStorageKey } from "@/components/account/AccountProfileAvatar";

type FeedCreatorInfoProps = {
  userId: string;
  userName: string;
  profilePhotoUrl?: string | null;
  isOfficial?: boolean;
  officialBadge?: ReactNode;
  caption?: string;
  onCaptionClick?: () => void;
};

function normalizedPhotoUrl(value?: string | null) {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}

export function FeedCreatorInfo({
  userId,
  userName,
  profilePhotoUrl,
  isOfficial = false,
  officialBadge,
  caption,
  onCaptionClick,
}: FeedCreatorInfoProps) {
  const [storedPhotoUrl, setStoredPhotoUrl] = useState<string | null>(null);
  const [imageError, setImageError] = useState(false);
  const initial = userName.trim().charAt(0).toUpperCase() || "N";
  const directPhotoUrl = normalizedPhotoUrl(profilePhotoUrl);
  const photoSource = directPhotoUrl ?? storedPhotoUrl;
  const avatarUrl = !imageError ? photoSource : null;

  useEffect(() => {
    if (directPhotoUrl || !userId) {
      setStoredPhotoUrl(null);
      return;
    }

    function syncStoredPhoto() {
      try {
        setStoredPhotoUrl(normalizedPhotoUrl(localStorage.getItem(profilePhotoStorageKey(userId))));
      } catch {
        setStoredPhotoUrl(null);
      }
    }

    syncStoredPhoto();
    window.addEventListener("account-profile-photo-updated", syncStoredPhoto);
    window.addEventListener("storage", syncStoredPhoto);
    return () => {
      window.removeEventListener("account-profile-photo-updated", syncStoredPhoto);
      window.removeEventListener("storage", syncStoredPhoto);
    };
  }, [directPhotoUrl, userId]);

  useEffect(() => {
    setImageError(false);
  }, [photoSource]);

  return (
    <div className="pointer-events-auto flex max-w-full flex-col items-start">
      <div className="flex max-w-full items-center gap-2">
        <div className="relative grid h-8 w-8 shrink-0 place-items-center overflow-hidden rounded-full border border-white/80 bg-white/15 text-xs font-extrabold text-white shadow-[0_1px_8px_rgba(0,0,0,0.35)]">
          {avatarUrl ? (
            <img
              src={avatarUrl}
              alt={`${userName} profile photo`}
              className="h-full w-full object-cover"
              onError={() => setImageError(true)}
            />
          ) : (
            <span className="grid h-full w-full place-items-center bg-blue-600">
              {isOfficial ? "N" : initial}
            </span>
          )}
        </div>

        <p
          className={`min-w-0 truncate text-[16px] leading-tight drop-shadow-[0_1px_5px_rgba(0,0,0,0.65)] ${
            isOfficial ? "font-bold text-[#D6A84A]" : "font-bold text-white"
          }`}
        >
          {userName}
        </p>

        {officialBadge}
      </div>

      {caption ? (
        <button
          type="button"
          onClick={onCaptionClick}
          className="mt-1.5 block max-w-full text-left"
          aria-label="Buka deskripsi dan komentar"
        >
          <p className="line-clamp-2 text-[15px] font-normal leading-snug text-white drop-shadow-[0_1px_5px_rgba(0,0,0,0.65)]">
            {caption}
            <span className="font-semibold text-white/80"> Selengkapnya</span>
          </p>
        </button>
      ) : null}
    </div>
  );
}
