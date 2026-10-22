"use client";

import { Suspense, useCallback, useEffect } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { ChatConversation } from "@/components/chat/ChatConversation";
import { parseChatContext } from "@/lib/chat/web-client";

function ChatPageInner() {
  const router = useRouter();
  const pathname = usePathname();
  const search = useSearchParams();
  const context = parseChatContext(new URLSearchParams(search.toString()));
  const pname = (search.get("pname") ?? "").trim().slice(0, 80);

  useEffect(() => {
    const root = document.documentElement;
    root.setAttribute("data-chat-route", "true");
    return () => root.removeAttribute("data-chat-route");
  }, []);

  // Kartu sudah terkirim / dibatalkan → buang order/product/pname dari alamat
  // (replace: tanpa entri riwayat baru, posisi gulir tetap). Kembali atau muat
  // ulang halaman ini tidak lagi membawa konteks yang sama. Halaman yang sama →
  // ChatConversation TIDAK dipasang ulang; konteks prop menjadi null.
  const dropContextFromUrl = useCallback(() => {
    const params = new URLSearchParams(window.location.search);
    params.delete("order");
    params.delete("product");
    params.delete("pname");
    const qs = params.toString();
    const path = pathname || "/chat";
    router.replace(qs ? `${path}?${qs}` : path, { scroll: false });
  }, [pathname, router]);

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
        onContextConsumed={dropContextFromUrl}
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
