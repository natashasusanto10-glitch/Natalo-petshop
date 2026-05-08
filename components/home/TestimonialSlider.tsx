"use client";

import { useEffect, useState } from "react";

export type HomeTestimonial = {
  id: string;
  name: string;
  pet: string;
  petEmoji: string;
  avatarEmoji: string;
  quote: string;
  rating: number;
};

type Props = {
  testimonials: HomeTestimonial[];
  intervalMs?: number;
};

export function TestimonialSlider({ testimonials, intervalMs = 5000 }: Props) {
  const [active, setActive] = useState(0);

  useEffect(() => {
    if (testimonials.length <= 1) return;
    const id = setInterval(() => {
      setActive((prev) => (prev + 1) % testimonials.length);
    }, intervalMs);
    return () => clearInterval(id);
  }, [testimonials.length, intervalMs]);

  if (!testimonials.length) return null;
  const t = testimonials[active];

  return (
    <div>
      <div className="rounded-2xl border border-[#f5f5f5] bg-white p-5 shadow-sm">
        <div className="flex items-start gap-3">
          <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-blue-50 text-2xl">
            {t.avatarEmoji}
          </div>
          <div className="min-w-0 flex-1">
            <p className="text-sm font-bold text-zinc-900">{t.name}</p>
            <p className="text-xs text-zinc-500">
              {t.petEmoji} {t.pet}
            </p>
            <div className="mt-1 flex gap-0.5 text-amber-500">
              {Array.from({ length: 5 }).map((_, i) => (
                <span key={i} className={i < t.rating ? "" : "opacity-30"}>
                  ★
                </span>
              ))}
            </div>
          </div>
        </div>
        <p className="mt-4 text-sm leading-relaxed text-zinc-700">&ldquo;{t.quote}&rdquo;</p>
      </div>

      <div className="mt-3 flex justify-center gap-1.5">
        {testimonials.map((_, i) => (
          <button
            key={i}
            onClick={() => setActive(i)}
            aria-label={`Testimoni ${i + 1}`}
            className={`h-1.5 rounded-full transition-all ${
              i === active ? "w-6 bg-blue-500" : "w-1.5 bg-zinc-300"
            }`}
          />
        ))}
      </div>
    </div>
  );
}
