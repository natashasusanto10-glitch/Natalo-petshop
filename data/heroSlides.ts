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
    background: "from-natalo-700 via-natalo-600 to-natalo-500",
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
      textColor: "text-natalo-800",
    },
  },
  {
    id: "instant-delivery",
    type: "content",
    background: "from-orange-500 via-orange-600 to-natalo-600",
    icon: "bolt",
    badge: "Instant 3 jam",
    headlineBefore: "Pesan pagi,",
    headlineHighlight: "sampai sore",
    subtitle: "Pengiriman instan via Gojek untuk area Medan. Order sebelum 15.00 WIB.",
    cta: {
      text: "Belanja sekarang",
      href: "/products",
      bg: "bg-white",
      textColor: "text-orange-700",
    },
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
    type: "content",
    background: "from-natalo-800 via-natalo-700 to-rose-700",
    icon: "store",
    badge: "Est. 2019",
    headlineHighlight: "6 tahun",
    headlineAfter: "melayani pecinta hewan",
    subtitle: "Toko fisik di Medan, top seller di Tokopedia dan Shopee.",
    cta: {
      text: "Tentang kami",
      href: "/tentang-kami",
      bg: "bg-white",
      textColor: "text-natalo-800",
    },
  },
];
