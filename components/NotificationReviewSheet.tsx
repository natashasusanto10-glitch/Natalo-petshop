"use client";

import { ReviewFlow } from "@/components/review/ReviewFlow";

type Props = {
  orderNumber: string;
  onClose: () => void;
  onSubmitted?: () => void;
};

/**
 * Thin wrapper preserved for backward compat — delegates to the unified
 * <ReviewFlow>. Used by NotificationsList.
 */
export function NotificationReviewSheet({ orderNumber, onClose, onSubmitted }: Props) {
  return <ReviewFlow orderNumber={orderNumber} onClose={onClose} onSubmitted={onSubmitted} />;
}
