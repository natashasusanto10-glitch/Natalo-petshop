/**
 * Admin UI primitives — barrel re-export.
 *
 * Import pattern:
 *   import { StatCard, SectionCard, EmptyState, PageHeader, Badge } from "@/components/admin/ui";
 *
 * Single source of truth design language untuk admin pages.
 */
export { StatCard } from "./StatCard";
export type { StatCardVariant } from "./StatCard";

export { SectionCard } from "./SectionCard";
export { EmptyState } from "./EmptyState";
export { ResultCount } from "./ResultCount";
export { Pagination } from "./Pagination";
export { PageHeader } from "./PageHeader";
export { AdminPage } from "./AdminPage";
export { FormField } from "./FormField";

export { Button, DangerButton } from "./Button";
export type { ButtonVariant, ButtonSize, ButtonComponentProps } from "./Button";
export { SubmitButton } from "./SubmitButton";
export { ConfirmDialog } from "./ConfirmDialog";
export { ToastProvider, useAdminToast } from "./Toast";

export {
  Badge,
  STATUS_BADGE_VARIANT,
  PAY_BADGE_VARIANT,
} from "./Badge";
export type { BadgeVariant } from "./Badge";
