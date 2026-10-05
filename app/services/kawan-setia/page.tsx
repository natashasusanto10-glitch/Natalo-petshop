import type { Metadata } from "next";
import Image from "next/image";
import { FaWhatsapp } from "react-icons/fa";
import { FiHeart, FiBookOpen } from "react-icons/fi";
import { MdOutlineBathtub, MdDirectionsWalk } from "react-icons/md";
import { StickyBackTitle } from "@/components/StickyBackTitle";
import { PageStatusBar } from "@/components/PageStatusBar";
import "./page.css";

export const metadata: Metadata = {
  title: "Kawan Setia",
  description:
    "Mandi dan perawatan, pacak, jalan-jalan, serta latihan anjing bersama Kawan Setia.",
  alternates: { canonical: "/services/kawan-setia" },
  itunes: null,
};

const services = [
  {
    title: "Mandi & Perawatan",
    description: "Biar bersih, wangi, dan nyaman.",
    icon: MdOutlineBathtub,
  },
  {
    title: "Jasa Pacak Anjing",
    description: "Tanyakan pasangan yang tersedia.",
    icon: FiHeart,
  },
  {
    title: "Jalan-Jalan Anjing",
    description: "Teman jalan agar aktif dan ceria.",
    icon: MdDirectionsWalk,
  },
  {
    title: "Latihan Anjing",
    description: "Belajar duduk, diam, dan datang saat dipanggil.",
    icon: FiBookOpen,
  },
];
const whatsappHref = `https://wa.me/6281330003880?text=${encodeURIComponent(
  "Halo Kawan Setia, saya melihat layanan di aplikasi Natalo. Saya ingin bertanya tentang layanan untuk anjing saya."
)}`;

export default function KawanSetiaPage() {
  return (
    <div className="kawan-setia-page">
      <PageStatusBar
        iconColor="dark"
        themeColor="#ffffff"
        nativeBackgroundColor="#ffffff"
        overlaysWebView={false}
      />
      <StickyBackTitle label="Kawan Setia" fallbackHref="/" stickToTop />
      <div className="kawan-setia-content">
        <Image
          src="/assets/images/kawan-setia-hero.jpg"
          alt="Kawan Setia, dengan anjing kecil, sedang, dan besar"
          width={1400}
          height={788}
          priority
          className="kawan-setia-hero"
        />
        <section
          className="kawan-setia-services"
          aria-labelledby="service-title"
        >
          <h1 id="service-title">Yuk, kenali layanan kami</h1>
          <p>Untuk anjing kesayanganmu.</p>
          <ul>
            {services.map(({ title, description, icon: Icon }) => (
              <li key={title}>
                <span className="kawan-setia-icon" aria-hidden="true">
                  <Icon size={25} />
                </span>
                <div>
                  <h2>{title}</h2>
                  <p>{description}</p>
                </div>
              </li>
            ))}
          </ul>
        </section>
      </div>
      <div className="kawan-setia-contact">
        <div>
          <p>Mau tanya layanan atau jadwal?</p>
          <a href={whatsappHref}>
            <FaWhatsapp size={26} aria-hidden="true" />
            Tanya via WhatsApp
          </a>
        </div>
      </div>
    </div>
  );
}
