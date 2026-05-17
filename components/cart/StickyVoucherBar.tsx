"use client";

import { FiChevronRight, FiTag } from "react-icons/fi";
import { useAutoHideOnInteraction } from "@/hooks/useAutoHideOnInteraction";
import styles from "./StickyVoucherBar.module.css";

type StickyVoucherBarProps = {
  selectedCount: number;
  discountText?: string;
  freeShippingText?: string;
  bonusText?: string;
  noEligibleVoucher?: boolean;
  onClick: () => void;
};

export function StickyVoucherBar({
  selectedCount,
  discountText,
  freeShippingText,
  bonusText,
  noEligibleVoucher = false,
  onClick,
}: StickyVoucherBarProps) {
  const hasSelectedProduct = selectedCount > 0;
  const isVisible = useAutoHideOnInteraction({ delay: 950, enabled: true });
  const hasBenefit = Boolean(discountText || freeShippingText || bonusText);
  const placeholderChip = !hasSelectedProduct
    ? "Pilih produk"
    : noEligibleVoucher
    ? "Belum cocok"
    : "Pilih voucher";

  return (
    <button
      type="button"
      data-auto-hide-ignore="true"
      onClick={onClick}
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

        <span className={styles.content}>
          <span className={styles.mainText}>Voucher untukmu</span>
          <span className={styles.chips}>
            {discountText && (
              <span className={styles.discountChip}>{discountText}</span>
            )}
            {freeShippingText && (
              <span className={styles.shippingChip}>{freeShippingText}</span>
            )}
            {bonusText && <span className={styles.bonusChip}>{bonusText}</span>}
            {!hasBenefit && <span className={styles.placeholderChip}>{placeholderChip}</span>}
          </span>
        </span>
      </span>

      <FiChevronRight size={22} className={styles.chevron} aria-hidden="true" />
    </button>
  );
}
