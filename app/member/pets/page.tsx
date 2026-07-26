import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { LogoutButton } from "@/components/LogoutButton";
import { MemberNav } from "@/components/MemberNav";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import Link from "next/link";
import { requireCustomerSession } from "@/lib/session-guards";

// Opsi dropdown untuk pet BARU — 5 spesies kanonis, sinkron dengan
// flutter_app/lib/models/pet.dart kPetTypes. Pet lama dengan jenis di luar
// daftar ini (Burung/Reptil/Lainnya) masih valid di backend (lib/pets-api.ts
// PET_TYPES superset) dan tetap tampil apa adanya — hanya opsi pemilihan
// untuk pet baru/edit yang dipersempit di sini.
const PET_TYPES = ["Kucing", "Anjing", "Hamster", "Kelinci", "Ikan"];

// Keyword mapping untuk rekomendasi produk
const PET_KEYWORDS: Record<string, string[]> = {
  Kucing: ["kucing", "cat"],
  Anjing: ["anjing", "dog"],
  Hamster: ["hamster"],
  Kelinci: ["kelinci", "rabbit"],
  Ikan: ["ikan", "aquarium", "aquatic"],
  Burung: ["burung", "bird"],
  Reptil: ["reptil", "reptile"],
  Lainnya: [],
};

function daysUntil(date: Date): number {
  return Math.ceil((date.getTime() - Date.now()) / (1000 * 60 * 60 * 24));
}

function petAge(birthDate: Date): string {
  const months =
    (new Date().getFullYear() - birthDate.getFullYear()) * 12 +
    (new Date().getMonth() - birthDate.getMonth());
  if (months < 1) return "< 1 bulan";
  if (months < 12) return `${months} bulan`;
  const years = Math.floor(months / 12);
  const rem = months % 12;
  return rem > 0 ? `${years} tahun ${rem} bulan` : `${years} tahun`;
}

const PET_EMOJI: Record<string, string> = {
  Kucing: "🐱",
  Anjing: "🐶",
  Hamster: "🐹",
  Kelinci: "🐰",
  Ikan: "🐠",
  Burung: "🐦",
  Reptil: "🦎",
  Lainnya: "🐾",
};

