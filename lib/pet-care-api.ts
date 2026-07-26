export const CARE_CATEGORIES = new Set([
  "grooming",
  "deworm",
  "flea",
  "vaccine",
  "vet",
  "other",
]);

const MAX_NOTE_LENGTH = 200;

export type ValidatedCarePayload = {
  category: string;
  doneAt: Date;
  note: string | null;
  nextDueAt: Date | null;
  productId: string | null;
  brandText: string | null;
  dosageNote: string | null;
  weightKg: number | null;
  place: string | null;
  vaccineName: string | null;
  complaint: string | null;
};

export function validateCarePayload(
  body: unknown,
): { data: ValidatedCarePayload } | { error: string } {
  if (typeof body !== "object" || body === null) {
    return { error: "Data perawatan tidak terkirim dengan benar. Coba ulangi." };
  }
  const { category, doneAt, note, nextDueAt } = body as Record<string, unknown>;

  if (typeof category !== "string" || !CARE_CATEGORIES.has(category)) {
    return { error: "Jenis perawatan tidak valid." };
  }

  if (typeof doneAt !== "string" || !doneAt.trim()) {
    return { error: "Tanggal perawatan tidak valid." };
  }
  const parsedDone = new Date(doneAt);
  if (Number.isNaN(parsedDone.getTime())) {
    return { error: "Tanggal perawatan tidak valid." };
  }

  const trimmedNote = typeof note === "string" ? note.trim() : "";
  if (trimmedNote.length > MAX_NOTE_LENGTH) {
    return { error: `Catatan maksimal ${MAX_NOTE_LENGTH} karakter.` };
  }

  let parsedNext: Date | null = null;
  if (typeof nextDueAt === "string" && nextDueAt.trim()) {
    const parsed = new Date(nextDueAt);
    if (Number.isNaN(parsed.getTime())) {
      return { error: "Jadwal berikutnya tidak valid." };
    }
    if (parsed.getTime() <= parsedDone.getTime()) {
      return { error: "Jadwal berikutnya harus setelah tanggal perawatan." };
    }
    parsedNext = parsed;
  }

  const b = body as Record<string, unknown>;
  const str = (v: unknown): string | null => {
    if (typeof v !== "string") return null;
    const t = v.trim();
    return t ? t : null;
  };

  let weightKg: number | null = null;
  if (b.weightKg !== undefined && b.weightKg !== null && b.weightKg !== "") {
    const w = typeof b.weightKg === "number" ? b.weightKg : Number(b.weightKg);
    if (Number.isNaN(w) || w <= 0 || w > 200) {
      return { error: "Berat badan tidak valid." };
    }
    weightKg = w;
  }

  return {
    data: {
      category,
      doneAt: parsedDone,
      note: trimmedNote || null,
      nextDueAt: parsedNext,
      productId: str(b.productId),
      brandText: str(b.brandText),
      dosageNote: str(b.dosageNote),
      weightKg,
      place: str(b.place),
      vaccineName: str(b.vaccineName),
      complaint: str(b.complaint),
    },
  };
}

export type CareRow = {
  id: string;
  category: string;
  doneAt: Date;
  nextDueAt: Date | null;
};

export type UpcomingSchedule = {
  recordId: string;
  category: string;
  nextDueAt: Date;
};

/**
 * A record's nextDueAt is an active schedule only if no other record of the
 * same category has doneAt >= this record's doneAt. Returns one active
 * schedule per category, sorted by nextDueAt ascending.
 */
export function computeUpcoming(records: CareRow[]): UpcomingSchedule[] {
  const out: UpcomingSchedule[] = [];
  for (const rec of records) {
    if (!rec.nextDueAt) continue;
    const superseded = records.some(
      (other) =>
        other.id !== rec.id &&
        other.category === rec.category &&
        other.doneAt.getTime() >= rec.doneAt.getTime(),
    );
    if (superseded) continue;
    out.push({ recordId: rec.id, category: rec.category, nextDueAt: rec.nextDueAt });
  }
  out.sort((a, b) => a.nextDueAt.getTime() - b.nextDueAt.getTime());
  return out;
}
