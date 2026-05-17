import type { Metadata } from "next";
import packageJson from "@/package.json";
import { AccountSettingsClient } from "@/components/account/AccountSettingsClient";
import { PageStatusBar } from "@/components/PageStatusBar";
import { requireCustomerSession } from "@/lib/session-guards";

export const metadata: Metadata = { title: "Pengaturan" };

export default async function AccountSettingsPage() {
  await requireCustomerSession();

  return (
    <>
      <PageStatusBar
        iconColor="dark"
        themeColor="#ffffff"
        nativeBackgroundColor="#ffffff"
        overlaysWebView={false}
      />
      <AccountSettingsClient appVersion={packageJson.version} />
    </>
  );
}
