export type TrustItemIcon = "star" | "users" | "calendar" | "bolt";

export type TrustItem = {
  icon: TrustItemIcon;
  iconClass: string;
  text: string;
  href?: string;
  showLinkIcon?: boolean;
};

export const trustItems: TrustItem[] = [
  {
    icon: "star",
    iconClass: "text-amber-500",
    text: "5.0 di Tokopedia",
    href: "https://tk.tokopedia.com/ZS9tktJbt/",
    showLinkIcon: true,
  },
  {
    icon: "star",
    iconClass: "text-amber-500",
    text: "4.9 Shopee Natalo",
    href: "https://shopee.co.id/natalopetshop",
    showLinkIcon: true,
  },
  {
    icon: "star",
    iconClass: "text-amber-500",
    text: "4.9 Shopee Sinar",
    href: "https://shopee.co.id/fuzitapetshop",
    showLinkIcon: true,
  },
  {
    icon: "users",
    iconClass: "text-natalo-700",
    text: "58.000+ pelanggan",
  },
  {
    icon: "calendar",
    iconClass: "text-natalo-700",
    text: "Est. 2019",
  },
  {
    icon: "bolt",
    iconClass: "text-amber-500",
    text: "Instant 3 jam",
  },
];
