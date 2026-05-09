export type TrustItemIcon = "bolt" | "chat" | "gift" | "paw" | "shield" | "star" | "truck" | "users" | "calendar";

export type TrustItem = {
  icon: TrustItemIcon;
  iconClass: string;
  text: string;
  href?: string;
  external?: boolean;
  showLinkIcon?: boolean;
};

export const trustItems: TrustItem[] = [
  {
    icon: "truck",
    iconClass: "text-natalo-700",
    text: "Gratis Ongkir Area Medan",
  },
  {
    icon: "shield",
    iconClass: "text-emerald-600",
    text: "Produk Original 100%",
  },
  {
    icon: "chat",
    iconClass: "text-natalo-700",
    text: "Konsultasi via WhatsApp",
  },
  {
    icon: "paw",
    iconClass: "text-natalo-700",
    text: "Petshop Medan Terpercaya",
  },
  {
    icon: "gift",
    iconClass: "text-amber-500",
    text: "Banyak Promo Setiap Hari",
  },
];
