export type HeroSlideIcon = "award" | "bolt" | "fish" | "gift" | "store";

export type HeroSlide =
  | {
      id: string;
      type: "content";
      background: string;
      icon: HeroSlideIcon;
      badge: string;
      headlineBefore?: string;
      headlineHighlight: string;
      headlineAfter?: string;
      subtitle: string;
      cta: {
        text: string;
        href: string;
        bg?: string;
        textColor?: string;
      };
      activeFrom?: string;
      activeUntil?: string;
      priority?: boolean;
    }
  | {
      id: string;
      type: "image";
      image: string;
      imageAlt: string;
      href?: string;
      activeFrom?: string;
      activeUntil?: string;
      priority?: boolean;
    };

export const heroSlides: HeroSlide[] = [
  {
    id: "happy-dog-banner",
    type: "image",
    image: "/banners/happy-dog.jpg",
    imageAlt: "Happy Dog — All you feed is love. Made with love in Germany.",
    href: "/products?kategori=anjing",
    priority: true,
  },
  {
    id: "instant-delivery",
    type: "image",
    image: "/banners/instant-max-3-jam.jpg",
    imageAlt: "Pengiriman Cepat — Instant Max 3 Jam dengan kurir Natalo Petshop di Medan.",
    href: "/products",
  },
  {
    id: "member-benefit",
    type: "image",
    image: "/banners/member-benefit.png",
    imageAlt: "Khusus member baru — Diskon Rp50.000 di orderan pertama, kode voucher NATA-NEW.",
    href: "/member/register",
  },
  {
    id: "heritage",
    type: "image",
    image: "/banners/heritage-7-tahun.jpg",
    imageAlt: "7 tahun melayani pecinta hewan — Natalo Petshop, toko fisik di Medan, top seller Tokopedia & Shopee.",
    href: "/tentang-kami",
  },
];
