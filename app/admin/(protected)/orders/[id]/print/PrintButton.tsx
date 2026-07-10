"use client";

import { Button } from "@/components/admin/ui";

export function PrintButton() {
  return (
    <Button
      type="button"
      onClick={() => window.print()}
      className="print:hidden"
    >
      Print Resi
    </Button>
  );
}
