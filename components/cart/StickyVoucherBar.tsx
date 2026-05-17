"use client";

import { FiChevronRight, FiTag } from "react-icons/fi";
import { useAutoHideOnInteraction } from "@/hooks/useAutoHideOnInteraction";
import styles from "./StickyVoucherBar.module.css";

type StickyVoucherBarProps = {
  selectedCount: number;
  appliedVoucherText?: string;
  freeShippingText?: string;
  bonusText?: string;
  onClick: () => void;
};

export function StickyVoucherBar({
  selectedCount,
  appliedVoucherText,
  freeShippingText,
  bonusText,
  onClick,
}: StickyVoucherBarProps) {
  const hasSelectedProduct = selectedCount > 0;
  const isVisible = useAutoHideOnInteraction({ delay: 650, enabled: true });
  const hasBenefit = Boolean(appliedVoucherText || freeShippingText || bonusText);

  return (
    <button
      type="button"
      data-auto-hide-ignore="true"
      onClick={onClick}
      disabled={!hasSelectedProduct}
      className={[
        styles.voucherBar,
        isVisible ? styles.show : styles.hide,
        !hasSelectedProduct ? styles.disabled : "",
      ].join(" ")}
      aria-label={
        hasSelectedProduct
          ? "Buka pilihan voucher keranjang"
          : "Pilih produk dulu untuk pakai voucher"
      }
    >
      <span className={styles.left}>
        <span className={styles.iconBadge} aria-hidden="true">
          <FiTag size={21} />
        </span>

        {hasSelectedProduct ? (
          <span className={styles.chips}>
            {appliedVoucherText && (
              <span className={styles.discountChip}>{appliedVoucherText}</span>
            )}
            {freeShippingText && (
              <span className={styles.shippingChip}>{freeShippingText}</span>
            )}
            {bonusText && <span className={styles.bonusChip}>{bonusText}</span>}
            {!hasBenefit && (
              <span className={styles.placeholderText}>
                Pilih voucher untuk hemat belanja
              </span>
            )}
          </span>
        ) : (
          <span className={styles.placeholderText}>
            Pilih produk dulu untuk pakai voucher
          </span>
        )}
      </span>

      <FiChevronRight size={22} className={styles.chevron} aria-hidden="true" />
    </button>
  );
}
