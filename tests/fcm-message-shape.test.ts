import assert from "node:assert/strict";
import test, { describe } from "node:test";
import { buildFcmMulticastMessage } from "@/lib/fcm";

const base = {
  title: "Budi menandai Anda dalam postingan",
  body: "Lihat postingannya sekarang.",
  url: "/feed/p1",
  tag: "feed-tagged-p1-u1",
  data: { type: "feed_tagged", url: "/feed/p1" },
  imageUrl: "https://cdn/img.jpg",
  prefCategory: "feed" as const,
};

describe("buildFcmMulticastMessage", () => {
  test("sosial + token capable → Android data-only, iOS alert+mutable", () => {
    const m: any = buildFcmMulticastMessage(
      { ...base, renderClientSide: true, actorAvatarUrl: "https://cdn/ava.jpg" },
      { clientRender: true },
    );
    assert.equal(m.notification, undefined);
    assert.equal(m.android.notification, undefined);
    assert.equal(m.android.priority, "high");
    assert.equal(m.data.title, base.title);
    assert.equal(m.data.actor_avatar_url, "https://cdn/ava.jpg");
    assert.deepEqual(m.apns.payload.aps.alert, { title: base.title, body: base.body });
    assert.equal(m.apns.payload.aps["mutable-content"], 1);
  });
  test("actorAvatarUrl http:// (non-https) → TIDAK diteruskan ke data", () => {
    const m: any = buildFcmMulticastMessage(
      { ...base, renderClientSide: true, actorAvatarUrl: "http://cdn/ava.jpg" },
      { clientRender: true },
    );
    assert.equal(m.data.actor_avatar_url, undefined);
  });
  test("sosial + token LAMA → shape lama utuh (notification block ada)", () => {
    const m: any = buildFcmMulticastMessage(
      { ...base, renderClientSide: true, actorAvatarUrl: "https://cdn/ava.jpg" },
      { clientRender: false },
    );
    assert.equal(m.notification.title, base.title);
    assert.equal(m.android.notification.clickAction, "FCM_PLUGIN_ACTIVITY");
    assert.equal(m.apns.payload.aps.alert, undefined);
  });
  test("non-sosial → shape lama apapun kapabilitasnya", () => {
    const m: any = buildFcmMulticastMessage(base, { clientRender: true });
    assert.equal(m.notification.title, base.title);
    assert.equal(m.data.actor_avatar_url, undefined);
  });
  test("user_followed + token capable → Android data-only, actor avatar terkirim", () => {
    const m: any = buildFcmMulticastMessage(
      {
        title: "Pengikut baru",
        body: "Budi mulai mengikuti kamu.",
        url: "/u/budi",
        tag: "user_followed-u1-u2",
        data: { type: "user_followed", url: "/u/budi" },
        imageUrl: "https://cdn/ava.jpg",
        renderClientSide: true,
        actorAvatarUrl: "https://cdn/ava.jpg",
      },
      { clientRender: true },
    );
    assert.equal(m.notification, undefined);
    assert.equal(m.android.notification, undefined);
    assert.equal(m.data.actor_avatar_url, "https://cdn/ava.jpg");
    assert.deepEqual(m.apns.payload.aps.alert, {
      title: "Pengikut baru",
      body: "Budi mulai mengikuti kamu.",
    });
  });
});
