"use client";

/**
 * Global background-upload controller for the customer feed.
 *
 * The Create Post sheet calls `start()` and immediately dismisses. The
 * provider keeps running the compress → upload video → upload thumbnail →
 * POST /api/feed/posts pipeline in the background, while <FeedUploadToast>
 * renders a floating progress pill at the bottom of the viewport so the
 * user can scroll the feed and watch it tick over.
 *
 * State machine:
 *   idle → compressing → uploading-video → uploading-thumbnail → submitting → done
 *                                                                          ↘ error
 *
 * `done` and `error` are terminal — the toast hangs around for ~3s after
 * `done` then auto-clears back to idle. `error` requires user dismissal.
 */

import { createContext, useCallback, useContext, useRef, useState } from "react";
import { USER_VIDEO_CONFIG } from "@/lib/feed/video-config";

export type FeedUploadStage =
  | "compressing"
  | "uploading-video"
  | "uploading-thumbnail"
  | "submitting"
  | "done"
  | "error";

export type FeedUploadPayload = {
  videoFile: File;
  thumbnailBlob: Blob;
  trimStartSec: number;
  trimDurationSec: number;
  videoWidth: number;
  videoHeight: number;
  caption: string;
  petType: string | null;
  petName: string;
  selectedProductIds: string[];
};

export type FeedUploadState = {
  active: boolean;
  stage: FeedUploadStage | null;
  /** 0–1 for compressing; -1 means indeterminate. */
  progress: number;
  error: string | null;
  postId: string | null;
};

type Context = {
  state: FeedUploadState;
  start: (payload: FeedUploadPayload) => void;
  dismiss: () => void;
};

const FeedUploadContext = createContext<Context | null>(null);

const INITIAL_STATE: FeedUploadState = {
  active: false,
  stage: null,
  progress: 0,
  error: null,
  postId: null,
};

const AUTO_DISMISS_MS = 3000;

export function FeedUploadProvider({ children }: { children: React.ReactNode }) {
  const [state, setState] = useState<FeedUploadState>(INITIAL_STATE);
  const dismissTimerRef = useRef<number | null>(null);

  const dismiss = useCallback(() => {
    if (dismissTimerRef.current) {
      window.clearTimeout(dismissTimerRef.current);
      dismissTimerRef.current = null;
    }
    setState(INITIAL_STATE);
  }, []);

  const start = useCallback((payload: FeedUploadPayload) => {
    // Reset any pending auto-dismiss from a previous run.
    if (dismissTimerRef.current) {
      window.clearTimeout(dismissTimerRef.current);
      dismissTimerRef.current = null;
    }
    setState({
      active: true,
      stage: "compressing",
      progress: 0,
      error: null,
      postId: null,
    });

    void runUpload(payload, setState).finally(() => {
      // Auto-dismiss the toast on success; errors require manual dismissal.
      setState((current) => {
        if (current.stage === "done") {
          dismissTimerRef.current = window.setTimeout(() => {
            setState(INITIAL_STATE);
            dismissTimerRef.current = null;
          }, AUTO_DISMISS_MS);
        }
        return current;
      });
    });
  }, []);

  return (
    <FeedUploadContext.Provider value={{ state, start, dismiss }}>
      {children}
    </FeedUploadContext.Provider>
  );
}

export function useFeedUpload() {
  const ctx = useContext(FeedUploadContext);
  if (!ctx) {
    throw new Error("useFeedUpload must be used inside <FeedUploadProvider>");
  }
  return ctx;
}

async function runUpload(
  payload: FeedUploadPayload,
  setState: React.Dispatch<React.SetStateAction<FeedUploadState>>,
) {
  try {
    // Step 1: compress
    const { compressVideo } = await import("@/lib/feed/video-compressor");
    const compressedFile = await compressVideo(payload.videoFile, {
      config: USER_VIDEO_CONFIG,
      trimStartSec: payload.trimStartSec,
      trimDurationSec: payload.trimDurationSec,
      onProgress: (p) =>
        setState((current) =>
          current.stage === "compressing" ? { ...current, progress: p } : current,
        ),
    });

    // Step 2: upload video
    setState((current) => ({
      ...current,
      stage: "uploading-video",
      progress: -1,
    }));
    const videoForm = new FormData();
    videoForm.append("file", compressedFile);
    const videoRes = await fetch("/api/feed/upload-video", {
      method: "POST",
      body: videoForm,
    });
    const videoData = await videoRes.json().catch(() => ({}));
    if (!videoRes.ok) {
      throw new Error(
        typeof videoData?.error === "string" ? videoData.error : "Upload video gagal.",
      );
    }

    // Step 3: upload thumbnail
    setState((current) => ({
      ...current,
      stage: "uploading-thumbnail",
      progress: -1,
    }));
    const thumbForm = new FormData();
    thumbForm.append(
      "file",
      new File([payload.thumbnailBlob], "thumbnail.jpg", { type: "image/jpeg" }),
    );
    const thumbRes = await fetch("/api/feed/upload-thumbnail", {
      method: "POST",
      body: thumbForm,
    });
    const thumbData = await thumbRes.json().catch(() => ({}));
    if (!thumbRes.ok) {
      throw new Error(
        typeof thumbData?.error === "string"
          ? thumbData.error
          : "Upload thumbnail gagal.",
      );
    }

    // Step 4: submit post
    setState((current) => ({
      ...current,
      stage: "submitting",
      progress: -1,
    }));
    const petInfo = [payload.petType, payload.petName.trim()]
      .filter(Boolean)
      .join(" · ");
    const descriptionParts = [
      payload.caption.trim(),
      petInfo ? `Info peliharaan: ${petInfo}` : "",
    ].filter(Boolean);
    const description = descriptionParts.join("\n\n") || null;
    const title = payload.caption.trim().slice(0, 80) || "Video Feed Natalo";

    const postRes = await fetch("/api/feed/posts", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        title,
        description,
        videoUrl: videoData.url,
        thumbnailUrl: thumbData.url,
        videoMimeType: videoData.mimeType,
        videoSizeBytes: videoData.sizeBytes,
        videoDurationSec: Math.round(payload.trimDurationSec),
        videoWidth: payload.videoWidth,
        videoHeight: payload.videoHeight,
        productId: payload.selectedProductIds[0] ?? null,
        productIds: payload.selectedProductIds,
      }),
    });
    const postData = await postRes.json().catch(() => ({}));
    if (!postRes.ok) {
      throw new Error(
        typeof postData?.error === "string" ? postData.error : "Gagal membuat postingan.",
      );
    }

    setState({
      active: true,
      stage: "done",
      progress: 1,
      error: null,
      postId: String(postData?.post?.id ?? ""),
    });
  } catch (err) {
    setState({
      active: true,
      stage: "error",
      progress: 0,
      error: err instanceof Error ? err.message : "Gagal mengirim postingan.",
      postId: null,
    });
  }
}
