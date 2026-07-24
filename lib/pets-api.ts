export const PET_TYPES = new Set([
  "Kucing",
  "Anjing",
  "Ikan",
  "Burung",
  "Reptil",
  "Lainnya",
]);
const MAX_NAME_LENGTH = 40;
const MAX_BREED_LENGTH = 60;

export type ValidatedPetPayload = {
  name: string;
  type: string;
  breed: string | null;
  birthDate: Date | null;
};

export function validatePetPayload(
  body: unknown,
): { data: ValidatedPetPayload } | { error: string } {
  if (typeof body !== "object" || body === null) {
    return { error: "Payload tidak valid." };
  }
  const { name, type, breed, birthDate } = body as Record<string, unknown>;

  const trimmedName = typeof name === "string" ? name.trim() : "";
  if (!trimmedName) {
    return { error: "Nama pet wajib diisi." };
  }
  if (trimmedName.length > MAX_NAME_LENGTH) {
    return { error: `Nama pet maksimal ${MAX_NAME_LENGTH} karakter.` };
  }
  if (typeof type !== "string" || !PET_TYPES.has(type)) {
    return { error: "Jenis pet tidak valid." };
  }
  const trimmedBreed = typeof breed === "string" ? breed.trim() : "";
  if (trimmedBreed.length > MAX_BREED_LENGTH) {
    return { error: `Breed maksimal ${MAX_BREED_LENGTH} karakter.` };
  }
  let parsedBirthDate: Date | null = null;
  if (typeof birthDate === "string" && birthDate.trim()) {
    const parsed = new Date(birthDate);
    if (Number.isNaN(parsed.getTime())) {
      return { error: "Tanggal lahir tidak valid." };
    }
    parsedBirthDate = parsed;
  }

  return {
    data: {
      name: trimmedName,
      type,
      breed: trimmedBreed || null,
      birthDate: parsedBirthDate,
    },
  };
}
