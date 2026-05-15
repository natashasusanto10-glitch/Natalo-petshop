import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import { FeedUploadClient } from "@/components/feed/FeedUploadClient";
import { PageStatusBar } from "@/components/PageStatusBar";

export const metadata: Metadata = {
  title: "Upload Video — Feed Natalo",
};

// Wajib login customer. Admin tidak pakai page ini (admin posting via
// dashboard di F5). Kalau tidak login → redirect ke login dgn returnUrl.
export default async function FeedUploadPage() {
  const session = await getSession();
  if (!session) {
    redirect("/member/login?returnUrl=/feed/upload");
  }
  if (session.role === "ADMIN") {
    redirect("/feed");
  }

  return (
    <main className="min-h-[100dvh] overflow-x-hidden bg-black text-white">
      <PageStatusBar
        iconColor="light"
        themeColor="#000000"
        nativeBackgroundColor="#00000000"
        overlaysWebView
      />
      <div className="feed-upload-page-enter min-h-[100dvh]">
        <FeedUploadClient />
      </div>
      <style>{`
        .feed-upload-page-enter {
          animation: feed-upload-page-enter 320ms cubic-bezier(0.22, 1, 0.36, 1) both;
        }

        @keyframes feed-upload-page-enter {
          from {
            opacity: 0.92;
            transform: translate3d(100%, 0, 0);
          }
          to {
            opacity: 1;
            transform: translate3d(0, 0, 0);
          }
        }

        @media (prefers-reduced-motion: reduce) {
          .feed-upload-page-enter {
            animation: none !important;
          }
        }
      `}</style>
    </main>
  );
}
