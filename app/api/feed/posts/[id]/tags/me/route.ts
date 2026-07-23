/**
 * Tag People (Spec B) — self-service untuk user yang DITANDAI:
 *   DELETE → "Hapus saya dari post" (hapus baris tag miliknya sendiri).
 *   PATCH {hidden} → "Sembunyikan/Tampilkan di profil saya".
 * Otorisasi: session user == taggedUserId (baris orang lain tidak
 * tersentuh — where compound unique feedPostId+taggedUserId).
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { prisma } from "@/lib/prisma";
import { parseHiddenBody } from "@/lib/feed/tagged-users";

async function requireSession(request: NextRequest) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return { reject: csrfReject, session: null };
  const session = await getSession("CUSTOMER");
  if (!session) {
    return {
      reject: NextResponse.json(
        { error: "LOGIN_REQUIRED", message: "Login dulu." },
        { status: 401 },
      ),
      session: null,
    };
  }
  return { reject: null, session };
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  const { reject, session } = await requireSession(request);
  if (reject || !session) return reject;

  const deleted = await prisma.feedTaggedUser.deleteMany({
    where: { feedPostId: id, taggedUserId: session.sub },
  });
  if (deleted.count === 0) {
    return NextResponse.json(
      { error: "Kamu tidak ditandai di postingan ini." },
      { status: 404 },
    );
  }
  return NextResponse.json({ ok: true });
}

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  const { reject, session } = await requireSession(request);
  if (reject || !session) return reject;

  const body = await request.json().catch(() => null);
  const parsed = parseHiddenBody(body);
  if (!parsed.ok) {
    return NextResponse.json({ error: parsed.error }, { status: 400 });
  }

  const updated = await prisma.feedTaggedUser.updateMany({
    where: { feedPostId: id, taggedUserId: session.sub },
    data: { hidden: parsed.hidden },
  });
  if (updated.count === 0) {
    return NextResponse.json(
      { error: "Kamu tidak ditandai di postingan ini." },
      { status: 404 },
    );
  }
  return NextResponse.json({ ok: true, hidden: parsed.hidden });
}