export default async function MemberPetsPage({
  searchParams,
}: {
  searchParams: Promise<{ added?: string }>;
}) {
  const session = await requireCustomerSession();
  const { added } = await searchParams;

  const pets = await prisma.pet.findMany({
    where: { userId: session.sub },
    orderBy: { createdAt: "asc" },
  });

  // Rekomendasi produk berdasarkan jenis hewan
  const petTypes = [...new Set(pets.map((p) => p.type))];
  const keywords = petTypes.flatMap((t) => PET_KEYWORDS[t] ?? []);

  const recommendedProducts =
    keywords.length > 0
      ? await prisma.product.findMany({
          where: {
            isActive: true,
            OR: keywords.map((k) => ({
              category: { name: { contains: k, mode: "insensitive" as const } },
            })),
          },
          include: { category: true },
          take: 6,
        })
      : [];

  // ── Server Actions ─────────────────────────────────────────────────────────

  async function addPet(formData: FormData) {
    "use server";
    const sess = await getSession("CUSTOMER");
    if (!sess) return;

    const name = String(formData.get("name") || "").trim();
    const type = String(formData.get("type") || "Lainnya");
    const breed = String(formData.get("breed") || "").trim() || null;
    const birthDateRaw = String(formData.get("birthDate") || "").trim();
    const birthDate = birthDateRaw ? new Date(birthDateRaw) : null;
    const vaccineRaw = String(formData.get("vaccineReminderAt") || "").trim();
    const vaccineReminderAt = vaccineRaw ? new Date(vaccineRaw) : null;
    const groomingRaw = String(formData.get("groomingReminderAt") || "").trim();
    const groomingReminderAt = groomingRaw ? new Date(groomingRaw) : null;
    const notes = String(formData.get("notes") || "").trim() || null;

    if (!name) return;

    await prisma.pet.create({
      data: {
        userId: sess.sub,
        name,
        type,
        breed,
        birthDate,
        vaccineReminderAt,
        groomingReminderAt,
        notes,
      },
    });
    redirect("/member/pets?added=1");
  }

  async function updatePet(formData: FormData) {
    "use server";
    const sess = await getSession("CUSTOMER");
    if (!sess) return;

    const petId = String(formData.get("petId"));
    const name = String(formData.get("name") || "").trim();
    const type = String(formData.get("type") || "Lainnya");
    const breed = String(formData.get("breed") || "").trim() || null;
    const birthDateRaw = String(formData.get("birthDate") || "").trim();
    const birthDate = birthDateRaw ? new Date(birthDateRaw) : null;
    const vaccineRaw = String(formData.get("vaccineReminderAt") || "").trim();
    const vaccineReminderAt = vaccineRaw ? new Date(vaccineRaw) : null;
    const groomingRaw = String(formData.get("groomingReminderAt") || "").trim();
    const groomingReminderAt = groomingRaw ? new Date(groomingRaw) : null;
    const notes = String(formData.get("notes") || "").trim() || null;

    if (!name) return;

    await prisma.pet.updateMany({
      where: { id: petId, userId: sess.sub },
      data: {
        name,
        type,
        breed,
        birthDate,
        vaccineReminderAt,
        groomingReminderAt,
        notes,
      },
    });
    revalidatePath("/member/pets");
  }

  async function deletePet(formData: FormData) {
    "use server";
    const sess = await getSession("CUSTOMER");
    if (!sess) return;

    const petId = String(formData.get("petId"));
    await prisma.pet.deleteMany({ where: { id: petId, userId: sess.sub } });
    revalidatePath("/member/pets");
  }

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <div className="bg-natalo-600 px-4 pb-0 pt-8">
        <div className="mx-auto max-w-4xl">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div className="flex items-center gap-3">
              <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-white/20 text-2xl">
                🐾
              </div>
              <div>
                <p className="text-xs text-natalo-100">Member resmi</p>
                <p className="text-lg font-black text-white">
                  Halo, {session?.name}!
                </p>
              </div>
            </div>
            <LogoutButton
              redirectTo="/member/login"
              className="border-white/30 text-white hover:border-white/60"
            />
          </div>
          <MemberNav />
        </div>
      </div>

      <main className="mx-auto max-w-4xl px-4 py-8">
        {added && (
          <div className="mb-6 rounded-2xl bg-green-50 p-4 text-sm font-semibold text-green-700">
            ✅ Hewan berhasil ditambahkan.
          </div>
        )}

        {/* ── Daftar Hewan ── */}
        <h2 className="text-xl font-black text-gray-900">Hewan Saya</h2>

        <div className="mt-5 space-y-4">
          {pets.length === 0 && (
            <div className="rounded-2xl border border-gray-100 bg-white p-10 text-center">
              <span className="text-5xl">🐾</span>
              <p className="mt-3 font-semibold text-gray-700">
                Belum ada hewan terdaftar
              </p>
              <p className="mt-1 text-sm text-gray-500">
                Tambahkan hewan peliharaanmu di bawah ini.
              </p>
            </div>
          )}

          {pets.map((pet) => {
            const vaccDays = pet.vaccineReminderAt
              ? daysUntil(pet.vaccineReminderAt)
              : null;
            const groomDays = pet.groomingReminderAt
              ? daysUntil(pet.groomingReminderAt)
              : null;
            const birthStr = pet.birthDate
              ? pet.birthDate.toLocaleDateString("id-ID", {
                  day: "numeric",
                  month: "long",
                  year: "numeric",
                })
              : null;

            return (
              <div
                key={pet.id}
                className="overflow-hidden rounded-3xl border border-gray-100 bg-white shadow-sm"
              >
                {/* Pet header */}
                <div className="flex items-center gap-4 p-5">
                  <div className="flex h-14 w-14 shrink-0 items-center justify-center rounded-2xl bg-natalo-100 text-3xl">
                    {PET_EMOJI[pet.type] ?? "🐾"}
                  </div>
                  <div className="flex-1">
                    <p className="font-black text-gray-900 text-lg">
                      {pet.name}
                    </p>
                    <p className="text-sm text-gray-500">
                      {pet.type}
                      {pet.breed ? ` · ${pet.breed}` : ""}
                      {pet.birthDate ? ` · ${petAge(pet.birthDate)}` : ""}
                    </p>
                  </div>
                </div>

                {/* Reminders */}
                {(vaccDays !== null || groomDays !== null || pet.notes) && (
                  <div className="border-t border-gray-50 px-5 pb-4">
                    <div className="mt-4 flex flex-wrap gap-3">
                      {vaccDays !== null && (
                        <div
                          className={`rounded-xl px-3 py-2 text-xs ${
                            vaccDays <= 7
                              ? "bg-red-50 text-red-600"
                              : vaccDays <= 30
                              ? "bg-amber-50 text-amber-700"
                              : "bg-green-50 text-green-700"
                          }`}
                        >
                          💉 <strong>Vaksin</strong>{" "}
                          {vaccDays < 0
                            ? `telat ${Math.abs(vaccDays)} hari`
                            : vaccDays === 0
                            ? "hari ini!"
                            : `${vaccDays} hari lagi`}
                          <p className="mt-0.5 text-xs opacity-70">
                            {pet.vaccineReminderAt!.toLocaleDateString(
                              "id-ID",
                              {
                                day: "numeric",
                                month: "short",
                                year: "numeric",
                              }
                            )}
                          </p>
                        </div>
                      )}
                      {groomDays !== null && (
                        <div
                          className={`rounded-xl px-3 py-2 text-xs ${
                            groomDays <= 7
                              ? "bg-red-50 text-red-600"
                              : groomDays <= 14
                              ? "bg-amber-50 text-amber-700"
                              : "bg-natalo-50 text-natalo-700"
                          }`}
                        >
                          ✂️ <strong>Grooming</strong>{" "}
                          {groomDays < 0
                            ? `telat ${Math.abs(groomDays)} hari`
                            : groomDays === 0
                            ? "hari ini!"
                            : `${groomDays} hari lagi`}
                          <p className="mt-0.5 text-xs opacity-70">
                            {pet.groomingReminderAt!.toLocaleDateString(
                              "id-ID",
                              {
                                day: "numeric",
                                month: "short",
                                year: "numeric",
                              }
                            )}
                          </p>
                        </div>
                      )}
                      {birthStr && (
                        <div className="rounded-xl bg-purple-50 px-3 py-2 text-xs text-purple-700">
                          🎂 Lahir {birthStr}
                        </div>
                      )}
                    </div>
                    {pet.notes && (
                      <p className="mt-3 text-sm text-gray-500 italic">
                        {pet.notes}
                      </p>
                    )}
                  </div>
                )}

                {/* Edit & Delete */}
                <div className="border-t border-gray-100">
                  <details>
                    <summary className="flex cursor-pointer list-none items-center gap-2 px-5 py-3 text-sm font-semibold text-gray-500 hover:text-gray-900">
                      ✏️ Edit
                    </summary>
                    <form
                      action={updatePet}
                      className="border-t border-gray-50 p-5 space-y-4"
                    >
                      <input type="hidden" name="petId" value={pet.id} />
                      <div className="grid gap-4 sm:grid-cols-2">
                        <PetField
                          label="Nama"
                          name="name"
                          required
                          defaultValue={pet.name}
                        />
                        <div>
                          <label className="block text-sm font-medium text-gray-700">
                            Jenis hewan
                          </label>
                          <select
                            name="type"
                            defaultValue={pet.type}
                            className="mt-1 block w-full rounded-xl border border-gray-200 px-4 py-3 text-sm outline-none focus:border-natalo-400"
                          >
                            {/* Jenis lama (mis. Burung/Reptil) yang sudah tak
                                lagi jadi opsi baru tetap ditampilkan sebagai
                                opsi tambahan supaya edit pet lama (mis. ganti
                                nama saja) tidak diam-diam mengubah jenisnya. */}
                            {!PET_TYPES.includes(pet.type) && (
                              <option key={pet.type}>{pet.type}</option>
                            )}
                            {PET_TYPES.map((t) => (
                              <option key={t}>{t}</option>
                            ))}
                          </select>
                        </div>
                      </div>
                      <PetField
                        label="Ras / Breed"
                        name="breed"
                        defaultValue={pet.breed ?? ""}
                        placeholder="Opsional"
                      />
                      <div className="grid gap-4 sm:grid-cols-2">
                        <PetField
                          label="Tanggal lahir"
                          name="birthDate"
                          type="date"
                          defaultValue={
                            pet.birthDate
                              ? pet.birthDate.toISOString().substring(0, 10)
                              : ""
                          }
                        />
                      </div>
                      <div className="grid gap-4 sm:grid-cols-2">
                        <PetField
                          label="Reminder vaksin"
                          name="vaccineReminderAt"
                          type="date"
                          defaultValue={
                            pet.vaccineReminderAt
                              ? pet.vaccineReminderAt
                                  .toISOString()
                                  .substring(0, 10)
                              : ""
                          }
                        />
                        <PetField
                          label="Reminder grooming"
                          name="groomingReminderAt"
                          type="date"
                          defaultValue={
                            pet.groomingReminderAt
                              ? pet.groomingReminderAt
                                  .toISOString()
                                  .substring(0, 10)
                              : ""
                          }
                        />
                      </div>
                      <PetField
                        label="Catatan"
                        name="notes"
                        defaultValue={pet.notes ?? ""}
                        placeholder="Opsional"
                        textarea
                      />
                      <div className="flex gap-3">
                        <button
                          type="submit"
                          className="rounded-full bg-natalo-600 px-5 py-2.5 text-sm font-bold text-white hover:bg-natalo-700"
                        >
                          Simpan
                        </button>
                      </div>
                    </form>
                  </details>
                  <form action={deletePet} className="border-t border-gray-50">
                    <input type="hidden" name="petId" value={pet.id} />
                    <button
                      type="submit"
                      className="w-full px-5 py-3 text-sm font-semibold text-red-400 hover:text-red-600 hover:bg-red-50"
                    >
                      Hapus {pet.name}
                    </button>
                  </form>
                </div>
              </div>
            );
          })}
        </div>

        {/* ── Tambah Hewan ── */}
        <section className="mt-6 overflow-hidden rounded-3xl border border-gray-200 bg-white shadow-sm">
          <details>
            <summary className="flex cursor-pointer list-none items-center gap-2 px-6 py-4 font-bold text-gray-700 hover:bg-gray-50">
              <span className="text-natalo-600">＋</span> Tambah Hewan
              Peliharaan
            </summary>

            <form
              action={addPet}
              className="border-t border-gray-100 p-6 space-y-4"
            >
              <div className="grid gap-4 sm:grid-cols-2">
                <PetField
                  label="Nama hewan"
                  name="name"
                  required
                  placeholder="Contoh: Mochi"
                />
                <div>
                  <label className="block text-sm font-medium text-gray-700">
                    Jenis hewan <span className="text-red-500">*</span>
                  </label>
                  <select
                    name="type"
                    className="mt-1 block w-full rounded-xl border border-gray-200 px-4 py-3 text-sm outline-none focus:border-natalo-400"
                  >
                    {PET_TYPES.map((t) => (
                      <option key={t}>{t}</option>
                    ))}
                  </select>
                </div>
              </div>

              <PetField
                label="Ras / Breed"
                name="breed"
                placeholder="Opsional, contoh: Persian"
              />

              <div className="grid gap-4 sm:grid-cols-2">
                <PetField label="Tanggal lahir" name="birthDate" type="date" />
              </div>

              <div className="grid gap-4 sm:grid-cols-2">
                <div>
                  <PetField
                    label="Reminder vaksin berikutnya"
                    name="vaccineReminderAt"
                    type="date"
                  />
                  <p className="mt-1 text-xs text-gray-400">
                    💉 Kamu akan diingatkan melalui halaman ini
                  </p>
                </div>
                <div>
                  <PetField
                    label="Reminder grooming berikutnya"
                    name="groomingReminderAt"
                    type="date"
                  />
                  <p className="mt-1 text-xs text-gray-400">
                    ✂️ Untuk kucing & anjing
                  </p>
                </div>
              </div>

              <PetField
                label="Catatan"
                name="notes"
                placeholder="Opsional, contoh: alergi makanan tertentu"
                textarea
              />

              <button
                type="submit"
                className="rounded-full bg-natalo-600 px-6 py-3 text-sm font-bold text-white hover:bg-natalo-700"
              >
                Tambahkan hewan
              </button>
            </form>
          </details>
        </section>

        {/* ── Rekomendasi Produk ── */}
        {recommendedProducts.length > 0 && (
          <section className="mt-8">
            <h2 className="text-lg font-black text-gray-900">
              Rekomendasi untuk Hewanmu
            </h2>
            <p className="mt-1 text-sm text-gray-500">
              Produk yang sesuai untuk {petTypes.join(", ")} kamu.
            </p>

            <div className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {recommendedProducts.map((product) => (
                <Link
                  key={product.id}
                  href={`/products/${product.slug}`}
                  className="group flex gap-3 rounded-2xl border border-gray-100 bg-white p-4 shadow-sm transition hover:border-natalo-200 hover:shadow"
                >
                  <div className="flex h-16 w-16 shrink-0 items-center justify-center overflow-hidden rounded-xl bg-gray-50">
                    {product.imageUrl ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img
                        src={product.imageUrl}
                        alt={product.name}
                        className="h-full w-full object-cover"
                      />
                    ) : (
                      <span className="text-2xl">🐾</span>
                    )}
                  </div>
                  <div>
                    <p className="text-sm font-semibold text-gray-900 group-hover:text-natalo-700 line-clamp-2">
                      {product.name}
                    </p>
                    {product.category && (
                      <p className="mt-0.5 text-xs text-gray-400">
                        {product.category.name}
                      </p>
                    )}
                    <p className="mt-1 text-sm font-bold text-natalo-600">
                      Rp
                      {(product.memberPrice ?? product.price).toLocaleString(
                        "id-ID"
                      )}
                    </p>
                  </div>
                </Link>
              ))}
            </div>
          </section>
        )}
      </main>
    </div>
  );
}

function PetField({
  label,
  name,
  type = "text",
  required,
  placeholder,
  defaultValue,
  textarea,
}: {
  label: string;
  name: string;
  type?: string;
  required?: boolean;
  placeholder?: string;
  defaultValue?: string;
  textarea?: boolean;
}) {
  const cls =
    "mt-1 block w-full rounded-xl border border-gray-200 px-4 py-3 text-sm outline-none focus:border-natalo-400";
  return (
    <div>
      <label className="block text-sm font-medium text-gray-700">
        {label}
        {required && <span className="ml-1 text-red-500">*</span>}
      </label>
      {textarea ? (
        <textarea
          name={name}
          placeholder={placeholder}
          defaultValue={defaultValue}
          rows={2}
          className={cls}
        />
      ) : (
        <input
          type={type}
          name={name}
          required={required}
          placeholder={placeholder}
          defaultValue={defaultValue}
          className={cls}
        />
      )}
    </div>
  );
}
