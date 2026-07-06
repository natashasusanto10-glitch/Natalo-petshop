export type LoyaltyTier = {
  points: number;
  discountAmount: number;
  minimumOrder: number;
  label: string;
};

// Sumber tunggal tabel tier tukar poin loyalty. Sebelumnya terduplikasi di
// app/api/member/claim-voucher/route.ts dan RedeemPointsClient.tsx.
// Earn rate: 1 poin per Rp20.000 belanja.
export const LOYALTY_TIERS: readonly LoyaltyTier[] = [
  { points: 20, discountAmount: 10000, minimumOrder: 150000, label: "20 poin -> voucher Rp10.000 (min belanja Rp150.000)" },
  { points: 50, discountAmount: 25000, minimumOrder: 300000, label: "50 poin -> voucher Rp25.000 (min belanja Rp300.000)" },
  { points: 75, discountAmount: 40000, minimumOrder: 500000, label: "75 poin -> voucher Rp40.000 (min belanja Rp500.000)" },
  { points: 100, discountAmount: 60000, minimumOrder: 700000, label: "100 poin -> voucher Rp60.000 (min belanja Rp700.000)" },
  { points: 200, discountAmount: 150000, minimumOrder: 1500000, label: "200 poin -> voucher Rp150.000 (min belanja Rp1.500.000)" },
] as const;

// Balikan jumlah poin dari nominal diskon voucher loyalty. Nominal unik per
// tier, jadi cukup match discountAmount. null bila bukan nominal tier.
export function loyaltyPointsForDiscount(discountAmount: number): number | null {
  const tier = LOYALTY_TIERS.find((t) => t.discountAmount === discountAmount);
  return tier ? tier.points : null;
}
