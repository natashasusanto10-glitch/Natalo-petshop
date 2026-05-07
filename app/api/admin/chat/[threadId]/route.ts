import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import { checkChatRateLimit, normalizeChatMessage } from "@/lib/chat";

export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ threadId: string }> }
) {
  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { threadId } = await params;
  const thread = await prisma.chatThread.findUnique({
    where: { id: threadId },
    include: { user: { select: { id: true, name: true, phone: true, email: true } } },
  });
  if (!thread) return NextResponse.json({ error: "Chat tidak ditemukan" }, { status: 404 });

  await prisma.chatMessage.updateMany({
    where: { threadId, senderRole: "CUSTOMER", readAt: null },
    data: { readAt: new Date() },
  });

  const messages = await prisma.chatMessage.findMany({
    where: { threadId },
    orderBy: { createdAt: "asc" },
    take: 200,
    select: {
      id: true,
      senderRole: true,
      content: true,
      createdAt: true,
      readAt: true,
    },
  });

  return NextResponse.json({ thread, messages });
}

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ threadId: string }> }
) {
  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { threadId } = await params;
    const gate = checkChatRateLimit(`admin-chat:${session.sub}:${threadId}`, 30, 60_000);
    if (!gate.ok) {
      return NextResponse.json(
        { error: "Terlalu banyak pesan. Coba lagi sebentar." },
        { status: 429, headers: { "Retry-After": String(gate.retryAfter) } }
      );
    }

    const body = await request.json();
    const content = normalizeChatMessage(body?.content);
    const thread = await prisma.chatThread.findUnique({ where: { id: threadId } });
    if (!thread) return NextResponse.json({ error: "Chat tidak ditemukan" }, { status: 404 });

    const message = await prisma.chatMessage.create({
      data: {
        threadId,
        senderId: session.sub,
        senderRole: "ADMIN",
        content,
      },
      select: {
        id: true,
        senderRole: true,
        content: true,
        createdAt: true,
        readAt: true,
      },
    });
    await prisma.chatThread.update({
      where: { id: threadId },
      data: { updatedAt: new Date(), status: "OPEN" },
    });

    return NextResponse.json({ message }, { status: 201 });
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Gagal mengirim pesan" },
      { status: 400 }
    );
  }
}
