# Anabulku Tahap 3 — Perawatan Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-pet care records (riwayat) + optional next-due schedules with in-app overdue/soon status, surfaced across the Anabulku list, pet profile, a new care page, and a new care form.

**Architecture:** New `PetCareRecord` Prisma table (one-to-many under `Pet`, cascade delete) plus three static health fields on `Pet`. A pure server-side lib computes "upcoming" schedules via a supersede rule. Three App-Router endpoints (`GET`/`POST` list, `DELETE` one) mirror the existing pets routes' auth/ownership pattern; the pets-list route gains `careCount` + `nearestDue`. Flutter adds a `PetCareRecord` model, care service methods, a local-only photo store (path_provider), and 4 UI surfaces reusing existing Anabulku widgets and NataloWeight/NataloColors tokens exactly.

**Tech Stack:** Next.js App Router + Prisma (PostgreSQL), Flutter (Dart), existing `apiClient`/`AppToast`/`NataloPawRefreshIndicator`/`ProfilePhotoPickerScreen` infrastructure.

## Global Constraints

- Auth: every care route calls `const session = await getSession("CUSTOMER");` → `if (!session) return 401`; user id is `session.sub`. Ownership: verify pet via `prisma.pet.findFirst({ where: { id, userId: session.sub } })` (404 `{ error: "Pet tidak ditemukan." }`) BEFORE any care read/write.
- Dynamic route params are async: `{ params }: { params: Promise<{ id: string }> }` then `const { id } = await params;`.
- Care categories (fixed set, priority order): `grooming`, `deworm`, `flea`, `vaccine`, `vet`, `other`. Label order in UI: Grooming, Obat Cacing, Obat Kutu, Vaksin, Periksa Dokter, Lainnya.
- Migrations: nullable columns use `ADD COLUMN IF NOT EXISTS`; new table uses `CREATE TABLE IF NOT EXISTS` + `CREATE INDEX IF NOT EXISTS`. Folder name `YYYYMMDDHHMMSS_snake_case`.
- Field limits: `note` max 200, `allergy` max 100, `healthNote` max 150. Trim; empty → null.
- Supersede rule: a record's `nextDueAt` is an ACTIVE schedule only if no other record of the SAME category has `doneAt >= that record's doneAt`. "Upcoming" = one active schedule per category, sorted `nextDueAt` asc.
- Status thresholds (compare date-only, local): `nextDueAt < today` → **overdue** (red, "Terlambat N hari", banner label "SUDAH LEWAT JADWAL"); `0..14 days` → **soon** (blue, "N hari lagi" / "Besok" / "Hari ini"); `> 14 days` → **normal** (neutral, date only).
- Flutter tokens are LOCKED to existing values: `NataloWeight.body`=w400, `NataloWeight.strong`=w600; `NataloColors.primary`=#1E5FBF, `primarySoft`=#EEF4FF, `grey400`=#9CA3AF, `danger`=#EF4444, `dangerSoft`=#FEF2F2, `dangerDark`=#DC2626. AppBar uses global `appBarTheme` only (no title override). Page horizontal padding = 20. No new font sizes/weights/radii outside the spec's token table.
- Flutter service mutations must call `readOnlyMode.assertWritable('<op>')` first (throws `ReadOnlyModeException`). All HTTP via `apiClient` (never raw `http`). Toasts via `AppToast.show(context, msg, kind: ToastKind.*)` — never `ScaffoldMessenger`.
- Care photos are LOCAL ONLY: after a successful POST, copy compressed jpg to `${ApplicationDocumentsDirectory}/pet_care/{recordId}.jpg`. Server has no photo field. Missing file → no error, just no thumbnail.
- Work on a branch off `main` (this is a shared checkout — see standing worktree guidance). Do NOT commit to `main` directly for code; open a PR at the end.

---

## File Structure

**Backend (primary checkout `C:\Users\USER\Desktop\natalopetshopflutter`):**
- Modify: `prisma/schema.prisma` — add `PetCareRecord` model + 3 `Pet` fields + back-relation.
- Create: `prisma/migrations/20260724020000_add_pet_care_records/migration.sql`.
- Create: `lib/pet-care-api.ts` — `CARE_CATEGORIES`, `validateCarePayload`, `computeUpcoming`.
- Modify: `lib/pets-api.ts` — extend `validatePetPayload` with `sterilized`/`allergy`/`healthNote`.
- Create: `app/api/member/pets/[id]/care/route.ts` — `GET` + `POST`.
- Create: `app/api/member/pets/[id]/care/[recordId]/route.ts` — `DELETE`.
- Modify: `app/api/member/pets/route.ts` — add `careCount` + `nearestDue` to list.
- Create tests: `lib/__tests__/pet-care-api.test.ts`.

**Flutter (`flutter_app/`):**
- Create: `lib/models/pet_care_record.dart` — `PetCareCategory` enum + `PetCareRecord` + `PetSchedule`.
- Modify: `lib/models/pet.dart` — add `sterilized`/`allergy`/`healthNote`/`careCount`/`nearestDue`.
- Modify: `lib/services/pet_service.dart` — `fetchCare`/`createCare`/`deleteCare`; extend `updatePet`/`createPet`.
- Create: `lib/services/pet_care_photo_store.dart` — local photo save/get/delete.
- Create: `lib/screens/pet_care_screen.dart` — care page.
- Create: `lib/screens/pet_care_form_screen.dart` — record form.
- Modify: `lib/screens/pet_profile_screen.dart` — "Perawatan" section + health rows.
- Modify: `lib/screens/anabulku_screen.dart` — schedule chip + "Jadwal Terdekat" section.
- Modify: `lib/screens/pet_form_screen.dart` — health fields.
- Create tests: `test/pet_care_status_test.dart`, `test/pet_care_screen_test.dart`.

---

## Task 1: Prisma schema + migration (PetCareRecord + Pet health fields)

**Files:**
- Modify: `prisma/schema.prisma` (Pet model ~lines 1112-1130; add new model after it)
- Create: `prisma/migrations/20260724020000_add_pet_care_records/migration.sql`

**Interfaces:**
- Produces: `PetCareRecord` table (`id`, `petId`, `category`, `doneAt`, `note?`, `nextDueAt?`, `createdAt`); `Pet.sterilized?` (Boolean), `Pet.allergy?` (String), `Pet.healthNote?` (String), `Pet.careRecords PetCareRecord[]`.

- [ ] **Step 1: Add 3 health fields + back-relation to `Pet` model**

In `prisma/schema.prisma`, inside `model Pet { ... }`, add after the `bio` line and before `vaccineReminderAt`:

```prisma
  sterilized         Boolean?
  allergy            String?
  healthNote         String?
```

And add the back-relation before the closing `}` (after `updatedAt`, before `@@index`):

```prisma
  careRecords        PetCareRecord[]
```

- [ ] **Step 2: Add the `PetCareRecord` model**

Immediately after the `Pet` model's closing brace, add:

```prisma
model PetCareRecord {
  id        String    @id @default(cuid())
  petId     String
  pet       Pet       @relation(fields: [petId], references: [id], onDelete: Cascade)
  category  String // grooming | deworm | flea | vaccine | vet | other
  doneAt    DateTime
  note      String?
  nextDueAt DateTime?
  createdAt DateTime  @default(now())

  @@index([petId, doneAt])
}
```

- [ ] **Step 3: Write the migration SQL**

Create `prisma/migrations/20260724020000_add_pet_care_records/migration.sql`:

```sql
ALTER TABLE "Pet" ADD COLUMN IF NOT EXISTS "sterilized" BOOLEAN;
ALTER TABLE "Pet" ADD COLUMN IF NOT EXISTS "allergy" TEXT;
ALTER TABLE "Pet" ADD COLUMN IF NOT EXISTS "healthNote" TEXT;

