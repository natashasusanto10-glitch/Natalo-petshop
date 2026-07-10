import BirthDateOverrideClient from "./BirthDateOverrideClient";
import { PageHeader, Button } from "@/components/admin/ui";

export const dynamic = "force-dynamic";

export default function BirthDateOverridePage() {
  return (
    <>
      <div className="mx-auto max-w-3xl px-4 py-5 md:py-10">
        <PageHeader
          title="🎂 Override Tanggal Lahir"
          subtitle="CS tool — set ulang tanggal lahir customer yang ke-lock setelah dapat voucher ultah. Audit logged."
          actions={
            <Button href="/admin/dashboard" variant="secondary" size="sm">
              ← Dashboard
            </Button>
          }
        />
      </div>
      <BirthDateOverrideClient />
    </>
  );
}
