import { getSession, createSessionToken, SESSION_COOKIE_OPTIONS } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import Link from "next/link";
import { LogoutButton } from "@/components/LogoutButton";
import { MemberNav } from "@/components/MemberNav";
import { AddressPinpointPicker } from "@/components/AddressPinpointPicker";
import { PasswordInput } from "@/components/PasswordInput";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import bcrypt from "bcryptjs";

export default async function MemberProfilePage({
  searchParams,
}: {
  searchParams: Promise<{
    saved?: string;
    pwsaved?: string;
    addrupdated?: string;
    error?: string;
    pwerror?: string;
  }>;
}) {
  const session = await getSession();
  const { saved, pwsaved, addrupdated, error, pwerror } = await searchParams;

  const [user, addresses] = await Promise.all([
    session
      ? prisma.user.findUnique({
          where: { id: session.sub },
          select: { id: true, name: true, email: true, phone: true, passwordHash: true, birthDate: true },
        })
      : null,
    session
      ? prisma.address.findMany({
          where: { userId: session.sub },
          orderBy: [{ isMain: "desc" }, { createdAt: "asc" }],
        })
      : [],
  ]);

  // ── Server Actions ─────────────────────────────────────────────────────────

  async function updateProfile(formData: FormData) {
    "use server";
    const sess = await getSession();
    if (!sess) return;

    const name = String(formData.get("name") || "").trim();
    const email = String(formData.get("email") || "").trim() || null;
    const phone = String(formData.get("phone") || "").trim() || null;
    const birthDateRaw = String(formData.get("birthDate") || "").trim();
    const birthDate = birthDateRaw ? new Date(birthDateRaw) : null;

    if (!name) redirect("/member/profile?error=name");

    if (email) {
      const ex = await prisma.user.findUnique({ where: { email } });
      if (ex && ex.id !== sess.sub) redirect("/member/profile?error=email");
    }
    if (phone) {
      const ex = await prisma.user.findUnique({ where: { phone } });
      if (ex && ex.id !== sess.sub) redirect("/member/profile?error=phone");
    }

    await prisma.user.update({
      where: { id: sess.sub },
      data: { name, email, phone, birthDate },
    });

    const newToken = await createSessionToken({ sub: sess.sub, role: sess.role, name });
    const cookieStore = await cookies();
    cookieStore.set("session", newToken, SESSION_COOKIE_OPTIONS);
    redirect("/member/profile?saved=1");
  }

  async function changePassword(formData: FormData) {
    "use server";
    const sess = await getSession();
    if (!sess) return;

    const oldPassword = String(formData.get("oldPassword") || "");
    const newPassword = String(formData.get("newPassword") || "");
    const confirmPassword = String(formData.get("confirmPassword") || "");

    if (!oldPassword || !newPassword || !confirmPassword) redirect("/member/profile?pwerror=empty");
    if (newPassword.length < 8) redirect("/member/profile?pwerror=short");
    if (newPassword !== confirmPassword) redirect("/member/profile?pwerror=mismatch");

    const dbUser = await prisma.user.findUnique({
      where: { id: sess.sub },
      select: { passwordHash: true },
    });
    if (!dbUser?.passwordHash) redirect("/member/profile?pwerror=nohash");

    const valid = await bcrypt.compare(oldPassword, dbUser.passwordHash);
    if (!valid) redirect("/member/profile?pwerror=wrong");

    const newHash = await bcrypt.hash(newPassword, 12);
    await prisma.user.update({ where: { id: sess.sub }, data: { passwordHash: newHash } });
    redirect("/member/profile?pwsaved=1");
  }

  async function updateAddress(formData: FormData) {
    "use server";
    const sess = await getSession();
    if (!sess) return;

    const addressId = String(formData.get("addressId") || "").trim();
    const label = String(formData.get("label") || "Rumah").trim();
    const recipientName = String(formData.get("recipientName") || "").trim();
    const phone = String(formData.get("phone") || "").trim();
    const address = String(formData.get("address") || "").trim();
    const city = String(formData.get("city") || "").trim();
    const postalCode = String(formData.get("postalCode") || "").trim();
    const latitudeRaw = String(formData.get("latitude") || "").trim();
    const longitudeRaw = String(formData.get("longitude") || "").trim();
    const pinpointAddress = String(formData.get("pinpointAddress") || "").trim() || null;
    const streetName = String(formData.get("streetName") || "").trim() || null;
    const latitude = latitudeRaw ? Number(latitudeRaw) : null;
    const longitude = longitudeRaw ? Number(longitudeRaw) : null;

    if (!addressId || !recipientName || !phone || !address || !city || !postalCode) return;

    const existingAddress = await prisma.address.findFirst({
      where: { id: addressId, userId: sess.sub },
      select: { id: true },
    });
    if (!existingAddress) return;

    await prisma.address.update({
      where: { id: addressId },
      data: {
        label,
        recipientName,
        phone,
        address,
        latitude: Number.isFinite(latitude) ? latitude : null,
        longitude: Number.isFinite(longitude) ? longitude : null,
        pinpointAddress,
        streetName,
        city,
        postalCode,
      },
    });

    redirect("/member/profile?addrupdated=1");
  }

  async function setMainAddress(formData: FormData) {
    "use server";
    const sess = await getSession();
    if (!sess) return;

    const addressId = String(formData.get("addressId"));
    await prisma.$transaction([
      prisma.address.updateMany({ where: { userId: sess.sub }, data: { isMain: false } }),
      prisma.address.update({ where: { id: addressId }, data: { isMain: true } }),
    ]);
    revalidatePath("/member/profile");
  }

  async function deleteAddress(formData: FormData) {
    "use server";
    const sess = await getSession();
    if (!sess) return;

    const addressId = String(formData.get("addressId"));
    const addr = await prisma.address.findFirst({ where: { id: addressId, userId: sess.sub } });
    if (!addr) return;

    await prisma.address.delete({ where: { id: addressId } });

    if (addr.isMain) {
      const next = await prisma.address.findFirst({ where: { userId: sess.sub }, orderBy: { createdAt: "asc" } });
      if (next) await prisma.address.update({ where: { id: next.id }, data: { isMain: true } });
    }
    revalidatePath("/member/profile");
  }

  // ── Messages ───────────────────────────────────────────────────────────────

  const errorMessages: Record<string, string> = {
    name: "Nama tidak boleh kosong.",
    email: "Email sudah digunakan akun lain.",
    phone: "Nomor HP sudah digunakan akun lain.",
  };

  const pwErrorMessages: Record<string, string> = {
    empty: "Semua kolom password harus diisi.",
    short: "Password baru minimal 8 karakter.",
    mismatch: "Konfirmasi password tidak cocok.",
    wrong: "Password lama tidak benar.",
    nohash: "Akun ini belum mengatur password.",
  };

  // Format birthDate ke YYYY-MM-DD untuk input[type=date]
  const birthDateValue = user?.birthDate
    ? user.birthDate.toISOString().substring(0, 10)
    : "";

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
                <p className="text-lg font-black text-white">Halo, {session?.name}!</p>
              </div>
            </div>
            <LogoutButton redirectTo="/member/login" className="border-white/30 text-white hover:border-white/60" />
          </div>
          <MemberNav />
        </div>
      </div>

      <main className="mx-auto max-w-4xl px-4 py-8">
        <div className="space-y-6">

          {/* ── Edit Profil ── */}
          <section className="rounded-3xl border border-gray-100 bg-white p-6 shadow-sm">
            <h2 className="text-lg font-black text-gray-900">Edit Profil</h2>

            {saved && <Alert type="success">✅ Profil berhasil disimpan.</Alert>}
            {error && <Alert type="error">⚠️ {errorMessages[error] ?? "Terjadi kesalahan."}</Alert>}

            <form action={updateProfile} className="mt-5 space-y-4">
              <Field label="Nama lengkap" name="name" required defaultValue={user?.name ?? ""} />
              <Field label="Email" name="email" type="email" defaultValue={user?.email ?? ""} placeholder="Opsional" />
              <Field label="Nomor HP / WhatsApp" name="phone" type="tel" defaultValue={user?.phone ?? ""} placeholder="08xxxxxxxxxx" />
              <div>
                <label className="block text-sm font-medium text-gray-700">
                  Tanggal lahir
                </label>
                <input
                  type="date"
                  name="birthDate"
                  defaultValue={birthDateValue}
                  className="mt-1 block w-full rounded-xl border border-gray-200 px-4 py-3 text-sm outline-none focus:border-natalo-400"
                />
                <p className="mt-1 text-xs text-gray-400">
                  🎂 Kamu akan mendapat voucher diskon 15% di hari ulang tahunmu!
                </p>
              </div>

              <button type="submit" className="rounded-full bg-natalo-600 px-6 py-3 text-sm font-bold text-white hover:bg-natalo-700">
                Simpan profil
              </button>
            </form>
          </section>

          {/* ── Alamat Tersimpan ── */}
          <section className="rounded-3xl border border-gray-100 bg-white p-6 shadow-sm">
            <h2 className="text-lg font-black text-gray-900">Alamat Tersimpan</h2>
            <p className="mt-1 text-sm text-gray-500">Alamat utama akan otomatis dipakai saat checkout.</p>

            {addrupdated && <Alert type="success">Alamat berhasil diperbarui.</Alert>}

            {/* List alamat */}
            <div className="mt-5 space-y-3">
              {addresses.map((addr) => (
                <div
                  key={addr.id}
                  className={`rounded-2xl border p-4 ${addr.isMain ? "border-natalo-300 bg-natalo-50" : "border-gray-100 bg-gray-50"}`}
                >
                  <div className="flex flex-wrap items-start justify-between gap-3">
                    <div className="text-sm">
                      <div className="flex items-center gap-2">
                        <span className="font-bold text-gray-900">{addr.label}</span>
                        {addr.isMain && (
                          <span className="rounded-full bg-natalo-600 px-2 py-0.5 text-xs font-bold text-white">
                            Utama
                          </span>
                        )}
                      </div>
                      <p className="mt-1 text-gray-700">{addr.recipientName} · {addr.phone}</p>
                      <p className="mt-0.5 text-gray-500">{addr.address}</p>
                      {addr.streetName && (
                        <p className="mt-1 text-xs font-bold text-natalo-800">{addr.streetName}</p>
                      )}
                      {addr.pinpointAddress && (
                        <p className="mt-1 rounded-xl bg-white/70 px-3 py-2 text-xs font-semibold text-natalo-800">
                          Pinpoint: {addr.pinpointAddress}
                        </p>
                      )}
                      <p className="text-gray-500">{addr.city}, {addr.postalCode}</p>
                    </div>

                    <div className="flex gap-2">
                      {!addr.isMain && (
                        <form action={setMainAddress}>
                          <input type="hidden" name="addressId" value={addr.id} />
                          <button className="rounded-full border border-natalo-200 px-3 py-1.5 text-xs font-bold text-natalo-700 hover:bg-natalo-50">
                            Jadikan utama
                          </button>
                        </form>
                      )}
                      <form action={deleteAddress}>
                        <input type="hidden" name="addressId" value={addr.id} />
                        <button className="rounded-full border border-red-100 px-3 py-1.5 text-xs font-bold text-red-500 hover:bg-red-50">
                          Hapus
                        </button>
                      </form>
                    </div>
                  </div>

                  <details className="mt-4 rounded-2xl border border-natalo-100 bg-white/80">
                    <summary className="flex cursor-pointer items-center justify-between gap-3 rounded-2xl px-4 py-3 text-sm font-black text-natalo-800 hover:bg-natalo-50">
                      <span>Edit alamat</span>
                      <span className="text-xs text-natalo-600">Buka</span>
                    </summary>

                    <form action={updateAddress} className="space-y-4 border-t border-natalo-100 p-4">
                      <input type="hidden" name="addressId" value={addr.id} />

                      <div>
                        <label className="block text-sm font-medium text-gray-700">Label alamat</label>
                        <select
                          name="label"
                          defaultValue={addr.label}
                          className="mt-1 block w-full rounded-xl border border-gray-200 px-4 py-3 text-sm outline-none focus:border-natalo-400"
                        >
                          <option>Rumah</option>
                          <option>Kantor</option>
                          <option>Kos / Apartemen</option>
                          <option>Lainnya</option>
                        </select>
                      </div>

                      <div className="grid gap-4 sm:grid-cols-2">
                        <Field label="Nama penerima" name="recipientName" required defaultValue={addr.recipientName} />
                        <Field label="Nomor HP penerima" name="phone" type="tel" required defaultValue={addr.phone} />
                      </div>

                      <Field label="Alamat lengkap" name="address" required defaultValue={addr.address} textarea />

                      <AddressPinpointPicker
                        defaultLatitude={addr.latitude}
                        defaultLongitude={addr.longitude}
                        defaultAddress={addr.pinpointAddress}
                        defaultStreetName={addr.streetName}
                      />

                      <div className="grid gap-4 sm:grid-cols-2">
                        <Field label="Kota / Kecamatan" name="city" required defaultValue={addr.city} />
                        <Field label="Kode pos" name="postalCode" required defaultValue={addr.postalCode} />
                      </div>

                      <button type="submit" className="rounded-full bg-natalo-600 px-6 py-3 text-sm font-bold text-white hover:bg-natalo-700">
                        Simpan perubahan
                      </button>
                    </form>
                  </details>
                </div>
              ))}

              {addresses.length === 0 && (
                <p className="text-sm text-gray-400">Belum ada alamat tersimpan.</p>
              )}
            </div>

            <Link
              href="/akun/alamat/tambah"
              className="mt-5 flex items-center justify-center gap-2 rounded-2xl border border-dashed border-natalo-300 px-5 py-4 text-sm font-bold text-natalo-700 transition hover:bg-natalo-50"
            >
              <span>＋</span> Tambah Alamat Baru
            </Link>
          </section>

          {/* ── Ganti Password ── */}
          <section className="rounded-3xl border border-gray-100 bg-white p-6 shadow-sm">
            <h2 className="text-lg font-black text-gray-900">Ganti Password</h2>

            {pwsaved && <Alert type="success">✅ Password berhasil diubah.</Alert>}
            {pwerror && <Alert type="error">⚠️ {pwErrorMessages[pwerror] ?? "Terjadi kesalahan."}</Alert>}

            <form action={changePassword} className="mt-5 space-y-4">
              <Field label="Password lama" name="oldPassword" type="password" required autoComplete="current-password" />
              <div>
                <Field label="Password baru" name="newPassword" type="password" required autoComplete="new-password" />
                <p className="mt-1 text-xs text-gray-400">Minimal 8 karakter.</p>
              </div>
              <Field label="Konfirmasi password baru" name="confirmPassword" type="password" required autoComplete="new-password" />

              <button type="submit" className="rounded-full bg-zinc-900 px-6 py-3 text-sm font-bold text-white hover:bg-zinc-700">
                Ganti password
              </button>
            </form>
          </section>

        </div>
      </main>
    </div>
  );
}