CREATE TABLE IF NOT EXISTS "PetCareRecord" (
    "id" TEXT NOT NULL,
    "petId" TEXT NOT NULL,
    "category" TEXT NOT NULL,
    "doneAt" TIMESTAMP(3) NOT NULL,
    "note" TEXT,
    "nextDueAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "PetCareRecord_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "PetCareRecord_petId_doneAt_idx" ON "PetCareRecord"("petId", "doneAt");

DO $$ BEGIN
    ALTER TABLE "PetCareRecord" ADD CONSTRAINT "PetCareRecord_petId_fkey" FOREIGN KEY ("petId") REFERENCES "Pet"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN null;
END $$;
```

- [ ] **Step 4: Regenerate Prisma client + verify schema is valid**

Run: `npx prisma generate`
Expected: "Generated Prisma Client" with no schema validation errors.

- [ ] **Step 5: Commit**

```bash
git add prisma/schema.prisma prisma/migrations/20260724020000_add_pet_care_records/
git commit -m "feat(db): PetCareRecord table + Pet health fields (Anabulku Tahap 3)"
```

---

## Task 2: Care validation + upcoming computation lib

**Files:**
- Create: `lib/pet-care-api.ts`
- Test: `lib/__tests__/pet-care-api.test.ts`

**Interfaces:**
- Consumes: nothing (pure functions).
- Produces:
  - `export const CARE_CATEGORIES: Set<string>` = {grooming, deworm, flea, vaccine, vet, other}.
  - `export type ValidatedCarePayload = { category: string; doneAt: Date; note: string | null; nextDueAt: Date | null }`.
  - `export function validateCarePayload(body: unknown): { data: ValidatedCarePayload } | { error: string }`.
  - `export type CareRow = { id: string; category: string; doneAt: Date; nextDueAt: Date | null }`.
  - `export type UpcomingSchedule = { recordId: string; category: string; nextDueAt: Date }`.
  - `export function computeUpcoming(records: CareRow[]): UpcomingSchedule[]` (sorted `nextDueAt` asc).

- [ ] **Step 1: Write failing tests**

Create `lib/__tests__/pet-care-api.test.ts`:

```ts
import { validateCarePayload, computeUpcoming, CARE_CATEGORIES } from "@/lib/pet-care-api";

describe("validateCarePayload", () => {
  it("rejects non-object", () => {
    expect(validateCarePayload(null)).toEqual({ error: "Payload tidak valid." });
  });
  it("rejects unknown category", () => {
    expect(validateCarePayload({ category: "spa", doneAt: "2026-07-01" }))
      .toEqual({ error: "Jenis perawatan tidak valid." });
  });
  it("rejects missing/invalid doneAt", () => {
    expect(validateCarePayload({ category: "grooming", doneAt: "bogus" }))
      .toEqual({ error: "Tanggal perawatan tidak valid." });
  });
  it("rejects note over 200 chars", () => {
    const r = validateCarePayload({ category: "grooming", doneAt: "2026-07-01", note: "x".repeat(201) });
    expect(r).toEqual({ error: "Catatan maksimal 200 karakter." });
  });
  it("rejects nextDueAt not after doneAt", () => {
    const r = validateCarePayload({ category: "grooming", doneAt: "2026-07-10", nextDueAt: "2026-07-10" });
    expect(r).toEqual({ error: "Jadwal berikutnya harus setelah tanggal perawatan." });
  });
  it("accepts a full valid payload and trims note", () => {
    const r = validateCarePayload({ category: "flea", doneAt: "2026-07-01", note: "  Frontline  ", nextDueAt: "2026-08-01" });
    expect("data" in r && r.data.category).toBe("flea");
    expect("data" in r && r.data.note).toBe("Frontline");
    expect("data" in r && r.data.nextDueAt instanceof Date).toBe(true);
  });
  it("maps empty note to null", () => {
    const r = validateCarePayload({ category: "vet", doneAt: "2026-07-01", note: "   " });
    expect("data" in r && r.data.note).toBeNull();
  });
  it("exposes all 6 categories", () => {
    expect([...CARE_CATEGORIES].sort()).toEqual(["deworm","flea","grooming","other","vaccine","vet"]);
  });
});

describe("computeUpcoming (supersede rule)", () => {
  const d = (s: string) => new Date(s);
  it("returns the schedule when not superseded", () => {
    const rows = [{ id: "a", category: "grooming", doneAt: d("2026-06-01"), nextDueAt: d("2026-09-01") }];
    expect(computeUpcoming(rows)).toEqual([{ recordId: "a", category: "grooming", nextDueAt: d("2026-09-01") }]);
  });
  it("supersedes an older schedule when a newer same-category record exists", () => {
    const rows = [
      { id: "a", category: "grooming", doneAt: d("2026-06-01"), nextDueAt: d("2026-09-01") },
      { id: "b", category: "grooming", doneAt: d("2026-07-01"), nextDueAt: null },
    ];
    expect(computeUpcoming(rows)).toEqual([]);
  });
  it("keeps schedules from different categories independent", () => {
    const rows = [
      { id: "a", category: "grooming", doneAt: d("2026-06-01"), nextDueAt: d("2026-09-01") },
      { id: "b", category: "flea", doneAt: d("2026-06-15"), nextDueAt: d("2026-07-15") },
    ];
    const out = computeUpcoming(rows);
    expect(out.map(x => x.category)).toEqual(["flea", "grooming"]);
  });
  it("ignores records without nextDueAt", () => {
    const rows = [{ id: "a", category: "vet", doneAt: d("2026-06-01"), nextDueAt: null }];
    expect(computeUpcoming(rows)).toEqual([]);
  });
});
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `npx jest lib/__tests__/pet-care-api.test.ts`
Expected: FAIL — "Cannot find module '@/lib/pet-care-api'".

- [ ] **Step 3: Implement the lib**

Create `lib/pet-care-api.ts`:

```ts
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
```

- [ ] **Step 4: Run tests, verify pass**

Run: `npx jest lib/__tests__/pet-care-api.test.ts`
Expected: PASS (all cases).

- [ ] **Step 5: Commit**

```bash
git add lib/pet-care-api.ts lib/__tests__/pet-care-api.test.ts
git commit -m "feat(api): pet-care validation + supersede/upcoming lib"
```

---

## Task 3: Care API routes (GET/POST list, DELETE one)

**Files:**
- Create: `app/api/member/pets/[id]/care/route.ts`
- Create: `app/api/member/pets/[id]/care/[recordId]/route.ts`

**Interfaces:**
- Consumes: `getSession` (`@/lib/auth`), `prisma` (`@/lib/prisma`), `validateCarePayload`/`computeUpcoming` (`@/lib/pet-care-api`).
- Produces:
  - `GET /api/member/pets/{id}/care` → `{ records: Array<{id,category,doneAt,note,nextDueAt,createdAt}>, upcoming: Array<{recordId,category,nextDueAt}> }` (records `doneAt` desc).
  - `POST /api/member/pets/{id}/care` (body `{category,doneAt,note?,nextDueAt?}`) → `{ record }` status 201.
  - `DELETE /api/member/pets/{id}/care/{recordId}` → `{ ok: true }`.

- [ ] **Step 1: Write the list route (GET + POST)**

Create `app/api/member/pets/[id]/care/route.ts`:

```ts
import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import { validateCarePayload, computeUpcoming } from "@/lib/pet-care-api";

async function getOwnedPet(id: string, userId: string) {
  return prisma.pet.findFirst({ where: { id, userId } });
}

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json({ error: "Login member dulu." }, { status: 401 });
  }
  const { id } = await params;
  const pet = await getOwnedPet(id, session.sub);
  if (!pet) {
    return NextResponse.json({ error: "Pet tidak ditemukan." }, { status: 404 });
  }

  const records = await prisma.petCareRecord.findMany({
    where: { petId: id },
    orderBy: { doneAt: "desc" },
  });

  const upcoming = computeUpcoming(
    records.map((r) => ({
      id: r.id,
      category: r.category,
      doneAt: r.doneAt,
      nextDueAt: r.nextDueAt,
    })),
  );

  return NextResponse.json({ records, upcoming });
}

export async function POST(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json({ error: "Login member dulu." }, { status: 401 });
  }
  const { id } = await params;
  const pet = await getOwnedPet(id, session.sub);
  if (!pet) {
    return NextResponse.json({ error: "Pet tidak ditemukan." }, { status: 404 });
  }

  const body = await request.json().catch(() => null);
  const validated = validateCarePayload(body);
  if ("error" in validated) {
    return NextResponse.json({ error: validated.error }, { status: 400 });
  }

  const record = await prisma.petCareRecord.create({
    data: { ...validated.data, petId: id },
  });

  return NextResponse.json({ record }, { status: 201 });
}
```

- [ ] **Step 2: Write the delete route**

Create `app/api/member/pets/[id]/care/[recordId]/route.ts`:

```ts
import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";

export async function DELETE(
  _request: Request,
  { params }: { params: Promise<{ id: string; recordId: string }> },
) {
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json({ error: "Login member dulu." }, { status: 401 });
  }
  const { id, recordId } = await params;

  const pet = await prisma.pet.findFirst({
    where: { id, userId: session.sub },
  });
  if (!pet) {
    return NextResponse.json({ error: "Pet tidak ditemukan." }, { status: 404 });
  }

  const deleted = await prisma.petCareRecord.deleteMany({
    where: { id: recordId, petId: id },
  });
  if (deleted.count === 0) {
    return NextResponse.json({ error: "Catatan tidak ditemukan." }, { status: 404 });
  }

  return NextResponse.json({ ok: true });
}
```

Note: `deleteMany` scoped by `{ id: recordId, petId: id }` guarantees a caller can only delete a record belonging to their own (already ownership-verified) pet.

- [ ] **Step 3: Typecheck**

Run: `npx tsc --noEmit`
Expected: no errors in the two new files.

- [ ] **Step 4: Commit**

```bash
git add app/api/member/pets/[id]/care/
git commit -m "feat(api): pet care records GET/POST/DELETE routes"
```

---

## Task 4: Extend `validatePetPayload` with health fields

**Files:**
- Modify: `lib/pets-api.ts`
- Test: `tests/pets-api-health.test.ts`

> **Repo test convention (confirmed):** this project has NO jest. Tests live in `tests/` and run via `tsx --test tests/*.test.ts` using `node:test` + `node:assert/strict` with a `@/` alias to the repo root. Write the test in that style (see below), NOT jest.

**Interfaces:**
- Produces: `ValidatedPetPayload` gains `sterilized: boolean | null`, `allergy: string | null`, `healthNote: string | null`.

- [ ] **Step 1: Write failing tests**

Create `tests/pets-api-health.test.ts`:

```ts
import assert from "node:assert/strict";
import test, { describe } from "node:test";
import { validatePetPayload } from "@/lib/pets-api";

const base = { name: "Milo", type: "Kucing" };

describe("validatePetPayload health fields", () => {
  test("defaults health fields to null when absent", () => {
    const r = validatePetPayload(base);
    assert.ok("data" in r);
    assert.equal(r.data.sterilized, null);
    assert.equal(r.data.allergy, null);
    assert.equal(r.data.healthNote, null);
  });
  test("accepts sterilized boolean", () => {
    const r = validatePetPayload({ ...base, sterilized: true });
    assert.ok("data" in r);
    assert.equal(r.data.sterilized, true);
  });
  test("trims allergy and rejects over 100 chars", () => {
    assert.deepEqual(
      validatePetPayload({ ...base, allergy: "x".repeat(101) }),
      { error: "Alergi maksimal 100 karakter." },
    );
    const r = validatePetPayload({ ...base, allergy: "  Ayam  " });
    assert.ok("data" in r);
    assert.equal(r.data.allergy, "Ayam");
  });
  test("rejects healthNote over 150 chars", () => {
    assert.deepEqual(
      validatePetPayload({ ...base, healthNote: "x".repeat(151) }),
      { error: "Kondisi khusus maksimal 150 karakter." },
    );
  });
});
```

- [ ] **Step 2: Run tests, verify fail**

Run: `npx jest lib/__tests__/pets-api-health.test.ts`
Expected: FAIL — `r.data.sterilized` is `undefined`, not `null`.

- [ ] **Step 3: Extend the constants, type, and function in `lib/pets-api.ts`**

Add constants near the other `MAX_*` (after `MAX_BIO_LENGTH`):

```ts
const MAX_ALLERGY_LENGTH = 100;
const MAX_HEALTH_NOTE_LENGTH = 150;
```

Extend the `ValidatedPetPayload` type — add three fields after `bio`:

```ts
  sterilized: boolean | null;
  allergy: string | null;
  healthNote: string | null;
```

In `validatePetPayload`, extend the destructure line to include the new keys:

```ts
  const { name, type, breed, birthDate, gender, bio, sterilized, allergy, healthNote } =
    body as Record<string, unknown>;
```

Before the final `return`, add validation:

```ts
  let parsedSterilized: boolean | null = null;
  if (typeof sterilized === "boolean") {
    parsedSterilized = sterilized;
  }
  const trimmedAllergy = typeof allergy === "string" ? allergy.trim() : "";
  if (trimmedAllergy.length > MAX_ALLERGY_LENGTH) {
    return { error: `Alergi maksimal ${MAX_ALLERGY_LENGTH} karakter.` };
  }
  const trimmedHealthNote = typeof healthNote === "string" ? healthNote.trim() : "";
  if (trimmedHealthNote.length > MAX_HEALTH_NOTE_LENGTH) {
    return { error: `Kondisi khusus maksimal ${MAX_HEALTH_NOTE_LENGTH} karakter.` };
  }
```

Extend the returned `data` object (after `bio: trimmedBio || null,`):

```ts
      sterilized: parsedSterilized,
      allergy: trimmedAllergy || null,
      healthNote: trimmedHealthNote || null,
```

- [ ] **Step 4: Run tests, verify pass**

Run: `npx jest lib/__tests__/pets-api-health.test.ts`
Expected: PASS. Also run existing pets tests if any: `npx jest lib/__tests__/pets-api` — all green.

- [ ] **Step 5: Commit**

```bash
git add lib/pets-api.ts lib/__tests__/pets-api-health.test.ts
git commit -m "feat(api): validate pet sterilized/allergy/healthNote fields"
```

---

## Task 5: Pets list route — add `careCount` + `nearestDue`

**Files:**
- Modify: `app/api/member/pets/route.ts` (GET handler)

**Interfaces:**
- Consumes: `computeUpcoming` (`@/lib/pet-care-api`).
- Produces: each pet in `GET /api/member/pets` list gains `careCount: number` and `nearestDue: { category: string; nextDueAt: string } | null` (the single soonest active schedule for that pet, or null).

- [ ] **Step 1: Rewrite the GET handler to aggregate care per pet**

Replace the body of `GET()` in `app/api/member/pets/route.ts` with (keep imports; add `computeUpcoming` import):

```ts
import { computeUpcoming } from "@/lib/pet-care-api";
```

```ts
export async function GET() {
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json({ error: "Login member dulu." }, { status: 401 });
  }

  const pets = await prisma.pet.findMany({
    where: { userId: session.sub },
    orderBy: { createdAt: "asc" },
    include: {
      careRecords: {
        select: { id: true, category: true, doneAt: true, nextDueAt: true },
      },
    },
  });

  const shaped = pets.map((pet) => {
    const upcoming = computeUpcoming(pet.careRecords);
    const nearest = upcoming[0] ?? null;
    const { careRecords, ...rest } = pet;
    return {
      ...rest,
      careCount: careRecords.length,
      nearestDue: nearest
        ? { category: nearest.category, nextDueAt: nearest.nextDueAt }
        : null,
    };
  });

  return NextResponse.json({ pets: shaped });
}
```

Note: `careRecords` is stripped from the response (only the aggregates ship). Existing `pet` fields remain intact via `...rest`, so the Flutter `Pet.fromJson` keeps working.

- [ ] **Step 2: Typecheck**

Run: `npx tsc --noEmit`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add app/api/member/pets/route.ts
git commit -m "feat(api): pets list includes careCount + nearestDue"
```

---

## Task 6: Flutter `PetCareRecord` model + category enum

**Files:**
- Create: `flutter_app/lib/models/pet_care_record.dart`
- Test: `flutter_app/test/pet_care_status_test.dart`

**Interfaces:**
- Produces:
  - `enum PetCareCategory { grooming, deworm, flea, vaccine, vet, other }` with `apiValue`, `label`, `fromApi(String?)`, and `static const List<PetCareCategory> ordered` (priority order).
  - `class PetCareRecord { String id; PetCareCategory category; DateTime doneAt; String? note; DateTime? nextDueAt; }` + `fromJson`.
  - `class PetSchedule { String recordId; PetCareCategory category; DateTime nextDueAt; }` + `fromJson`.
  - `enum ScheduleStatus { overdue, soon, normal }` + `ScheduleStatus scheduleStatusOf(DateTime due, {DateTime? now})` + `int daysUntil(DateTime due, {DateTime? now})` + `String scheduleCountdownLabel(DateTime due, {DateTime? now})` (returns "Terlambat N hari" / "Hari ini" / "Besok" / "N hari lagi").

- [ ] **Step 1: Write failing tests for status helpers**

Create `flutter_app/test/pet_care_status_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop/models/pet_care_record.dart';

void main() {
  final now = DateTime(2026, 7, 24);

  group('scheduleStatusOf', () {
    test('past date is overdue', () {
      expect(scheduleStatusOf(DateTime(2026, 7, 10), now: now), ScheduleStatus.overdue);
    });
    test('today is soon', () {
      expect(scheduleStatusOf(DateTime(2026, 7, 24), now: now), ScheduleStatus.soon);
    });
    test('within 14 days is soon', () {
      expect(scheduleStatusOf(DateTime(2026, 8, 5), now: now), ScheduleStatus.soon);
    });
    test('beyond 14 days is normal', () {
      expect(scheduleStatusOf(DateTime(2026, 8, 20), now: now), ScheduleStatus.normal);
    });
  });

  group('scheduleCountdownLabel', () {
    test('overdue', () {
      expect(scheduleCountdownLabel(DateTime(2026, 7, 10), now: now), 'Terlambat 14 hari');
    });
    test('today', () {
      expect(scheduleCountdownLabel(DateTime(2026, 7, 24), now: now), 'Hari ini');
    });
    test('tomorrow', () {
      expect(scheduleCountdownLabel(DateTime(2026, 7, 25), now: now), 'Besok');
    });
    test('n days', () {
      expect(scheduleCountdownLabel(DateTime(2026, 7, 30), now: now), '6 hari lagi');
    });
  });

  group('PetCareCategory', () {
    test('ordered list is priority order', () {
      expect(PetCareCategory.ordered.map((c) => c.apiValue).toList(),
          ['grooming', 'deworm', 'flea', 'vaccine', 'vet', 'other']);
    });
    test('fromApi maps and defaults to other', () {
      expect(PetCareCategory.fromApi('flea'), PetCareCategory.flea);
      expect(PetCareCategory.fromApi('bogus'), PetCareCategory.other);
    });
    test('labels are Indonesian', () {
      expect(PetCareCategory.deworm.label, 'Obat Cacing');
      expect(PetCareCategory.vet.label, 'Periksa Dokter');
    });
  });
}
```

- [ ] **Step 2: Run test, verify fail**

Run: `cd flutter_app && flutter test test/pet_care_status_test.dart`
Expected: FAIL — target of URI doesn't exist (`pet_care_record.dart`).

- [ ] **Step 3: Implement the model**

Create `flutter_app/lib/models/pet_care_record.dart`:

```dart
import 'package:flutter/material.dart';

/// Kategori perawatan — WAJIB sinkron dengan `CARE_CATEGORIES` di
/// `lib/pet-care-api.ts` (backend). Urutan `ordered` = prioritas UI.
enum PetCareCategory {
  grooming,
  deworm,
  flea,
  vaccine,
  vet,
  other;

  static const List<PetCareCategory> ordered = [
    PetCareCategory.grooming,
    PetCareCategory.deworm,
    PetCareCategory.flea,
    PetCareCategory.vaccine,
    PetCareCategory.vet,
    PetCareCategory.other,
  ];

  static PetCareCategory fromApi(String? value) {
    for (final c in PetCareCategory.values) {
      if (c.name == value) return c;
    }
    return PetCareCategory.other;
  }

  String get apiValue => name;

  String get label {
    switch (this) {
      case PetCareCategory.grooming:
        return 'Grooming';
      case PetCareCategory.deworm:
        return 'Obat Cacing';
      case PetCareCategory.flea:
        return 'Obat Kutu';
      case PetCareCategory.vaccine:
        return 'Vaksin';
      case PetCareCategory.vet:
        return 'Periksa Dokter';
      case PetCareCategory.other:
        return 'Lainnya';
    }
  }

  IconData get icon {
    switch (this) {
      case PetCareCategory.grooming:
        return Icons.bathtub_outlined;
      case PetCareCategory.deworm:
        return Icons.medication_outlined;
      case PetCareCategory.flea:
        return Icons.pest_control_outlined;
      case PetCareCategory.vaccine:
        return Icons.vaccines_outlined;
      case PetCareCategory.vet:
        return Icons.medical_services_outlined;
      case PetCareCategory.other:
        return Icons.more_horiz_rounded;
    }
  }
}

class PetCareRecord {
  final String id;
  final PetCareCategory category;
  final DateTime doneAt;
  final String? note;
  final DateTime? nextDueAt;

  const PetCareRecord({
    required this.id,
    required this.category,
    required this.doneAt,
    this.note,
    this.nextDueAt,
  });

  factory PetCareRecord.fromJson(Map<String, dynamic> json) {
    final next = json['nextDueAt'] as String?;
    return PetCareRecord(
      id: json['id'] as String? ?? '',
      category: PetCareCategory.fromApi(json['category'] as String?),
      doneAt: DateTime.tryParse(json['doneAt'] as String? ?? '') ??
          DateTime.now(),
      note: json['note'] as String?,
      nextDueAt: next == null ? null : DateTime.tryParse(next),
    );
  }
}

class PetSchedule {
  final String recordId;
  final PetCareCategory category;
  final DateTime nextDueAt;

  const PetSchedule({
    required this.recordId,
    required this.category,
    required this.nextDueAt,
  });

  factory PetSchedule.fromJson(Map<String, dynamic> json) {
    return PetSchedule(
      recordId: json['recordId'] as String? ?? '',
      category: PetCareCategory.fromApi(json['category'] as String?),
      nextDueAt:
          DateTime.tryParse(json['nextDueAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

enum ScheduleStatus { overdue, soon, normal }

/// Days from `now` (date-only) to `due` (date-only). Negative = overdue.
int daysUntil(DateTime due, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final target = DateTime(due.year, due.month, due.day);
  return target.difference(today).inDays;
}

ScheduleStatus scheduleStatusOf(DateTime due, {DateTime? now}) {
  final days = daysUntil(due, now: now);
  if (days < 0) return ScheduleStatus.overdue;
  if (days <= 14) return ScheduleStatus.soon;
  return ScheduleStatus.normal;
}

String scheduleCountdownLabel(DateTime due, {DateTime? now}) {
  final days = daysUntil(due, now: now);
  if (days < 0) return 'Terlambat ${-days} hari';
  if (days == 0) return 'Hari ini';
  if (days == 1) return 'Besok';
  return '$days hari lagi';
}
```

- [ ] **Step 4: Run test, verify pass**

Run: `cd flutter_app && flutter test test/pet_care_status_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/models/pet_care_record.dart flutter_app/test/pet_care_status_test.dart
git commit -m "feat(app): PetCareRecord model + schedule status helpers"
```

---

## Task 7: Extend Flutter `Pet` model with health + care aggregates

**Files:**
- Modify: `flutter_app/lib/models/pet.dart`

**Interfaces:**
- Produces: `Pet` gains `bool? sterilized`, `String? allergy`, `String? healthNote`, `int careCount`, `PetSchedule? nearestDue`; all wired through ctor, `fromJson`, `copyWith`.

- [ ] **Step 1: Add import + fields**

At top of `flutter_app/lib/models/pet.dart`, add:

```dart
import 'pet_care_record.dart';
```

In `class Pet`, add fields after `bio`:

```dart
  final bool? sterilized;
  final String? allergy;
  final String? healthNote;
  final int careCount;
  final PetSchedule? nearestDue;
```

- [ ] **Step 2: Extend the constructor**

Add to the `const Pet({...})` param list (after `this.bio,`):

```dart
    this.sterilized,
    this.allergy,
    this.healthNote,
    this.careCount = 0,
    this.nearestDue,
```

- [ ] **Step 3: Extend `fromJson`**

In `Pet.fromJson`, before the `return Pet(`, add:

```dart
    final nearestRaw = json['nearestDue'];
```

Add to the returned `Pet(...)` (after `bio: json['bio'] as String?,`):

```dart
      sterilized: json['sterilized'] as bool?,
      allergy: json['allergy'] as String?,
      healthNote: json['healthNote'] as String?,
      careCount: (json['careCount'] as num?)?.toInt() ?? 0,
      nearestDue: nearestRaw is Map<String, dynamic>
          ? PetSchedule(
              recordId: '',
              category: PetCareCategory.fromApi(nearestRaw['category'] as String?),
              nextDueAt: DateTime.tryParse(
                      nearestRaw['nextDueAt'] as String? ?? '') ??
                  DateTime.now(),
            )
          : null,
```

- [ ] **Step 4: Extend `copyWith`**

Add params to `copyWith({...})` (after `String? bio,`):

```dart
    bool? sterilized,
    String? allergy,
    String? healthNote,
    int? careCount,
    PetSchedule? nearestDue,
```

And in its returned `Pet(...)` (after `bio: bio ?? this.bio,`):

```dart
      sterilized: sterilized ?? this.sterilized,
      allergy: allergy ?? this.allergy,
      healthNote: healthNote ?? this.healthNote,
      careCount: careCount ?? this.careCount,
      nearestDue: nearestDue ?? this.nearestDue,
```

- [ ] **Step 5: Analyze**

Run: `cd flutter_app && flutter analyze lib/models/pet.dart`
Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
git add flutter_app/lib/models/pet.dart
git commit -m "feat(app): Pet model gains health fields + care aggregates"
```

---

## Task 8: Care service methods + pet health in create/update

**Files:**
- Modify: `flutter_app/lib/services/pet_service.dart`

**Interfaces:**
- Consumes: `apiClient`, `readOnlyMode`, `PetCareRecord`/`PetSchedule` models.
- Produces:
  - `Future<({List<PetCareRecord> records, List<PetSchedule> upcoming})> fetchCare(String petId)`.
  - `Future<PetCareRecord> createCare(String petId, {required PetCareCategory category, required DateTime doneAt, String? note, DateTime? nextDueAt})`.
  - `Future<void> deleteCare(String petId, String recordId)`.
  - `createPet`/`updatePet` gain `bool? sterilized, String? allergy, String? healthNote` params (conditional-spread into body).

- [ ] **Step 1: Add import**

At top of `flutter_app/lib/services/pet_service.dart`:

```dart
import '../models/pet_care_record.dart';
```

- [ ] **Step 2: Add care methods to the `PetService` class**

```dart
  Future<({List<PetCareRecord> records, List<PetSchedule> upcoming})> fetchCare(
      String petId) async {
    final data = await apiClient.getJson('/api/member/pets/$petId/care');
    final map = data as Map<String, dynamic>;
    final recordsRaw = map['records'];
    final upcomingRaw = map['upcoming'];
    final records = recordsRaw is List
        ? recordsRaw
            .whereType<Map<String, dynamic>>()
            .map(PetCareRecord.fromJson)
            .toList()
        : <PetCareRecord>[];
    final upcoming = upcomingRaw is List
        ? upcomingRaw
            .whereType<Map<String, dynamic>>()
            .map(PetSchedule.fromJson)
            .toList()
        : <PetSchedule>[];
    return (records: records, upcoming: upcoming);
  }

  Future<PetCareRecord> createCare(
    String petId, {
    required PetCareCategory category,
    required DateTime doneAt,
    String? note,
    DateTime? nextDueAt,
  }) async {
    readOnlyMode.assertWritable('createCare');
    final data = await apiClient.postJson(
      '/api/member/pets/$petId/care',
      body: {
        'category': category.apiValue,
        'doneAt': doneAt.toIso8601String(),
        if (note != null) 'note': note,
        if (nextDueAt != null) 'nextDueAt': nextDueAt.toIso8601String(),
      },
    );
    return PetCareRecord.fromJson((data as Map<String, dynamic>)['record']
        as Map<String, dynamic>);
  }

  Future<void> deleteCare(String petId, String recordId) async {
    readOnlyMode.assertWritable('deleteCare');
    await apiClient.deleteJson('/api/member/pets/$petId/care/$recordId');
  }
```

- [ ] **Step 3: Extend `createPet` and `updatePet` signatures + bodies**

Add these params to BOTH method signatures (after `String? bio,`):

```dart
    bool? sterilized,
    String? allergy,
    String? healthNote,
```

And add to BOTH request bodies (after `if (bio != null) 'bio': bio,`):

```dart
        if (sterilized != null) 'sterilized': sterilized,
        if (allergy != null) 'allergy': allergy,
        if (healthNote != null) 'healthNote': healthNote,
```

- [ ] **Step 4: Analyze**

Run: `cd flutter_app && flutter analyze lib/services/pet_service.dart`
Expected: No issues found.

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/services/pet_service.dart
git commit -m "feat(app): pet care service methods + health fields in create/update"
```

---

## Task 9: Local care-photo store (path_provider)

**Files:**
- Create: `flutter_app/lib/services/pet_care_photo_store.dart`

**Interfaces:**
- Consumes: `path_provider` (already a dependency).
- Produces: `class PetCarePhotoStore` with singleton `petCarePhotoStore`:
  - `Future<File> save(String recordId, String sourcePath)` — copies source into `pet_care/{recordId}.jpg`.
  - `Future<File?> get(String recordId)` — returns the file if it exists, else null.
  - `Future<void> delete(String recordId)` — removes it if present.

- [ ] **Step 1: Implement the store**

Create `flutter_app/lib/services/pet_care_photo_store.dart`:

```dart
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Menyimpan foto catatan perawatan LOKAL di HP (bukan server). File hidup di
/// folder privat app: `<AppDocuments>/pet_care/<recordId>.jpg`. Hilang saat
/// user ganti HP / reinstall — record tetap utuh tanpa error.
class PetCarePhotoStore {
  PetCarePhotoStore._();

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/pet_care');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  File _fileFor(Directory dir, String recordId) =>
      File('${dir.path}/$recordId.jpg');

  Future<File> save(String recordId, String sourcePath) async {
    final dir = await _dir();
    final dest = _fileFor(dir, recordId);
    return File(sourcePath).copy(dest.path);
  }

  Future<File?> get(String recordId) async {
    final dir = await _dir();
    final file = _fileFor(dir, recordId);
    return await file.exists() ? file : null;
  }

  Future<void> delete(String recordId) async {
    final dir = await _dir();
    final file = _fileFor(dir, recordId);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

final petCarePhotoStore = PetCarePhotoStore._();
```

- [ ] **Step 2: Analyze**

Run: `cd flutter_app && flutter analyze lib/services/pet_care_photo_store.dart`
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add flutter_app/lib/services/pet_care_photo_store.dart
git commit -m "feat(app): local-only care photo store"
```

---

## Task 10: Care form screen (Catat Perawatan)

**Files:**
- Create: `flutter_app/lib/screens/pet_care_form_screen.dart`

**Interfaces:**
- Consumes: `petService.createCare`, `petCarePhotoStore.save`, `ProfilePhotoPickerScreen.open`, `AppToast`, `NataloColors`, `NataloWeight`, `PetCareCategory`.
- Produces: `class PetCareFormScreen extends StatefulWidget { final String petId; }` — pops the created `PetCareRecord` on success, `null` on cancel.

- [ ] **Step 1: Implement the form screen**

Create `flutter_app/lib/screens/pet_care_form_screen.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/pet_care_record.dart';
import '../services/pet_care_photo_store.dart';
import '../services/pet_service.dart';
import '../theme/natalo_colors.dart';
import '../theme/natalo_text.dart';
import '../utils/api_exception.dart';
import '../utils/haptics.dart';
import '../utils/read_only_mode.dart';
import '../widgets/app_toast.dart';
import 'profile_photo_picker_screen.dart';

const _brandBlue = NataloColors.primary;

/// Form "Catat Perawatan" — pop `PetCareRecord` saat sukses, `null` saat batal.
class PetCareFormScreen extends StatefulWidget {
  final String petId;
  const PetCareFormScreen({super.key, required this.petId});

  @override
  State<PetCareFormScreen> createState() => _PetCareFormScreenState();
}

class _PetCareFormScreenState extends State<PetCareFormScreen> {
  PetCareCategory _category = PetCareCategory.grooming;
  DateTime _doneAt = DateTime.now();
  DateTime? _nextDueAt;
  final _noteController = TextEditingController();
  File? _pickedPhoto;
  bool _saving = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDoneDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _doneAt,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: _brandBlue,
            onPrimary: Colors.white,
            onSurface: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _doneAt = picked);
  }

  Future<void> _pickNextDate() async {
    final base = _doneAt;
    final picked = await showDatePicker(
      context: context,
      initialDate: _nextDueAt ?? base.add(const Duration(days: 30)),
      firstDate: base.add(const Duration(days: 1)),
      lastDate: DateTime(base.year + 5),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: _brandBlue,
            onPrimary: Colors.white,
            onSurface: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _nextDueAt = picked);
  }

  Future<void> _pickPhoto() async {
    AppHaptics.tap();
    final cropped =
        await ProfilePhotoPickerScreen.open(context, title: 'Foto perawatan');
    if (cropped != null) setState(() => _pickedPhoto = cropped);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final note = _noteController.text.trim();
      final record = await petService.createCare(
        widget.petId,
        category: _category,
        doneAt: _doneAt,
        note: note.isEmpty ? null : note,
        nextDueAt: _nextDueAt,
      );
      if (_pickedPhoto != null) {
        try {
          await petCarePhotoStore.save(record.id, _pickedPhoto!.path);
        } catch (_) {
          // Foto lokal gagal disimpan — record tetap sukses, jangan blokir.
        }
      }
      AppHaptics.success();
      if (!mounted) return;
      Navigator.of(context).pop(record);
      AppToast.show(context, 'Perawatan dicatat', kind: ToastKind.success);
    } on ReadOnlyModeException {
      if (!mounted) return;
      AppToast.show(context, 'Mode aman aktif, coba lagi nanti.',
          kind: ToastKind.warning);
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.show(context, e.message, kind: ToastKind.error);
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, 'Gagal menyimpan. Coba lagi.',
          kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dateFmt = _fmtDate(_doneAt);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Tutup',
        ),
        title: const Text('Catat Perawatan'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Simpan',
                    style: TextStyle(
                        fontWeight: NataloWeight.strong, color: _brandBlue)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        children: [
          const _Label('Jenis perawatan'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in PetCareCategory.ordered)
                _CategoryChip(
                  category: c,
                  selected: _category == c,
                  onTap: () => setState(() => _category = c),
                ),
            ],
          ),
          const SizedBox(height: 18),
          const _Label('Tanggal dilakukan'),
          const SizedBox(height: 6),
          _PickerField(
            icon: Icons.calendar_today_rounded,
            text: dateFmt,
            onTap: _pickDoneDate,
          ),
          const SizedBox(height: 18),
          const _Label('Foto (opsional)'),
          const SizedBox(height: 6),
          _PhotoField(picked: _pickedPhoto, onTap: _pickPhoto),
          const SizedBox(height: 18),
          const _Label('Catatan (opsional)'),
          const SizedBox(height: 6),
          TextField(
            controller: _noteController,
            maxLength: 200,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(
              filled: true,
              fillColor: cs.surface,
              hintText: 'Mis. Mandi + potong kuku',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const _Label('Jadwal berikutnya (opsional)'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _NextChip(
                label: '+1 bulan',
                selected: _isNext(const Duration(days: 30)),
                onTap: () => setState(() =>
                    _nextDueAt = _doneAt.add(const Duration(days: 30))),
              ),
              _NextChip(
                label: '+3 bulan',
                selected: _isNext(const Duration(days: 90)),
                onTap: () => setState(() =>
                    _nextDueAt = _doneAt.add(const Duration(days: 90))),
              ),
              _NextChip(
                label: _nextDueAt != null && !_isPreset()
                    ? _fmtDate(_nextDueAt!)
                    : 'Pilih tanggal',
                selected: _nextDueAt != null && !_isPreset(),
                onTap: _pickNextDate,
              ),
              if (_nextDueAt != null)
                _NextChip(
                  label: 'Hapus jadwal',
                  selected: false,
                  onTap: () => setState(() => _nextDueAt = null),
                ),
            ],
          ),
        ],
      ),
    );
  }

  bool _isPreset() =>
      _isNext(const Duration(days: 30)) || _isNext(const Duration(days: 90));

  bool _isNext(Duration d) {
    final n = _nextDueAt;
    if (n == null) return false;
    final expected = _doneAt.add(d);
    return n.year == expected.year &&
        n.month == expected.month &&
        n.day == expected.day;
  }
}

String _fmtDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(text,
        style: TextStyle(
            fontSize: 12,
            fontWeight: NataloWeight.body,
            color: cs.onSurfaceVariant));
  }
}

class _CategoryChip extends StatelessWidget {
  final PetCareCategory category;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryChip(
      {required this.category, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? (isDark
                    ? _brandBlue.withValues(alpha: 0.20)
                    : NataloColors.primarySoft)
                : Colors.transparent,
            border: Border.all(
                color: selected ? _brandBlue : cs.outlineVariant),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(category.icon,
                  size: 15,
                  color: selected ? _brandBlue : cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(category.label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: NataloWeight.strong,
                      color: selected ? _brandBlue : cs.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickerField extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;
  const _PickerField(
      {required this.icon, required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: cs.outlineVariant),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(text, style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoField extends StatelessWidget {
  final File? picked;
  final VoidCallback onTap;
  const _PhotoField({required this.picked, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (picked != null) {
      return Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(picked!,
                width: 64, height: 64, fit: BoxFit.cover),
          ),
          const SizedBox(width: 12),
          TextButton(onPressed: onTap, child: const Text('Ganti foto')),
        ],
      );
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: cs.outlineVariant),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Icon(Icons.add_a_photo_outlined,
                  size: 20, color: cs.onSurfaceVariant),
              const SizedBox(height: 4),
              Text('Tambah foto',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: NataloWeight.body,
                      color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NextChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _NextChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? (isDark
                    ? _brandBlue.withValues(alpha: 0.20)
                    : NataloColors.primarySoft)
                : Colors.transparent,
            border: Border.all(
                color: selected ? _brandBlue : cs.outlineVariant),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: NataloWeight.strong,
                  color: selected ? _brandBlue : cs.onSurfaceVariant)),
        ),
      ),
    );
  }
}
```

Note: verify `../utils/api_exception.dart` and `../utils/read_only_mode.dart` import paths match how `pet_form_screen.dart` imports `ApiException`/`ReadOnlyModeException` — copy those exact import lines from `pet_form_screen.dart` if they differ.

- [ ] **Step 2: Analyze**

Run: `cd flutter_app && flutter analyze lib/screens/pet_care_form_screen.dart`
Expected: No issues found. (Fix any import path mismatches by copying the exact lines from `pet_form_screen.dart`.)

- [ ] **Step 3: Commit**

```bash
git add flutter_app/lib/screens/pet_care_form_screen.dart
git commit -m "feat(app): Catat Perawatan form screen"
```

---

## Task 11: Care page (PetCareScreen)

**Files:**
- Create: `flutter_app/lib/screens/pet_care_screen.dart`
- Test: `flutter_app/test/pet_care_screen_test.dart`

**Interfaces:**
- Consumes: `petService.fetchCare/createCare/deleteCare`, `petCarePhotoStore`, `PetCareFormScreen`, status helpers, `AppFadeSwitcher`, `NataloPawRefreshIndicator`, `AppToast`.
- Produces: `class PetCareScreen extends StatefulWidget { final String petId; final String petName; }`. Pops nothing meaningful (care lives independently; profile stat refresh happens on its own reload).

- [ ] **Step 1: Write a widget test for banner color by status**

Create `flutter_app/test/pet_care_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop/models/pet_care_record.dart';
import 'package:natalo_petshop/screens/pet_care_screen.dart';
import 'package:natalo_petshop/theme/natalo_colors.dart';

void main() {
  testWidgets('overdue schedule banner label is SUDAH LEWAT JADWAL', (tester) async {
    final overdue = PetSchedule(
      recordId: 'r1',
      category: PetCareCategory.vaccine,
      nextDueAt: DateTime.now().subtract(const Duration(days: 14)),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PetCareBanner(schedule: overdue, onMarkDone: () {})),
    ));
    expect(find.text('SUDAH LEWAT JADWAL'), findsOneWidget);
    expect(find.text('JADWAL TERDEKAT'), findsNothing);
  });

  testWidgets('soon schedule banner label is JADWAL TERDEKAT', (tester) async {
    final soon = PetSchedule(
      recordId: 'r2',
      category: PetCareCategory.grooming,
      nextDueAt: DateTime.now().add(const Duration(days: 5)),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PetCareBanner(schedule: soon, onMarkDone: () {})),
    ));
    expect(find.text('JADWAL TERDEKAT'), findsOneWidget);
    expect(find.text('SUDAH LEWAT JADWAL'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test, verify fail**

Run: `cd flutter_app && flutter test test/pet_care_screen_test.dart`
Expected: FAIL — `PetCareBanner` / `pet_care_screen.dart` not found.

- [ ] **Step 3: Implement the care screen**

Create `flutter_app/lib/screens/pet_care_screen.dart`. It must export a PUBLIC `PetCareBanner` widget (used by the test) plus the screen. Key structure:

```dart
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/pet_care_record.dart';
import '../services/pet_care_photo_store.dart';
import '../services/pet_service.dart';
import '../theme/natalo_colors.dart';
import '../theme/natalo_text.dart';
import '../utils/haptics.dart';
import '../widgets/app_ui.dart';
import '../widgets/app_toast.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';
import 'pet_care_form_screen.dart';

const _brandBlue = NataloColors.primary;

class PetCareScreen extends StatefulWidget {
  final String petId;
  final String petName;
  const PetCareScreen({super.key, required this.petId, required this.petName});

  @override
  State<PetCareScreen> createState() => _PetCareScreenState();
}

class _PetCareScreenState extends State<PetCareScreen> {
  List<PetCareRecord> _records = const [];
  List<PetSchedule> _upcoming = const [];
  bool _loading = true;
  String? _error;
  PetCareCategory? _filter; // null = Semua

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await petService.fetchCare(widget.petId);
      if (!mounted) return;
      setState(() {
        _records = res.records;
        _upcoming = res.upcoming;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Gagal memuat perawatan. Tarik untuk coba lagi.';
        _loading = false;
      });
    }
  }

  Future<void> _openForm() async {
    AppHaptics.tap();
    final created = await Navigator.of(context).push<PetCareRecord>(
      MaterialPageRoute(
          builder: (_) => PetCareFormScreen(petId: widget.petId)),
    );
    if (created != null) await _load();
  }

  Future<void> _markDone(PetSchedule schedule) async {
    // "Tandai selesai": catat record baru kategori sama, doneAt = hari ini.
    AppHaptics.tap();
    try {
      await petService.createCare(
        widget.petId,
        category: schedule.category,
        doneAt: DateTime.now(),
      );
      await _load();
      if (!mounted) return;
      AppToast.show(context, 'Ditandai selesai', kind: ToastKind.success);
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, 'Gagal. Coba lagi.', kind: ToastKind.error);
    }
  }

  Future<void> _confirmDelete(PetCareRecord record) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus catatan?'),
        content: Text('${record.category.label} akan dihapus permanen.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hapus',
                  style: TextStyle(color: NataloColors.danger))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await petService.deleteCare(widget.petId, record.id);
      await petCarePhotoStore.delete(record.id);
      await _load();
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, 'Gagal menghapus.', kind: ToastKind.error);
    }
  }

  List<PetCareRecord> get _filtered => _filter == null
      ? _records
      : _records.where((r) => r.category == _filter).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Kembali',
        ),
        title: Text('Perawatan ${widget.petName}'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        backgroundColor: _brandBlue,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_rounded),
      ),
      body: NataloPawRefreshIndicator(
        onRefresh: _load,
        child: AppFadeSwitcher(
          stateKey: _loading
              ? 'loading'
              : _error != null
                  ? 'error'
                  : (_records.isEmpty && _upcoming.isEmpty)
                      ? 'empty'
                      : 'content',
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const _CareSkeleton();
    if (_error != null) {
      return _CareMessage(icon: Icons.wifi_off_rounded, text: _error!);
    }
    if (_records.isEmpty && _upcoming.isEmpty) {
      return _CareEmpty(onAdd: () => _openForm());
    }
    final nearest = _upcoming.isNotEmpty ? _upcoming.first : null;
    final others = _upcoming.length > 1 ? _upcoming.sublist(1) : <PetSchedule>[];
    final filtered = _filtered;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 96),
      children: [
        _FilterRow(
          selected: _filter,
          onSelect: (c) => setState(() => _filter = c),
        ),
        if (nearest != null) ...[
          const SizedBox(height: 14),
          PetCareBanner(schedule: nearest, onMarkDone: () => _markDone(nearest)),
        ],
        if (others.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < others.length && i < 2; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _MiniSchedule(schedule: others[i])),
              ],
            ],
          ),
        ],
        const SizedBox(height: 14),
        Text('RIWAYAT',
            style: TextStyle(
                fontSize: 10,
                fontWeight: NataloWeight.strong,
                letterSpacing: 0.3,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('Belum ada catatan untuk filter ini.',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: NataloWeight.body,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          )
        else
          for (final r in filtered)
            _HistoryTile(record: r, onDelete: () => _confirmDelete(r)),
      ],
    );
  }
}
```

Then implement these widgets in the SAME file (below the state class):

```dart
/// Banner jadwal terdekat. Merah + label "SUDAH LEWAT JADWAL" saat overdue,
/// biru brand + "JADWAL TERDEKAT" selain itu.
class PetCareBanner extends StatelessWidget {
  final PetSchedule schedule;
  final VoidCallback onMarkDone;
  const PetCareBanner(
      {super.key, required this.schedule, required this.onMarkDone});

