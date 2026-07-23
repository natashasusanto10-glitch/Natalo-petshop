import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import { GET as getAasa } from "@/app/.well-known/apple-app-site-association/route";
import { GET as getAssetLinks } from "@/app/.well-known/assetlinks.json/route";

test("AASA permits public Feed, product, and profile links for the production app", async () => {
  const response = await getAasa();
  const document = await response.json();
  const detail = document.applinks.details[0];
  const paths = detail.components.map((component: { "/": string }) => component["/"]);

  assert.deepEqual(detail.appIDs, ["87FXPV558A.com.natalo.petshop"]);
  assert.ok(paths.includes("/feed/*"));
  assert.ok(paths.includes("/products/*"));
  assert.ok(paths.includes("/u/*"));
});

test("Asset Links retains the production Android package and certificate", async () => {
  const response = await getAssetLinks();
  const document = await response.json();
  const target = document[0].target;

  assert.equal(target.package_name, "com.natalo.petshop");
  assert.ok(
    target.sha256_cert_fingerprints.includes(
      "B3:07:D9:B5:2C:4A:C8:DD:60:A6:25:3C:DF:E4:36:B3:99:60:DB:E5:C8:A7:AE:EE:1A:5A:07:70:28:D8:19:50",
    ),
  );
});

test("native App Links and Universal Links remain configured for both public hosts", async () => {
  const [manifest, entitlements] = await Promise.all([
    readFile("flutter_app/android/app/src/main/AndroidManifest.xml", "utf8"),
    readFile("flutter_app/ios/Runner/Runner.entitlements", "utf8"),
  ]);

  assert.match(manifest, /android:autoVerify="true"/);
  assert.match(manifest, /android:scheme="https" android:host="natalopetshop\.com"/);
  assert.match(manifest, /android:scheme="https" android:host="www\.natalopetshop\.com"/);
  assert.match(entitlements, /applinks:natalopetshop\.com/);
  assert.match(entitlements, /applinks:www\.natalopetshop\.com/);
});