// ── Helpers ────────────────────────────────────────────────────────────────

function Alert({ type, children }: { type: "success" | "error"; children: React.ReactNode }) {
  return (
    <div
      className={`mt-4 rounded-2xl p-4 text-sm font-semibold ${
        type === "success" ? "bg-green-50 text-green-700" : "bg-red-50 text-red-600"
      }`}
    >
      {children}
    </div>
  );
}

function Field({
  label,
  name,
  type = "text",
  required,
  placeholder,
  defaultValue,
  autoComplete,
  textarea,
}: {
  label: string;
  name: string;
  type?: string;
  required?: boolean;
  placeholder?: string;
  defaultValue?: string;
  autoComplete?: string;
  textarea?: boolean;
}) {
  const cls = "mt-1 block w-full rounded-xl border border-gray-200 px-4 py-3 text-sm outline-none focus:border-natalo-400";
  return (
    <div>
      <label className="block text-sm font-medium text-gray-700">
        {label}
        {required && <span className="ml-1 text-red-500">*</span>}
      </label>
      {textarea ? (
        <textarea
          name={name}
          required={required}
          placeholder={placeholder}
          defaultValue={defaultValue}
          rows={3}
          className={cls}
        />
      ) : type === "password" ? (
        <PasswordInput
          name={name}
          required={required}
          placeholder={placeholder}
          autoComplete={autoComplete}
          className={cls}
        />
      ) : (
        <input
          type={type}
          name={name}
          required={required}
          placeholder={placeholder}
          defaultValue={defaultValue}
          autoComplete={autoComplete}
          className={cls}
        />
      )}
    </div>
  );
}
