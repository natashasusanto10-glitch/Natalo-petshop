type SchedulableSlide = {
  activeFrom?: string;
  activeUntil?: string;
};

export function filterActiveSlides<T extends SchedulableSlide>(slides: T[], now = new Date()) {
  if (!Array.isArray(slides)) return [];

  return slides.filter((slide) => {
    if (slide.activeFrom) {
      const from = new Date(slide.activeFrom);
      if (now < from) return false;
    }

    if (slide.activeUntil) {
      const until = new Date(slide.activeUntil);
      until.setHours(23, 59, 59, 999);
      if (now > until) return false;
    }

    return true;
  });
}
