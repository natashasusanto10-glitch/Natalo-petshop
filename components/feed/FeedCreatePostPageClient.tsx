"use client";

import { useRouter } from "next/navigation";
import { FeedCreatePostSheet } from "./FeedCreatePostSheet";

export function FeedCreatePostPageClient() {
  const router = useRouter();

  function closeToFeed() {
    router.replace("/feed");
  }

  return <FeedCreatePostSheet open onClose={closeToFeed} />;
}
