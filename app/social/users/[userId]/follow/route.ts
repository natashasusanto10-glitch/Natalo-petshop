import type { NextRequest } from "next/server";
import { assertSameOrigin } from "@/lib/csrf";
import {
  followUser,
  requireSocialUserId,
  socialError,
  socialJson,
  unfollowUser,
} from "../../_follow";

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ userId: string }> },
) {
  // CSRF defense-in-depth — match pola mutation feed lain (like/share/
  // comments/post). Native Flutter request tanpa Origin header di-allow
  // oleh assertSameOrigin (return null), jadi tidak break mobile app.
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;
  try {
    const viewerUserId = await requireSocialUserId();
    const { userId } = await params;
    return socialJson(await followUser(viewerUserId, userId));
  } catch (error) {
    return socialError(error);
  }
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ userId: string }> },
) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;
  try {
    const viewerUserId = await requireSocialUserId();
    const { userId } = await params;
    return socialJson(await unfollowUser(viewerUserId, userId));
  } catch (error) {
    return socialError(error);
  }
}
