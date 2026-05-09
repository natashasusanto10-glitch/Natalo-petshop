"use client";

import Image from "next/image";
import { useState } from "react";

type Props = {
  images: string[];
  alt: string;
};

export function ProductImageCarousel({ images, alt }: Props) {
  const safeImages = images.filter(Boolean);
  const [active, setActive] = useState(0);
  const current = safeImages[active];

  return (
    <div className="relative mx-auto aspect-square w-full max-h-[360px] overflow-hidden bg-gray-100 md:max-h-none md:rounded-3xl">
      {current ? (
        <Image
          src={current}
          alt={alt}
          fill
          sizes="(min-width: 1024px) 50vw, 100vw"
          className="object-cover"
          priority
        />
      ) : (
        <div className="flex h-full items-center justify-center text-5xl font-black text-gray-200">
          NP
        </div>
      )}

      <div className="absolute bottom-3 right-3 rounded-full bg-black/65 px-2.5 py-1 text-xs font-bold text-white">
        {safeImages.length ? active + 1 : 1}/{Math.max(safeImages.length, 1)}
      </div>

      {safeImages.length > 1 && (
        <div className="absolute inset-x-0 bottom-3 flex justify-center gap-1.5">
          {safeImages.map((image, index) => (
            <button
              key={`${image}-${index}`}
              type="button"
              aria-label={`Lihat foto ${index + 1}`}
              onClick={() => setActive(index)}
              className={`h-1.5 rounded-full transition-all ${
                active === index ? "w-5 bg-white" : "w-1.5 bg-white/60"
              }`}
            />
          ))}
        </div>
      )}
    </div>
  );
}
