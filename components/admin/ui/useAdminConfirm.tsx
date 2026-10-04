"use client";

import { useEffect, useRef, useState } from "react";
import { ConfirmDialog } from "./ConfirmDialog";

/** Awaitable confirmation with the shared keyboard and motion behavior. */
export function useAdminConfirm() {
  const [message, setMessage] = useState<string | null>(null);
  const resolve = useRef<((accepted: boolean) => void) | null>(null);
  useEffect(() => () => resolve.current?.(false), []);
  function finish(accepted: boolean) {
    resolve.current?.(accepted);
    resolve.current = null;
    setMessage(null);
  }
  function confirm(nextMessage: string) {
    resolve.current?.(false);
    setMessage(nextMessage);
    return new Promise<boolean>((done) => {
      resolve.current = done;
    });
  }
  const confirmation = (
    <ConfirmDialog
      open={message !== null}
      message={message ?? ""}
      onCancel={() => finish(false)}
      onConfirm={() => finish(true)}
    />
  );
  return { confirm, confirmation };
}
