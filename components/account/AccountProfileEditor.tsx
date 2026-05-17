"use client";

import Link from "next/link";
import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import {
  FiArrowLeft,
  FiCamera,
  FiImage,
  FiTrash2,
  FiUpload,
} from "react-icons/fi";
import { BottomSheet } from "@/components/BottomSheet";
import { natToast } from "@/components/Toast";
import { pickPhoto } from "@/lib/photo-picker";
import {
  AccountProfileAvatar,
  dispatchProfilePhotoUpdated,
  profilePhotoStorageKey,
} from "@/components/account/AccountProfileAvatar";

type ProfileForm = {
  name: string;
  phone: string;
  birthDate: string;
};

type Props = {
  userId: string;
  initialName: string;
  initialPhone: string | null;
  initialBirthDate: string | null;
  email: string | null;
};

function buildInitialForm(
  initialName: string,
  initialPhone: string | null,
  initialBirthDate: string | null,
): ProfileForm {
  return {
    name: initialName,
    phone: initialPhone ?? "",
    birthDate: initialBirthDate ?? "",
  };
}

function blobToDataUrl(blob: Blob) {
  return new Promise<string>((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result));
    reader.onerror = () => reject(new Error("Gagal membaca foto."));
    reader.readAsDataURL(blob);
  });
}

