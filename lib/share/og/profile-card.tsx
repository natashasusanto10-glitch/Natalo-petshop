import type { PublicShareProfile } from "@/lib/share/profile-share-data";

import { safeOgImageUrl } from "../og-image-security";

export type ProfileShareCardInput = PublicShareProfile & {
  renderedAvatarUrl?: string | null;
};

export type ProfileShareCardModel = {
  avatarUrl: string | null;
  bio: string | null;
  displayName: string;
  followersCount: number;
  followingCount: number;
  isOfficial: boolean;
  postCount: number;
  username: string;
};

export function buildProfileShareCardModel(input: ProfileShareCardInput): ProfileShareCardModel {
  return {
    avatarUrl: safeOgImageUrl(input.avatarUrl),
    bio: input.bio,
    displayName: input.displayName,
    followersCount: input.followersCount,
    followingCount: input.followingCount,
    isOfficial: input.isOfficial,
    postCount: input.postCount,
    username: input.username,
  };
}

function stat(value: number, label: string) {
  return (
    <div style={{ alignItems: "center", display: "flex", flexDirection: "column", gap: 8, minWidth: 104 }}>
      <div style={{ color: "#FFFFFF", display: "flex", fontSize: 34, fontWeight: 800 }}>{value}</div>
      <div style={{ color: "#B9D4FF", display: "flex", fontSize: 18, fontWeight: 700 }}>{label}</div>
    </div>
  );
}

export function renderProfileShareCard(input: ProfileShareCardInput) {
  const card = buildProfileShareCardModel(input);
  const avatarUrl = input.renderedAvatarUrl === undefined ? card.avatarUrl : input.renderedAvatarUrl;

  return (
    <div
      style={{
        alignItems: "center",
        background: "#0F2F63",
        color: "#FFFFFF",
        display: "flex",
        fontFamily: "Arial, sans-serif",
        height: "100%",
        padding: 58,
        width: "100%",
      }}
    >
      <div
        style={{
          alignItems: "center",
          background: "#E9F2FF",
          border: "8px solid #FFFFFF",
          borderRadius: 160,
          display: "flex",
          height: 250,
          justifyContent: "center",
          overflow: "hidden",
          width: 250,
        }}
      >
        {avatarUrl ? (
          <img alt="" height="100%" src={avatarUrl} style={{ height: "100%", objectFit: "cover", width: "100%" }} width="100%" />
        ) : (
          <div style={{ color: "#1E5FBF", display: "flex", fontSize: 100, fontWeight: 900 }}>N</div>
        )}
      </div>
      <div style={{ display: "flex", flex: 1, flexDirection: "column", marginLeft: 52 }}>
        <div style={{ alignItems: "center", display: "flex", gap: 14 }}>
          <div style={{ display: "flex", fontSize: 44, fontWeight: 800 }}>{card.displayName}</div>
          {card.isOfficial ? <div style={{ color: "#F6C650", display: "flex", fontSize: 24, fontWeight: 800 }}>AKUN RESMI</div> : null}
        </div>
        <div style={{ color: "#B9D4FF", display: "flex", fontSize: 28, marginTop: 9 }}>@{card.username}</div>
        <div style={{ WebkitBoxOrient: "vertical", WebkitLineClamp: 2, color: "#E7F0FF", display: "-webkit-box", fontSize: 25, lineHeight: 1.3, marginTop: 24, overflow: "hidden" }}>
          {card.bio ?? "Lihat profil dan postingan terbaru di Natalo."}
        </div>
        <div style={{ display: "flex", gap: 32, marginTop: 42 }}>
          {stat(card.postCount, "Postingan")}
          {stat(card.followersCount, "Pengikut")}
          {stat(card.followingCount, "Mengikuti")}
        </div>
      </div>
    </div>
  );
}
