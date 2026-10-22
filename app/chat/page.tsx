"use client";

import { Suspense } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { ChatConversation } from "@/components/chat/ChatConversation";
import { parseChatContext } from "@/lib/chat/web-client";

function ChatPageInner() {
  const router = useRouter();
  const search = useSearchParams();
  const context = parseChatContext(new URLSearchParams(search.toString()));
  const pname = (search.get("pname") ?? "").trim().slice(0, 80);

  function goBack() {
    if (typeof window !== "undefined" && window.history.length > 1) router.back();
    else router.push("/");
  }

  return (
    <div className="mx-auto box-border h-[calc(100dvh-env(safe-area-inset-bottom))] w-full max-w-[720px] pt-[env(safe-area-inset-top)] md:border-x md:border-slate-200">
      <ChatConversation
        variant="page"
        context={context}
        onBack={goBack}
        contextLabel={pname || undefined}
      />
    </div>
  );
}

export default function ChatPage() {
  return (
    <Suspense fallback={null}>
      <ChatPageInner />
    </Suspense>
  );
}
