"use client";

/**
 * Floating progress pill for background feed uploads. Subscribes to the
 * <FeedUploadProvider> state and renders a slim toast at the bottom of
 * the viewport so the user can keep scrolling the feed while their video
 * compresses + uploads + posts.
 *
 * Variants:
 *   - in-flight  → dark pill with spinner / determinate bar + stage copy
 *   - done       → green-tinted "Postingan terkirim!" with check, auto-dismiss
 *   - error      → red-tinted line with retry-style dismiss
 */

import Link from "next/link";
import { FiCheck, FiX } from "react-icons/fi";
import { useFeedUpload, type FeedUploadStage } from "@/components/feed/FeedUploadProvider";

const STAGE_LABEL: Record<FeedUploadStage, string> = {
  compressing: "Mengompres video…",
  "uploading-video": "Mengupload video…",
  "uploading-thumbnail": "Menyiapkan thumbnail…",
  submitting: "Menyimpan postingan…",
  done: "Postingan terkirim",
  error: "Upload gagal",
};

export function FeedUploadToast() {
  const { state, dismiss } = useFeedUpload();
  if (!state.active || !state.stage) return null;

  const isDone = state.stage === "done";
  const isError = state.stage === "error";
  const isWorking = !isDone && !isError;

  const label = STAGE_LABEL[state.stage];
  const determinate = state.stage === "compressing" && state.progress >= 0;
  const pct = Math.max(0, Math.min(1, state.progress));

  return (
    <div className="pointer-events-none fixed inset-x-0 bottom-[calc(96px+env(safe-area-inset-bottom))] z-[80] flex justify-center px-4 md:bottom-6">
      <div
        role="status"
        aria-live="polite"
        className={`pointer-events-auto flex w-full max-w-sm items-center gap-3 rounded-full px-4 py-3 text-sm font-bold text-white shadow-2xl backdrop-blur-md transition ${
          isError
            ? "bg-red-600/95"
            : isDone
              ? "bg-emerald-600/95"
              : "bg-slate-950/90"
        }`}
      >
        <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-white/15">
          {isDone ? (
            <FiCheck className="h-4 w-4" aria-hidden="true" />
          ) : isError ? (
            <FiX className="h-4 w-4" aria-hidden="true" />
          ) : (
            <span
              className="h-3.5 w-3.5 animate-spin rounded-full border-2 border-white/30 border-t-white"
              aria-hidden="true"
            />
          )}
        </span>

        <div className="min-w-0 flex-1">
          <p className="truncate text-sm leading-tight">{label}</p>
          {isWorking && determinate && (
            <div className="mt-1.5 h-1 w-full overflow-hidden rounded-full bg-white/20">
              <div
                className="h-full rounded-full bg-white transition-[width] duration-200 ease-out"
                style={{ width: `${Math.round(pct * 100)}%` }}
              />
            </div>
          )}
          {isError && state.error && (
            <p className="truncate text-xs font-semibold text-white/85">
              {state.error}
            </p>
          )}
          {isDone && (
            <p className="truncate text-xs font-semibold text-white/85">
              Menunggu review admin (max. 1×24 jam).
            </p>
          )}
        </div>

        {isDone && (
          <Link
            href="/notifications"
            onClick={dismiss}
            className="shrink-0 whitespace-nowrap rounded-full bg-white/20 px-3 py-1 text-xs font-black text-white hover:bg-white/30"
          >
            Status
          </Link>
        )}

        {(isError || isDone) && (
          <button
            type="button"
            onClick={dismiss}
            aria-label="Tutup"
            className="-mr-1 grid h-7 w-7 shrink-0 place-items-center rounded-full bg-white/10 text-white/90 transition active:bg-white/20"
          >
            <FiX className="h-4 w-4" />
          </button>
        )}
      </div>
    </div>
  );
}
