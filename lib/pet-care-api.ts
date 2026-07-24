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
};

export function validateCarePayload(
  body: unknown,
): { data: ValidatedCarePayload } | { error: string } {
  if (typeof body !== "object" || body === null) {
    return { error: "Payload tidak valid." };
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

  return {
    data: {
      category,
      doneAt: parsedDone,
      note: trimmedNote || null,
      nextDueAt: parsedNext,
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
