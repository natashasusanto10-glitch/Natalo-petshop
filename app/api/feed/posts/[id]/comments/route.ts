/**
 * GET /api/feed/posts/[id]/comments?cursor=<commentId>  — list (lazy)
 * POST /api/feed/posts/[id]/comments  — add comment (auth required)
 *
 * Spec 10.7: comments lazy-loaded. User tap icon comment → load 20+pagination.
 * Posting: transaction supaya commentCount counter di-sync atomic.
 * Admin reply (parentCommentId set, isAdminOfficial=true) belum di-implement
 * dalam endpoint ini — admin akan reply via /api/admin/feed/* di F5.
 */
import { after, NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { prisma } from "@/lib/prisma";
import { listFeedComments } from "@/lib/feed/queries";
import {
  sendCommentNotification,
  sendMentionNotifications,
  sendReplyNotification,
} from "@/lib/feed/activity-notifications";
import {
  extractMentionHandles,
  resolveMentionedUsers,
} from "@/lib/feed/mentions";

const MAX_COMMENT_LENGTH = 1000;

/**
 * Anti-spam rate limit untuk komentar.
 *
 * Window 5 menit, max 10 komentar per user. Window-based count (bukan
 * proper leaky bucket per-second), tapi cukup efektif untuk Natalo scale:
 *   - User normal: 2-3 komentar / 5 menit (rapid back-and-forth chat)
 *   - User aktif diskusi: 5-7 / 5 menit (interactive thread)
 *   - Spammer / troll: 50+ dalam 30 detik = block keras
 *
 * Count over BOTH top-level + replies — supaya troll yang reply spam ke
 * 1 komentar berkali-kali tetap kena limit. Authors di-track via
 * authorId, jadi tidak per-post (1 user gak bisa workaround dengan ganti
 * post).
 *
 * Admin exempt — mereka perlu reply moderasi cepat.
 */
const COMMENT_RATE_LIMIT_PER_WINDOW = 10;
const COMMENT_RATE_LIMIT_WINDOW_MS = 5 * 60 * 1000; // 5 menit

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id: postId } = await params;
  if (!postId) {
    return NextResponse.json({ error: "Post ID required" }, { status: 400 });
  }

  const post = await prisma.feedPost
    .findUnique({
      where: { id: postId },
      select: { id: true, status: true, deletedAt: true },
    })
    .catch(() => null);
  if (!post || post.status !== "ACTIVE" || post.deletedAt) {
    return NextResponse.json({ error: "Post tidak ditemukan" }, { status: 404 });
  }

  const { searchParams } = new URL(request.url);
  const cursor = searchParams.get("cursor") || null;

  const session = await getSession().catch(() => null);
  const result = await listFeedComments({
    postId,
    cursor,
    viewerUserId: session?.sub ?? null,
  });

  return NextResponse.json(result);
}

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: "Login dulu untuk komentar." }, { status: 401 });
  }

  const { id: postId } = await params;
  if (!postId) {
    return NextResponse.json({ error: "Post ID required" }, { status: 400 });
  }

  const post = await prisma.feedPost.findUnique({
    where: { id: postId },
    select: { id: true, status: true, deletedAt: true },
  });
  if (!post || post.status !== "ACTIVE" || post.deletedAt) {
    return NextResponse.json({ error: "Post tidak ditemukan" }, { status: 404 });
  }

  const body = await request.json().catch(() => ({}));
  const content = String((body as { content?: unknown }).content ?? "").trim();
  if (!content) {
    return NextResponse.json({ error: "Komentar tidak boleh kosong." }, { status: 400 });
  }
  if (content.length > MAX_COMMENT_LENGTH) {
    return NextResponse.json(
      { error: `Komentar maksimal ${MAX_COMMENT_LENGTH} karakter.` },
      { status: 400 },
    );
  }

  // Anti-spam: max 10 unique @mention per komentar. Cegah DDoS notif
  // via mention flooding (e.g. 100 user di-tag sekaligus). Block sebelum
  // create comment supaya gak waste DB row + notif worker time.
  const mentionHandlesEarly = extractMentionHandles(content);
  if (mentionHandlesEarly.size > 10) {
    return NextResponse.json(
      {
        error: `Maksimal 10 mention per komentar (kamu pakai ${mentionHandlesEarly.size}).`,
      },
      { status: 400 },
    );
  }

  const rawParent = (body as { parentCommentId?: unknown }).parentCommentId;
  const parentCommentId = typeof rawParent === "string" && rawParent ? rawParent : null;

  // Verify parent comment exists + masih di post yang sama (kalau ada).
  if (parentCommentId) {
    const parent = await prisma.feedComment.findUnique({
      where: { id: parentCommentId },
      select: { id: true, postId: true, isHidden: true },
    });
    if (!parent || parent.postId !== postId || parent.isHidden) {
      return NextResponse.json(
        { error: "Komentar parent tidak valid." },
        { status: 400 },
      );
    }
  }

  const isAdmin = session.role === "ADMIN";

  // Rate limit — skip admin. Cek SEBELUM transaction supaya tidak waste
  // DB write untuk request yang akan ditolak. Window-based count atas
  // semua komentar (top-level + reply) dari user dalam 5 menit terakhir.
  if (!isAdmin) {
    const since = new Date(Date.now() - COMMENT_RATE_LIMIT_WINDOW_MS);
    const recentCount = await prisma.feedComment.count({
      where: {
        authorId: session.sub,
        createdAt: { gte: since },
      },
    });
    if (recentCount >= COMMENT_RATE_LIMIT_PER_WINDOW) {
      return NextResponse.json(
        {
          error:
            "Kamu komentar terlalu cepat. Coba lagi dalam beberapa menit.",
          rateLimited: true,
          retryAfterMs: COMMENT_RATE_LIMIT_WINDOW_MS,
        },
        { status: 429 },
      );
    }
  }

  const result = await prisma.$transaction(async (tx) => {
    const comment = await tx.feedComment.create({
      data: {
        postId,
        authorId: session.sub,
        parentCommentId,
        content,
        isAdminOfficial: isAdmin,
      },
      include: {
        // BUG FIX: tambah profilePhotoUrl ke author select. Sebelumnya
        // POST response author hanya {id, name, role} → Flutter parse
        // author dengan profilePhotoUrl=null → avatar fallback ke
        // initial saat user post komentar baru. GET listing sudah benar
        // (lihat lib/feed/queries.ts mapFeedComment), bug cuma di
        // create-then-return path.
        author: {
          select: {
            id: true,
            name: true,
            username: true,
            role: true,
            profilePhotoUrl: true,
          },
        },
      },
    });
    // Count both top-level comments and replies so the drawer/action rail
    // matches the visible conversation total.
    await tx.feedPost.update({
      where: { id: postId },
      data: { commentCount: { increment: 1 } },
    });
    return comment;
  });

  // Activity notification via `after()` (bukan `void`) — void promise bisa
  // dibekukan Vercel sebelum jalan → notif hilang; after() dijamin eksekusi
  // setelah response tanpa menahan komentar muncul. Reply path goes to the
  // parent comment's author; top-level comment goes to the post author.
  // Helpers skip self-notify + admin-authored posts internally.
  if (parentCommentId) {
    after(() =>
      sendReplyNotification({
        parentCommentId,
        replyCommentId: result.id,
        postId,
        actorUserId: session.sub,
        content,
      }),
    );
  } else {
    after(() =>
      sendCommentNotification({
        postId,
        commentId: result.id,
        actorUserId: session.sub,
        content,
      }),
    );
  }

  // @mention notification — separate dari reply/comment notif supaya user
  // yang di-mention dapat alert spesifik "@asiong menyebut kamu", bukan
  // notif post-author generic. Fire ke SEMUA user yang di-mention di
  // text. Dedup via tag di sendMentionNotifications. Skip kalau actor
  // sendiri ada di list (self-mention). Via after() — bukan void IIFE
  // yang bisa dibekukan Vercel sebelum jalan.
  after(async () => {
    try {
      const handles = extractMentionHandles(content);
      if (handles.size === 0) return;
      const mentioned = await resolveMentionedUsers(handles, session.sub);
      if (mentioned.length === 0) return;
      await sendMentionNotifications({
        actorUserId: session.sub,
        recipientUserIds: mentioned.map((u) => u.id),
        source: "comment",
        postId,
        commentId: result.id,
        excerpt: content,
      });
    } catch (err) {
      console.warn("[comments] mention notif failed:", err);
    }
  });

  return NextResponse.json({
    ok: true,
    comment: {
      id: result.id,
      postId: result.postId,
      parentCommentId: result.parentCommentId,
      content: result.content,
      isAdminOfficial: result.isAdminOfficial,
      isHidden: false,
      likeCount: 0,
      createdAt: result.createdAt.toISOString(),
      author: {
        id: result.author.id,
        name: result.author.name,
        username: result.author.username ?? null,
        role: (result.author.role === "ADMIN" ? "ADMIN" : "CUSTOMER") as "ADMIN" | "CUSTOMER",
        // Include profilePhotoUrl di response — match shape dengan GET
        // listing supaya Flutter dapat tampil avatar foto user yang
        // benar saat comment baru pertama kali muncul di drawer.
        profilePhotoUrl: result.author.profilePhotoUrl ?? null,
      },
      viewerLiked: false,
    },
  });
}
