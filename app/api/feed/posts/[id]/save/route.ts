import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { PUBLIC_FEED_POST_WHERE } from "@/lib/feed/queries";
import { prisma } from "@/lib/prisma";

async function authorizeViewer(
  request: NextRequest,
  params: Promise<{ id: string }>,
) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return { response: csrfReject };

  const session = await getSession("CUSTOMER");
  if (!session) {
    return {
      response: NextResponse.json(
        {
          error: "LOGIN_REQUIRED",
          message: "Login dulu untuk menyimpan postingan.",
        },
        { status: 401 },
      ),
    };
  }

  const { id: postId } = await params;
  if (!postId) {
    return {
      response: NextResponse.json(
        { error: "Post ID required" },
        { status: 400 },
      ),
    };
  }

  return { session, postId };
}

async function authorizePublicPost(
  request: NextRequest,
  params: Promise<{ id: string }>,
) {
  const authorized = await authorizeViewer(request, params);
  if ("response" in authorized) return authorized;

  const post = await prisma.feedPost.findFirst({
    where: { id: authorized.postId, ...PUBLIC_FEED_POST_WHERE },
    select: { id: true },
  });
  if (!post) {
    return {
      response: NextResponse.json(
        { error: "POST_NOT_FOUND", message: "Postingan tidak ditemukan." },
        { status: 404 },
      ),
    };
  }

  return authorized;
}

export async function PUT(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const authorized = await authorizePublicPost(request, params);
  if ("response" in authorized) return authorized.response;

  await prisma.feedSave.upsert({
    where: {
      userId_postId: {
        userId: authorized.session.sub,
        postId: authorized.postId,
      },
    },
    create: {
      userId: authorized.session.sub,
      postId: authorized.postId,
    },
    update: {},
  });

  return NextResponse.json({ ok: true, saved: true });
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  // Removing a private bookmark must remain possible even when the post was
  // later hidden, rejected, or deleted from public feeds.
  const authorized = await authorizeViewer(request, params);
  if ("response" in authorized) return authorized.response;

  await prisma.feedSave.deleteMany({
    where: {
      userId: authorized.session.sub,
      postId: authorized.postId,
    },
  });

  return NextResponse.json({ ok: true, saved: false });
}