export function AccountProfileEditor({
  userId,
  initialName,
  initialPhone,
  initialBirthDate,
  email,
}: Props) {
  const router = useRouter();
  const savedTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [initialForm, setInitialForm] = useState<ProfileForm>(() =>
    buildInitialForm(initialName, initialPhone, initialBirthDate),
  );
  const [form, setForm] = useState<ProfileForm>(initialForm);
  const [saving, setSaving] = useState(false);
  const [photoBusy, setPhotoBusy] = useState(false);
  const [photoSheetOpen, setPhotoSheetOpen] = useState(false);
  const [deletePhotoOpen, setDeletePhotoOpen] = useState(false);
  const [hasPhoto, setHasPhoto] = useState(false);

  const hasChanges = useMemo(
    () =>
      form.name !== initialForm.name ||
      form.phone !== initialForm.phone ||
      form.birthDate !== initialForm.birthDate,
    [form, initialForm],
  );

  useEffect(() => {
    const nextInitialForm = buildInitialForm(initialName, initialPhone, initialBirthDate);
    setInitialForm(nextInitialForm);
    setForm(nextInitialForm);
  }, [initialName, initialPhone, initialBirthDate]);

  useEffect(() => {
    function syncPhotoState() {
      try {
        setHasPhoto(Boolean(localStorage.getItem(profilePhotoStorageKey(userId))));
      } catch {
        setHasPhoto(false);
      }
    }

    syncPhotoState();
    window.addEventListener("account-profile-photo-updated", syncPhotoState);
    window.addEventListener("storage", syncPhotoState);
    return () => {
      window.removeEventListener("account-profile-photo-updated", syncPhotoState);
      window.removeEventListener("storage", syncPhotoState);
      if (savedTimerRef.current) clearTimeout(savedTimerRef.current);
    };
  }, [userId]);

  function update(field: keyof ProfileForm, value: string) {
    if (savedTimerRef.current) {
      clearTimeout(savedTimerRef.current);
      savedTimerRef.current = null;
    }
    setForm((prev) => ({ ...prev, [field]: value }));
  }

  async function saveProfile(event?: React.FormEvent) {
    event?.preventDefault();
    if (!hasChanges || saving) return;

    const nextForm: ProfileForm = {
      name: form.name.trim(),
      phone: form.phone.trim(),
      birthDate: form.birthDate,
    };

    setSaving(true);
    try {
      const res = await fetch("/api/member/profile", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: nextForm.name,
          phone: nextForm.phone || null,
          birthDate: nextForm.birthDate || null,
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? "Gagal menyimpan profil.");
      setForm(nextForm);
      setInitialForm(nextForm);
      natToast("Profil berhasil diperbarui.", { kind: "ok" });
      window.dispatchEvent(new Event("auth-updated"));
      router.refresh();
    } catch (err) {
      natToast(
        err instanceof Error ? err.message : "Profil belum berhasil diperbarui. Coba lagi ya.",
        { kind: "err" },
      );
    } finally {
      setSaving(false);
    }
  }

  async function choosePhoto(source: "camera" | "photos") {
    setPhotoBusy(true);
    try {
      const result = await pickPhoto({
        source,
        quality: 82,
        maxWidth: 768,
        maxHeight: 768,
      });

      if (!result.ok) {
        if (!("cancelled" in result && result.cancelled)) {
          natToast(
            "Foto profil belum berhasil diperbarui. Coba lagi ya.",
            { kind: "err" },
          );
        }
        return;
      }

      const dataUrl = await blobToDataUrl(result.blob);
      localStorage.setItem(profilePhotoStorageKey(userId), dataUrl);
      dispatchProfilePhotoUpdated();
      setPhotoSheetOpen(false);
      natToast("Foto profil berhasil diperbarui", { kind: "ok" });
    } catch {
      natToast(
        "Natalo perlu akses kamera atau galeri untuk memperbarui foto profil. Kamu bisa mengaktifkannya dari pengaturan HP.",
        { kind: "err" },
      );
    } finally {
      setPhotoBusy(false);
    }
  }

  function deletePhoto() {
    try {
      localStorage.removeItem(profilePhotoStorageKey(userId));
      dispatchProfilePhotoUpdated();
      setDeletePhotoOpen(false);
      setPhotoSheetOpen(false);
      natToast("Foto profil berhasil dihapus", { kind: "ok" });
    } catch {
      natToast("Foto profil belum berhasil dihapus. Coba lagi ya.", { kind: "err" });
    }
  }

  return (
    <main className="min-h-screen bg-[#F6F9FF] pb-[calc(2rem+env(safe-area-inset-bottom))]">
      <header className="sticky top-0 z-[1050] border-b border-slate-200/80 bg-white px-4 pb-3 shadow-[0_8px_24px_rgba(15,23,42,0.06)] [padding-top:calc(0.75rem+env(safe-area-inset-top))]">
        <div className="mx-auto flex max-w-2xl items-center gap-3">
          <Link
            href="/account/settings"
            aria-label="Kembali ke pengaturan"
            className="-ml-1 grid h-11 w-11 shrink-0 place-items-center rounded-full text-slate-800 transition active:bg-slate-100"
          >
            <FiArrowLeft className="h-5 w-5" aria-hidden="true" />
          </Link>
          <h1 className="min-w-0 flex-1 truncate text-xl font-black text-slate-950">
            Ubah Profil
          </h1>
          <button
            type="submit"
            form="account-profile-form"
            disabled={!hasChanges || saving}
            className="h-10 rounded-full bg-natalo-600 px-4 text-sm font-black text-white transition active:scale-[0.98] disabled:cursor-not-allowed disabled:bg-slate-200 disabled:text-slate-500"
          >
            {saving ? "Menyimpan..." : "Simpan"}
          </button>
        </div>
      </header>

      <div className="mx-auto max-w-2xl px-4 py-5">
        <section className="rounded-[24px] border border-slate-100 bg-white p-5 text-center shadow-[0_8px_24px_rgba(16,24,40,0.06)]">
          <div className="relative mx-auto w-fit">
            <AccountProfileAvatar
              userId={userId}
              name={form.name || initialName}
              size="xl"
              className="bg-gradient-to-br from-natalo-500 to-natalo-700"
            />
            <span className="absolute bottom-1 right-1 grid h-9 w-9 place-items-center rounded-full border-4 border-white bg-natalo-600 text-white shadow-sm">
              <FiCamera className="h-4 w-4" aria-hidden="true" />
            </span>
          </div>
          <button
            type="button"
            onClick={() => setPhotoSheetOpen(true)}
            disabled={photoBusy}
            className="mt-4 inline-flex h-10 items-center gap-2 rounded-full bg-[#EAF2FF] px-4 text-sm font-black text-natalo-700 transition active:scale-[0.98] disabled:opacity-60"
          >
            <FiUpload className="h-4 w-4" aria-hidden="true" />
            {photoBusy ? "Memproses..." : "Ubah Foto"}
          </button>
          <p className="mt-2 text-xs font-semibold text-slate-500">
            Gunakan foto yang jelas agar mudah dikenali.
          </p>
        </section>

        <form
          id="account-profile-form"
          onSubmit={saveProfile}
          className="mt-5 space-y-4 rounded-[24px] border border-slate-100 bg-white p-5 shadow-[0_8px_24px_rgba(16,24,40,0.06)]"
        >
          <ProfileField label="Nama Lengkap" required>
            <input
              type="text"
              required
              value={form.name}
              onChange={(event) => update("name", event.target.value)}
              className="account-profile-input"
              placeholder="Nama lengkap"
            />
          </ProfileField>

          <ProfileField label="Email">
            <input
              type="email"
              readOnly
              value={email ?? ""}
              className="account-profile-input bg-slate-50 text-slate-500"
              placeholder="Email belum tersedia"
            />
          </ProfileField>

          <ProfileField label="No. Handphone">
            <input
              type="tel"
              value={form.phone}
              onChange={(event) => update("phone", event.target.value)}
              className="account-profile-input"
              placeholder="08xxxxxxxxxx atau +628xxxxxxxxxx"
            />
          </ProfileField>

          <ProfileField label="Tanggal Lahir">
            <input
              type="date"
              value={form.birthDate}
              onChange={(event) => update("birthDate", event.target.value)}
              max={new Date().toISOString().split("T")[0]}
              className="account-profile-input"
            />
          </ProfileField>
        </form>
      </div>

      <BottomSheet
        open={photoSheetOpen}
        onClose={() => setPhotoSheetOpen(false)}
        title="Foto Profil"
      >
        <div className="space-y-2">
          <PhotoOption
            icon={<FiCamera className="h-5 w-5" aria-hidden="true" />}
            title="Ambil Foto"
            subtitle="Gunakan kamera"
            onClick={() => void choosePhoto("camera")}
            disabled={photoBusy}
          />
          <PhotoOption
            icon={<FiImage className="h-5 w-5" aria-hidden="true" />}
            title="Pilih dari Galeri"
            subtitle="Pilih foto dari galeri"
            onClick={() => void choosePhoto("photos")}
            disabled={photoBusy}
          />
          {hasPhoto && (
            <PhotoOption
              icon={<FiTrash2 className="h-5 w-5" aria-hidden="true" />}
              title="Hapus Foto"
              subtitle="Hapus foto profil saat ini"
              danger
              onClick={() => setDeletePhotoOpen(true)}
              disabled={photoBusy}
            />
          )}
        </div>
      </BottomSheet>

      <BottomSheet
        open={deletePhotoOpen}
        onClose={() => setDeletePhotoOpen(false)}
        title="Hapus foto profil?"
        footer={
          <div className="grid grid-cols-2 gap-3">
            <button
              type="button"
              onClick={() => setDeletePhotoOpen(false)}
              className="h-11 rounded-full border border-slate-200 bg-white text-sm font-black text-slate-700 transition active:scale-[0.98]"
            >
              Batal
            </button>
            <button
              type="button"
              onClick={deletePhoto}
              className="h-11 rounded-full bg-red-500 text-sm font-black text-white transition active:scale-[0.98]"
            >
              Hapus
            </button>
          </div>
        }
      >
        <p className="text-sm font-semibold leading-6 text-slate-500">
          Foto profil kamu akan dihapus dan avatar akan kembali memakai inisial nama.
        </p>
      </BottomSheet>
    </main>
  );
}

