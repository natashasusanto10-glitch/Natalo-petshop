import Link from "next/link";
import BirthDateOverrideClient from "./BirthDateOverrideClient";

export const dynamic = "force-dynamic";

export default function BirthDateOverridePage() {
  return (
    <>
      <div className="mx-auto max-w-3xl px-4 pt-4">
        <Link
          href="/admin"
          className="text-sm font-bold text-zinc-500 hover:text-zinc-950"
        >
          ← Kembali ke dashboard
        </Link>
      </div>
      <BirthDateOverrideClient />
    </>
  );
}
