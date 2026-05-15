/**
 * POST /api/feed/posts/[id]/share
 *
 * Increment the denormalized shareCount on a FeedPost. Called by the
 * client after the native share sheet (Capacitor Share / navigator.share
 * / clipboard fallback) actually resolves to a successful share —
 * cancelled or failed shares are not counted.
 *
 * Anonymous: yes. Sharing a public post is a public action and counting
 * it doesn't require login. Spam protection lives in the rate-limit
 * layer if needed later — current threat model isn't worth gating.
 *
 * Returns the post's new shareCount so the client can reconcile its
 * optimistic update.
 */
import { NextRequest, NextResponse } from "next/server";
import { assertSameOrigin } from "@/lib/csrf";
import { prisma } from "@/lib/prisma";

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const { id: postId } = await params;
  if (!postId) {
    return NextResponse.json({ error: "Post ID required" }, { status: 400 });
  }

  try {
    const updated = await prisma.feedPost.update({
      where: { id: postId },
      data: { shareCount: { increment: 1 } },
      select: { shareCount: true, status: true },
    });

    // Allow shares of ACTIVE posts only; if the post moved to a non-public
    // status between the user's gesture and this call we shouldn't credit it.
    if (updated.status !== "ACTIVE") {
      return NextResponse.json(
        { error: "Post tidak ditemukan" },
        { status: 404 },
      );
    }

    return NextResponse.json({ ok: true, shareCount: updated.shareCount });
  } catch {
    return NextResponse.json(
      { error: "Post tidak ditemukan" },
      { status: 404 },
    );
  }
}