  @override
  Widget build(BuildContext context) {
    final status = scheduleStatusOf(schedule.nextDueAt);
    final overdue = status == ScheduleStatus.overdue;
    final bg = overdue ? NataloColors.dangerDark : _brandBlue;
    final label = overdue ? 'SUDAH LEWAT JADWAL' : 'JADWAL TERDEKAT';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: NataloWeight.strong,
                  letterSpacing: 0.4,
                  color: Colors.white70)),
          const SizedBox(height: 4),
          Text(schedule.category.label,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: NataloWeight.strong,
                  color: Colors.white)),
          const SizedBox(height: 7),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(scheduleCountdownLabel(schedule.nextDueAt),
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: NataloWeight.strong,
                        color: Colors.white)),
              ),
              const Spacer(),
              InkWell(
                onTap: onMarkDone,
                child: const Text('Tandai selesai',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: NataloWeight.strong,
                        color: Colors.white,
                        decoration: TextDecoration.underline)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniSchedule extends StatelessWidget {
  final PetSchedule schedule;
  const _MiniSchedule({required this.schedule});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final overdue = scheduleStatusOf(schedule.nextDueAt) == ScheduleStatus.overdue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(schedule.category.icon, size: 13, color: _brandBlue),
              const SizedBox(width: 5),
              Flexible(
                child: Text(schedule.category.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: NataloWeight.body,
                        color: cs.onSurfaceVariant)),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(scheduleCountdownLabel(schedule.nextDueAt),
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: NataloWeight.strong,
                  color: overdue ? NataloColors.dangerDark : null)),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final PetCareRecord record;
  final VoidCallback onDelete;
  const _HistoryTile({required this.record, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sub = [
      _fmtDate(record.doneAt),
      if (record.note != null && record.note!.trim().isNotEmpty)
        record.note!.trim(),
    ].join(' • ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: isDark
                  ? _brandBlue.withValues(alpha: 0.18)
                  : NataloColors.primarySoft,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(record.category.icon, size: 15, color: _brandBlue),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(record.category.label,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: NataloWeight.strong)),
                const SizedBox(height: 2),
                Text(sub,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: NataloWeight.body,
                        color: cs.onSurfaceVariant)),
                _CarePhotoThumb(recordId: record.id),
              ],
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: Icon(Icons.more_horiz_rounded, color: cs.outline),
            tooltip: 'Hapus',
          ),
        ],
      ),
    );
  }
}