function ProfileField({
  label,
  required,
  children,
}: {
  label: string;
  required?: boolean;
  children: React.ReactNode;
}) {
  return (
    <label className="block">
      <span className="text-sm font-black text-slate-800">
        {label}
        {required && <span className="text-natalo-600"> *</span>}
      </span>
      <span className="mt-2 block">{children}</span>
    </label>
  );
}

function PhotoOption({
  icon,
  title,
  subtitle,
  danger,
  disabled,
  onClick,
}: {
  icon: React.ReactNode;
  title: string;
  subtitle: string;
  danger?: boolean;
  disabled?: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className="flex w-full items-center gap-3 rounded-2xl px-3 py-3 text-left transition active:bg-slate-50 disabled:opacity-60"
    >
      <span
        className={`grid h-11 w-11 shrink-0 place-items-center rounded-2xl ${
          danger ? "bg-red-50 text-red-500" : "bg-[#EAF2FF] text-natalo-600"
        }`}
      >
        {icon}
      </span>
      <span className="min-w-0 flex-1">
        <span className={`block text-sm font-black ${danger ? "text-red-600" : "text-slate-950"}`}>
          {title}
        </span>
        <span className="mt-0.5 block text-xs font-semibold text-slate-500">
          {subtitle}
        </span>
      </span>
    </button>
  );
}
