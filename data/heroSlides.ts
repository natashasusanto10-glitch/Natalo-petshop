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
    id: "trust-58k",
    type: "content",
    background: "from-[#B85A18] via-[#E8711F] to-[#FB923C]",
    icon: "award",
    badge: "Rating 5.0 di Tokopedia",
    headlineBefore: "Dipercaya",
    headlineHighlight: "58.000+",
    headlineAfter: "pelanggan se-Indonesia",
    subtitle: "Pakan original, aksesoris lengkap, kirim cepat dari Medan.",
    cta: {
      text: "Belanja sekarang",
      href: "/products",
      bg: "bg-white",
      textColor: "text-[#B85A18]",
    },
  },
  {
    id: "instant-delivery",
    type: "image",
    image: "/banners/instant-max-3-jam.jpg",
    imageAlt: "Pengiriman Cepat — Instant Max 3 Jam dengan kurir Natalo Petshop di Medan.",
    href: "/products",
  },
  {
    id: "aquarium-set",
    type: "content",
    background: "from-cyan-600 via-natalo-600 to-natalo-800",
    icon: "fish",
    badge: "Aquarium set",
    headlineBefore: "Set lengkap mulai",
    headlineHighlight: "Rp199K",
    subtitle: "Tank, filter, lampu LED, dekorasi, semua dalam satu paket hemat.",
    cta: {
      text: "Lihat aquarium",
      href: "/products?kategori=ikan",
      bg: "bg-white",
      textColor: "text-cyan-800",
    },
  },
  {
    id: "member-benefit",
    type: "content",
    background: "from-amber-500 via-amber-600 to-natalo-700",
    icon: "gift",
    badge: "Khusus member baru",
    headlineBefore: "Hemat",
    headlineHighlight: "Rp50.000",
    headlineAfter: "di order pertama",
    subtitle: "Daftar gratis dalam 2 menit, langsung dapat voucher diskon.",
    cta: {
      text: "Daftar member",
      href: "/member/register",
      bg: "bg-white",
      textColor: "text-amber-700",
    },
  },
  {
    id: "heritage",
    type: "image",
    image: "/banners/heritage-7-tahun.jpg",
    imageAlt: "7 tahun melayani pecinta hewan — Natalo Petshop, toko fisik di Medan, top seller Tokopedia & Shopee.",
    href: "/tentang-kami",
  },
];