class _CarePhotoThumb extends StatefulWidget {
  final String recordId;
  const _CarePhotoThumb({required this.recordId});
  @override
  State<_CarePhotoThumb> createState() => _CarePhotoThumbState();
}

class _CarePhotoThumbState extends State<_CarePhotoThumb> {
  File? _file;
  @override
  void initState() {
    super.initState();
    petCarePhotoStore.get(widget.recordId).then((f) {
      if (mounted) setState(() => _file = f);
    });
  }

  @override
  Widget build(BuildContext context) {
    final f = _file;
    if (f == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GestureDetector(
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => Dialog(child: Image.file(f)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(f, width: 56, height: 56, fit: BoxFit.cover),
        ),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  final PetCareCategory? selected;
  final ValueChanged<PetCareCategory?> onSelect;
  const _FilterRow({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _chip(context, 'Semua', selected == null, () => onSelect(null)),
          for (final c in PetCareCategory.ordered) ...[
            const SizedBox(width: 6),
            _chip(context, c.label, selected == c, () => onSelect(c)),
          ],
        ],
      ),
    );
  }

  Widget _chip(
      BuildContext context, String label, bool active, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: active ? _brandBlue : Colors.transparent,
            border: Border.all(color: active ? _brandBlue : cs.outlineVariant),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: NataloWeight.strong,
                  color: active ? Colors.white : cs.onSurfaceVariant)),
        ),
      ),
    );
  }
}

