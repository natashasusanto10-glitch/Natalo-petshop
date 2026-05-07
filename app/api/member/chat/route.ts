import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import {
  checkChatRateLimit,
  getOrCreateCustomerThread,
  normalizeChatMessage,
} from "@/lib/chat";

export async function GET() {
  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const thread = await prisma.chatThread.findUnique({
    where: { userId: session.sub },
  });
  if (!thread) {
    return NextResponse.json({ threadId: null, messages: [] });
  }

  await prisma.chatMessage.updateMany({
    where: { threadId: thread.id, senderRole: "ADMIN", readAt: null },
    data: { readAt: new Date() },
  });

  const messages = await prisma.chatMessage.findMany({
    where: { threadId: thread.id },
    orderBy: { createdAt: "asc" },
    take: 100,
    select: {
      id: true,
      senderRole: true,
      content: true,
      createdAt: true,
      readAt: true,
    },
  });

  return NextResponse.json({ threadId: thread.id, messages });
}

export async function POST(request: NextRequest) {
  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const gate = checkChatRateLimit(`member-chat:${session.sub}`, 20, 60_000);
    if (!gate.ok) {
      return NextResponse.json(
        { error: "Terlalu banyak pesan. Coba lagi sebentar." },
        { status: 429, headers: { "Retry-After": String(gate.retryAfter) } }
      );
    }

    const body = await request.json();
    const content = normalizeChatMessage(body?.content);
    const thread = await getOrCreateCustomerThread(session.sub);
    const message = await prisma.chatMessage.create({
      data: {
        threadId: thread.id,
        senderId: session.sub,
        senderRole: "CUSTOMER",
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
      where: { id: thread.id },
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
