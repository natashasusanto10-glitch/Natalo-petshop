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
export { PageHeader } from "./PageHeader";

export {
  Badge,
  STATUS_BADGE_VARIANT,
  PAY_BADGE_VARIANT,
} from "./Badge";
export type { BadgeVariant } from "./Badge";