class _CareEmpty extends StatelessWidget {
  final VoidCallback onAdd;
  const _CareEmpty({required this.onAdd});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 90, 32, 100),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: isDark
                    ? _brandBlue.withValues(alpha: 0.20)
                    : NataloColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.medical_services_outlined,
                  color: _brandBlue, size: 30),
            ),
            const SizedBox(height: 16),
            const Text('Belum ada perawatan',
                style: TextStyle(
                    fontSize: 15, fontWeight: NataloWeight.strong)),
            const SizedBox(height: 6),
            Text(
                'Catat vaksin, grooming, atau obat untuk memantau kesehatannya.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: NataloWeight.body,
                    color: cs.onSurfaceVariant)),
            const SizedBox(height: 20),
            SizedBox(
              height: 44,
              child: ElevatedButton.icon(
                onPressed: onAdd,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brandBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Catat Perawatan',
                    style: TextStyle(
                        fontWeight: NataloWeight.strong, fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CareMessage extends StatelessWidget {
  final IconData icon;
  final String text;
  const _CareMessage({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 90, 32, 100),
        child: Column(
          children: [
            Icon(icon, color: cs.onSurfaceVariant, size: 40),
            const SizedBox(height: 14),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: NataloWeight.body,
                    color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _CareSkeleton extends StatelessWidget {
  const _CareSkeleton();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Container(
          height: 96,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ],
    );
  }
}

String _fmtDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}
```

- [ ] **Step 4: Run the widget test, verify pass**

Run: `cd flutter_app && flutter test test/pet_care_screen_test.dart`
Expected: PASS (both banner-label cases).

- [ ] **Step 5: Analyze**

Run: `cd flutter_app && flutter analyze lib/screens/pet_care_screen.dart`
Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
git add flutter_app/lib/screens/pet_care_screen.dart flutter_app/test/pet_care_screen_test.dart
git commit -m "feat(app): Perawatan care page (banner/mini/history/filter)"
```

---

## Task 12: PetProfileScreen — "Perawatan" section + health rows

**Files:**
- Modify: `flutter_app/lib/screens/pet_profile_screen.dart`

**Interfaces:**
- Consumes: `PetCareScreen`, `petService.fetchCare`, status helpers, `PetCareRecord`/`PetSchedule`.
- Produces: profile shows a live "Perawatan" section (nearest schedule card + last-2 records + "Lihat semua"), health info rows under the bio, and the stat card "Perawatan" shows `_pet.careCount` and is tappable.

- [ ] **Step 1: Add imports + care state to `_PetProfileScreenState`**

At top of file add:

```dart
import '../models/pet_care_record.dart';
import '../services/pet_service.dart';
import 'pet_care_screen.dart';
```

In `_PetProfileScreenState`, add fields:

```dart
  List<PetCareRecord> _careRecords = const [];
  List<PetSchedule> _careUpcoming = const [];
```

In `initState`, after `_pet = widget.pet;`, add:

```dart
    _loadCare();
```

Add methods:

```dart
  Future<void> _loadCare() async {
    try {
      final res = await petService.fetchCare(_pet.id);
      if (!mounted) return;
      setState(() {
        _careRecords = res.records;
        _careUpcoming = res.upcoming;
        _pet = _pet.copyWith(careCount: res.records.length);
      });
    } catch (_) {
      // Diamkan — section perawatan sekadar tak terisi kalau gagal muat.
    }
  }

  Future<void> _openCare() async {
    AppHaptics.tap();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PetCareScreen(petId: _pet.id, petName: _pet.name),
      ),
    );
    _dirty = true;
    await _loadCare();
  }
```

- [ ] **Step 2: Replace the "Segera hadir" card in the ListView with the care section**

In `build`, replace the `_Entrance(... _ComingSoonCard(...))` child with:

```dart
          _Entrance(
            controller: _entrance,
            start: 0.42,
            child: _CareSection(
              records: _careRecords,
              upcoming: _careUpcoming,
              petName: _pet.name,
              onSeeAll: _openCare,
              onAddFirst: _openCare,
            ),
          ),
          _Entrance(
            controller: _entrance,
            start: 0.5,
            child: _ComingSoonCard(petName: _pet.name),
          ),
```

- [ ] **Step 3: Make the "Perawatan" stat show careCount + tap**

In `_StatsRow`, change the middle stat to use the pet's count and wrap in a tap. Replace the `_StatCard(value: '0', label: 'Perawatan')` line with:

```dart
          Expanded(
            child: GestureDetector(
              onTap: onCareTap,
              child: _StatCard(value: '${pet.careCount}', label: 'Perawatan'),
            ),
          ),
```

Add `final VoidCallback onCareTap;` to `_StatsRow` and pass `onCareTap: _openCare` where `_StatsRow(pet: pet)` is built in `build` (change to `_StatsRow(pet: pet, onCareTap: _openCare)`).

- [ ] **Step 4: Update `_ComingSoonCard` text (Perawatan removed from it)**

In `_ComingSoonCard.build`, change the body text to:

```dart
              'Journey dan Belanja untuk $petName akan muncul di sini.',
```

- [ ] **Step 5: Add health info rows in `_ProfileHeader`**

In `_ProfileHeader.build`, after the bio block (`if (pet.bio != null ...)`), before the trailing `SizedBox(height: 12)`, add:

```dart
              if (_hasHealthInfo(pet)) ...[
                const SizedBox(height: 8),
                _Entrance(
                  controller: entrance,
                  start: 0.32,
                  child: _HealthInfoRows(pet: pet),
                ),
              ],
```

Add the helper (top-level in the file):

```dart
bool _hasHealthInfo(Pet pet) =>
    pet.sterilized != null ||
    (pet.allergy != null && pet.allergy!.trim().isNotEmpty) ||
    (pet.healthNote != null && pet.healthNote!.trim().isNotEmpty);
```

- [ ] **Step 6: Implement `_CareSection` and `_HealthInfoRows` widgets**

Add to the file:

```dart
class _CareSection extends StatelessWidget {
  final List<PetCareRecord> records;
  final List<PetSchedule> upcoming;
  final String petName;
  final VoidCallback onSeeAll;
  final VoidCallback onAddFirst;
  const _CareSection({
    required this.records,
    required this.upcoming,
    required this.petName,
    required this.onSeeAll,
    required this.onAddFirst,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (records.isEmpty && upcoming.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onAddFirst,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.medical_services_outlined,
                      color: _brandBlue, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Catat perawatan pertama $petName',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: NataloWeight.strong)),
                  ),
                  Icon(Icons.chevron_right_rounded, color: cs.outline),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final nearest = upcoming.isNotEmpty ? upcoming.first : null;
    final lastTwo = records.take(2).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Perawatan',
                  style: TextStyle(
                      fontSize: 13, fontWeight: NataloWeight.strong)),
              const Spacer(),
              GestureDetector(
                onTap: onSeeAll,
                child: const Text('Lihat semua',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: NataloWeight.strong,
                        color: _brandBlue)),
              ),
            ],
          ),
          if (nearest != null) ...[
            const SizedBox(height: 8),
            _NearestCard(schedule: nearest),
          ],
          if (lastTwo.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('TERAKHIR DICATAT',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: NataloWeight.strong,
                    letterSpacing: 0.3,
                    color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            for (final r in lastTwo)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Icon(r.category.icon, size: 15, color: cs.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text('${r.category.label} — ${_fmtDate(r.doneAt)}',
                        style: const TextStyle(
                            fontSize: 11.5, fontWeight: NataloWeight.body)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _NearestCard extends StatelessWidget {
  final PetSchedule schedule;
  const _NearestCard({required this.schedule});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final overdue =
        scheduleStatusOf(schedule.nextDueAt) == ScheduleStatus.overdue;
    final soon = scheduleStatusOf(schedule.nextDueAt) == ScheduleStatus.soon;
    final bg = overdue
        ? (isDark ? NataloColors.dangerDark.withValues(alpha: 0.18) : NataloColors.dangerSoft)
        : cs.surfaceContainerHighest;
    final border = overdue
        ? NataloColors.danger.withValues(alpha: 0.5)
        : Colors.transparent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(schedule.category.icon,
              size: 17,
              color: overdue ? NataloColors.dangerDark : _brandBlue),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(schedule.category.label,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: NataloWeight.strong,
                        color: overdue ? NataloColors.dangerDark : null)),
                const SizedBox(height: 2),
                Text(
                    '${_fmtDate(schedule.nextDueAt)} • ${scheduleCountdownLabel(schedule.nextDueAt)}',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: NataloWeight.body,
                        color: overdue
                            ? NataloColors.danger
                            : cs.onSurfaceVariant)),
              ],
            ),
          ),
          _StatusBadge(overdue: overdue, soon: soon),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool overdue;
  final bool soon;
  const _StatusBadge({required this.overdue, required this.soon});
  @override
  Widget build(BuildContext context) {
    if (!overdue && !soon) return const SizedBox.shrink();
    final bg = overdue ? NataloColors.danger : _brandBlue;
    final label = overdue ? 'Terlambat' : 'Segera';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: const TextStyle(
              fontSize: 9.5,
              fontWeight: NataloWeight.strong,
              color: Colors.white)),
    );
  }
}

class _HealthInfoRows extends StatelessWidget {
  final Pet pet;
  const _HealthInfoRows({required this.pet});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = <(String, String)>[
      if (pet.sterilized != null)
        ('Steril', pet.sterilized! ? 'Ya' : 'Belum'),
      if (pet.allergy != null && pet.allergy!.trim().isNotEmpty)
        ('Alergi', pet.allergy!.trim()),
      if (pet.healthNote != null && pet.healthNote!.trim().isNotEmpty)
        ('Kondisi', pet.healthNote!.trim()),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, value) in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text.rich(TextSpan(children: [
              TextSpan(
                  text: '$label: ',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: NataloWeight.strong)),
              TextSpan(
                  text: value,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: NataloWeight.body,
                      color: cs.onSurfaceVariant)),
            ])),
          ),
      ],
    );
  }
}

String _fmtDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}
```

- [ ] **Step 7: Analyze**

Run: `cd flutter_app && flutter analyze lib/screens/pet_profile_screen.dart`
Expected: No issues found. (If `_fmtDate` collides with an existing definition in the file, keep one.)

- [ ] **Step 8: Commit**

```bash
git add flutter_app/lib/screens/pet_profile_screen.dart
git commit -m "feat(app): Perawatan section + health rows on Profil Anabulku"
```

---

## Task 13: AnabulkuScreen — schedule chip + "Jadwal Terdekat" section

**Files:**
- Modify: `flutter_app/lib/screens/anabulku_screen.dart`

**Interfaces:**
- Consumes: `Pet.nearestDue`, status helpers, `PetCareScreen`.
- Produces: each `_PetTile` shows a schedule chip when `pet.nearestDue != null`; below the list a "Jadwal Terdekat" section aggregates schedules across pets (max 3), tapping a row opens that pet's `PetCareScreen`.

- [ ] **Step 1: Add imports**

At top of `flutter_app/lib/screens/anabulku_screen.dart`:

```dart
import '../models/pet_care_record.dart';
import 'pet_care_screen.dart';
```

- [ ] **Step 2: Add the schedule chip to `_PetTile`'s chip row**

In `_PetTile.build`, the chip `Row` currently holds gender + age. Add a schedule chip. Change `hasChips` to also account for the schedule, and append after the age chip:

```dart
                          if (pet.nearestDue != null) ...[
                            if (pet.gender != null || pet.ageLabel != null)
                              const SizedBox(width: 5),
                            _ScheduleChip(schedule: pet.nearestDue!),
                          ],
```

Update `hasChips`:

```dart
    final hasChips =
        pet.gender != null || pet.ageLabel != null || pet.nearestDue != null;
```

- [ ] **Step 3: Add the `_ScheduleChip` widget**

```dart
/// Chip jadwal terdekat di kartu pet — merah bila terlambat, biru bila segera,
/// netral bila normal.
class _ScheduleChip extends StatelessWidget {
  final PetSchedule schedule;
  const _ScheduleChip({required this.schedule});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = scheduleStatusOf(schedule.nextDueAt);
    final overdue = status == ScheduleStatus.overdue;
    final soon = status == ScheduleStatus.soon;
    final Color bg;
    final Color fg;
    if (overdue) {
      bg = isDark
          ? NataloColors.danger.withValues(alpha: 0.22)
          : NataloColors.dangerSoft;
      fg = NataloColors.dangerDark;
    } else if (soon) {
      bg = isDark ? _brandBlue.withValues(alpha: 0.22) : NataloColors.primarySoft;
      fg = _brandBlue;
    } else {
      bg = cs.surfaceContainerHighest;
      fg = cs.onSurfaceVariant;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        '${schedule.category.label} • ${scheduleCountdownLabel(schedule.nextDueAt)}',
        style: TextStyle(
            fontSize: 10, fontWeight: NataloWeight.strong, color: fg),
      ),
    );
  }
}
```

- [ ] **Step 4: Add the "Jadwal Terdekat" section to `_PetList`**

`_PetList` is a `StatelessWidget` receiving `pets`. It needs a callback to open a pet's care page. Add `final ValueChanged<Pet> onTapSchedule;` to `_PetList` and pass it from the build site (`_PetList(pets: _pets, onTapPet: _openProfile, onAdd: _openAddForm, onTapSchedule: _openCareFor)`). In `_AnabulkuScreenState` add:

```dart
  Future<void> _openCareFor(Pet pet) async {
    AppHaptics.tap();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PetCareScreen(petId: pet.id, petName: pet.name),
      ),
    );
    await _load();
  }
```

In `_PetList.build`, after the `_AddPetCard(onTap: onAdd)` child, append:

```dart
        _JadwalTerdekatSection(pets: pets, onTap: onTapSchedule),
```

- [ ] **Step 5: Implement `_JadwalTerdekatSection`**

```dart
/// Gabungan jadwal terdekat semua pet (maks 3), diurutkan paling dekat dulu.
class _JadwalTerdekatSection extends StatelessWidget {
  final List<Pet> pets;
  final ValueChanged<Pet> onTap;
  const _JadwalTerdekatSection({required this.pets, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entries = <({Pet pet, PetSchedule schedule})>[];
    for (final p in pets) {
      final due = p.nearestDue;
      if (due != null) entries.add((pet: p, schedule: due));
    }
    if (entries.isEmpty) return const SizedBox.shrink();
    entries.sort(
        (a, b) => a.schedule.nextDueAt.compareTo(b.schedule.nextDueAt));
    final top = entries.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        const Text('Jadwal Terdekat',
            style: TextStyle(fontSize: 13, fontWeight: NataloWeight.strong)),
        const SizedBox(height: 8),
        for (final e in top)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onTap(e.pet),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(e.schedule.category.icon,
                          size: 15, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${e.pet.name} — ${e.schedule.category.label}',
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: NataloWeight.strong)),
                          const SizedBox(height: 2),
                          Text(_fmtDate(e.schedule.nextDueAt),
                              style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: NataloWeight.body,
                                  color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    _ScheduleChip(schedule: e.schedule),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

String _fmtDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}
```

- [ ] **Step 6: Analyze**

Run: `cd flutter_app && flutter analyze lib/screens/anabulku_screen.dart`
Expected: No issues found.

- [ ] **Step 7: Commit**

```bash
git add flutter_app/lib/screens/anabulku_screen.dart
git commit -m "feat(app): schedule chip + Jadwal Terdekat on Anabulku list"
```

---

## Task 14: pet_form_screen — health fields (sterilized toggle + allergy/healthNote)

**Files:**
- Modify: `flutter_app/lib/screens/pet_form_screen.dart`

**Interfaces:**
- Consumes: extended `petService.createPet/updatePet` (health params from Task 8).
- Produces: form collects `sterilized` (tri-state: null / Ya / Belum), `allergy`, `healthNote`; passes them to create/update.

- [ ] **Step 1: Add state fields**

In `_PetFormScreenState`, add:

```dart
  bool? _sterilized;
  final _allergyController = TextEditingController();
  final _healthNoteController = TextEditingController();
```

In `initState` (where existing controllers are seeded from `widget.pet`), add:

```dart
    _sterilized = widget.pet?.sterilized;
    _allergyController.text = widget.pet?.allergy ?? '';
    _healthNoteController.text = widget.pet?.healthNote ?? '';
```

In `dispose`, add:

```dart
    _allergyController.dispose();
    _healthNoteController.dispose();
```

- [ ] **Step 2: Pass fields into save calls**

In `_save`, add to BOTH `updatePet(...)` and `createPet(...)` calls:

```dart
        sterilized: _sterilized,
        allergy: _allergyController.text.trim().isEmpty
            ? null
            : _allergyController.text.trim(),
        healthNote: _healthNoteController.text.trim().isEmpty
            ? null
            : _healthNoteController.text.trim(),
```

- [ ] **Step 3: Add form fields to the build (after the Bio field, before the delete button area)**

```dart
          const SizedBox(height: 16),
          const _FieldLabel('Steril'),
          Row(
            children: [
              Expanded(
                child: _SterilChip(
                  label: 'Ya',
                  selected: _sterilized == true,
                  onTap: () => setState(() =>
                      _sterilized = _sterilized == true ? null : true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SterilChip(
                  label: 'Belum',
                  selected: _sterilized == false,
                  onTap: () => setState(() =>
                      _sterilized = _sterilized == false ? null : false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _FieldLabel('Alergi (opsional)'),
          TextField(
            controller: _allergyController,
            maxLength: 100,
            decoration: _healthFieldDecoration(context, 'Mis. Ayam'),
          ),
          const SizedBox(height: 8),
          const _FieldLabel('Kondisi khusus (opsional)'),
          TextField(
            controller: _healthNoteController,
            maxLength: 150,
            maxLines: 2,
            minLines: 1,
            decoration: _healthFieldDecoration(context, 'Mis. Sensitif dingin'),
          ),
```

- [ ] **Step 4: Add the `_SterilChip` widget + decoration helper**

Reuse the `_GenderChip` visual. Add:

```dart
class _SterilChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SterilChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? (isDark
                    ? _brandBlue.withValues(alpha: 0.20)
                    : NataloColors.primarySoft)
                : Colors.transparent,
            border: Border.all(
                color: selected ? _brandBlue : cs.outlineVariant),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(label,
              style: TextStyle(
                  fontWeight: NataloWeight.strong,
                  color: selected ? _brandBlue : cs.onSurfaceVariant)),
        ),
      ),
    );
  }
}

InputDecoration _healthFieldDecoration(BuildContext context, String hint) {
  final cs = Theme.of(context).colorScheme;
  return InputDecoration(
    filled: true,
    fillColor: cs.surface,
    hintText: hint,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: cs.outlineVariant),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: cs.outlineVariant),
    ),
  );
}
```

- [ ] **Step 5: Analyze**

Run: `cd flutter_app && flutter analyze lib/screens/pet_form_screen.dart`
Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
git add flutter_app/lib/screens/pet_form_screen.dart
git commit -m "feat(app): pet health fields (steril/alergi/kondisi) in Edit Pet form"
```

---

## Task 15: Full verification + PR

**Files:** none (verification only).

- [ ] **Step 1: Run full backend test suite**

Run: `npx jest lib/__tests__/pet-care-api.test.ts lib/__tests__/pets-api-health.test.ts`
Expected: all green.

- [ ] **Step 2: Typecheck backend**

Run: `npx tsc --noEmit`
Expected: no errors.

- [ ] **Step 3: Run full Flutter analyze + tests**

Run: `cd flutter_app && flutter analyze`
Expected: No issues found (whole project).

Run: `cd flutter_app && flutter test`
Expected: all tests pass (including new `pet_care_status_test.dart`, `pet_care_screen_test.dart`, and existing suite).

- [ ] **Step 4: Push branch + open PR**

```bash
git push -u origin <branch-name>
gh pr create --title "Anabulku Tahap 3 — Perawatan (riwayat + jadwal)" --body "$(cat <<'EOF'
## Summary
- New PetCareRecord table + Pet health fields (sterilized/allergy/healthNote); migration idempotent.
- Care API: GET/POST/DELETE under /api/member/pets/[id]/care; pets list gains careCount + nearestDue.
- Server-side supersede rule → upcoming schedules (unit tested).
- Flutter: PetCareScreen (banner red-when-overdue, mini schedules, history, filter chips, FAB), Catat Perawatan form (category/date/note/next-due/local photo), Perawatan section + health rows on Profil Anabulku, schedule chip + Jadwal Terdekat on Anabulku list.
- Care photos stored LOCAL on device only (path_provider), not server.

## Verification
- Backend: jest (pet-care-api, pets-api-health) + tsc --noEmit green.
- Flutter: flutter analyze clean; flutter test green (status helpers + banner label tests).

## Not in scope (Tahap 3)
Push/cron reminders, edit record, server photo sync, Journey/Belanja. Dokumen Kesehatan + Grafik Berat Badan intentionally excluded per user.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 5: Post-merge chores (note for user, do not auto-run)**

Migration `20260724020000_add_pet_care_records` applies on next Vercel deploy. iOS/Android rebuild + device-verify needed for: Hero/entrance motion, banner red/blue in dark mode, local photo thumbnail. Update memory `anabulku-pets-profile-tahap1.md` to record Tahap 3.

---

## Self-Review

**Spec coverage:**
- Data model (PetCareRecord + supersede) → Tasks 1, 2. ✓
- Health fields on Pet → Tasks 1, 4, 8, 14. ✓
- API GET/POST/DELETE + list careCount/nearestDue → Tasks 3, 5. ✓
- Surface 0 (Anabulku list chip + Jadwal Terdekat) → Task 13. ✓
- Surface 1 (profile Perawatan section + health rows + stat) → Task 12. ✓
- Surface 2 (PetCareScreen banner/mini/history/filter/FAB/empty/loading/error) → Task 11. ✓
- Surface 3 (Catat Perawatan form: category/date/note/next-due/photo) → Task 10. ✓
- Local-only photo storage → Task 9 (+ used in 10, 11). ✓
- Status thresholds + "SUDAH LEWAT JADWAL" → Task 6 helpers, Tasks 11/12/13 rendering. ✓
- Tokens locked (NataloWeight/NataloColors, padding 20, appBar global) → applied in every UI task. ✓
- Tests (supersede/upcoming, payload validation, banner red vs blue, empty state, filter) → Tasks 2, 4, 6, 11. ✓ (Note: "tandai-selesai flow" is exercised via the `_markDone` path calling `createCare`; a dedicated widget test for it would need a mockable service seam — the current `petService` is a module singleton without injection, so that test is deferred; `_markDone` is covered indirectly by analyze + manual device-verify.)

**Placeholder scan:** No TBD/TODO; every code step shows complete code. Import-path caveats (api_exception/read_only_mode) flagged with instruction to copy exact lines from `pet_form_screen.dart`.

**Type consistency:** `PetCareCategory.apiValue`/`.label`/`.icon`/`.ordered`/`.fromApi` used consistently across Tasks 6/10/11/12/13. `fetchCare` returns record `({records, upcoming})` — consumed identically in Tasks 11 and 12. `PetSchedule` fields `recordId`/`category`/`nextDueAt` consistent. `scheduleStatusOf`/`scheduleCountdownLabel`/`daysUntil` signatures match between definition (Task 6) and all call sites. `PetCareBanner` is public (needed by Task 11 test). Service param names `sterilized`/`allergy`/`healthNote` consistent between Task 8 (service) and Task 14 (form) and Task 4 (backend validate).

**Tandai-selesai test deferral:** a dedicated widget test for the mark-done flow needs a mockable service seam, but `petService` is a module singleton without injection — deferred; the path is covered by analyze + device-verify. If injection is added later, add the test.
