import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";

export async function GET() {
  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const threads = await prisma.chatThread.findMany({
    orderBy: { updatedAt: "desc" },
    take: 100,
    include: {
      user: { select: { id: true, name: true, phone: true, email: true } },
      messages: {
        orderBy: { createdAt: "desc" },
        take: 1,
        select: { id: true, senderRole: true, content: true, createdAt: true },
      },
    },
  });

  const unreadRows = await prisma.chatMessage.groupBy({
    by: ["threadId"],
    where: { senderRole: "CUSTOMER", readAt: null },
    _count: true,
  });
  const unreadMap = new Map(unreadRows.map((row) => [row.threadId, row._count]));

  return NextResponse.json({
    threads: threads.map((thread) => ({
      id: thread.id,
      status: thread.status,
      updatedAt: thread.updatedAt,
      user: thread.user,
      lastMessage: thread.messages[0] ?? null,
      unreadCount: unreadMap.get(thread.id) ?? 0,
    })),
  });
}
