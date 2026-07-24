import test from "node:test";
import assert from "node:assert/strict";
import {
  extractHashtags,
  isValidHashtagName,
  MAX_HASHTAGS_PER_POST,
  HASHTAG_LIMIT_MESSAGE,
  syncPostHashtags,
  decrementHashtagCounts,
} from "../lib/feed/hashtags";

test("extractHashtags: dasar — lowercase, urutan kemunculan", () => {
  assert.deepEqual(extractHashtags("Halo #KucingLucu dan #anjing_kecil"), [
    "kucinglucu",
    "anjing_kecil",
  ]);
});

test("extractHashtags: boundary — mid-word & URL fragment ditolak", () => {
  assert.deepEqual(extractHashtags("harga#promo cek natalo.com/#promo"), []);
  assert.deepEqual(extractHashtags("#promo di awal teks"), ["promo"]);
  assert.deepEqual(extractHashtags("baris\n#baru juga valid"), ["baru"]);
});

test("extractHashtags: panjang 2-50 di-filter", () => {
  assert.deepEqual(extractHashtags("#a #ab"), ["ab"]);
  const long = "x".repeat(51);
  const max = "y".repeat(50);
  assert.deepEqual(extractHashtags(`#${long} #${max}`), [max]);
});

test("extractHashtags: dedup case-insensitive, sekali hitung", () => {
  assert.deepEqual(extractHashtags("#Kucing #kucing #KUCING #lain"), [
    "kucing",
    "lain",
  ]);
});

test("extractHashtags: angka & underscore boleh; teks kosong aman", () => {
  assert.deepEqual(extractHashtags("#tag_2026 ok"), ["tag_2026"]);
  assert.deepEqual(extractHashtags(""), []);
});

test("isValidHashtagName: hanya nama kanonik yang lolos", () => {
  assert.equal(isValidHashtagName("kucing_2"), true);
  assert.equal(isValidHashtagName("ab"), true);
  assert.equal(isValidHashtagName("a"), false);
  assert.equal(isValidHashtagName("Kucing"), false); // wajib lowercase
  assert.equal(isValidHashtagName("ku cing"), false);
  assert.equal(isValidHashtagName("x".repeat(51)), false);
});

test("konstanta limit & pesan sesuai spec", () => {
  assert.equal(MAX_HASHTAGS_PER_POST, 5);
  assert.equal(HASHTAG_LIMIT_MESSAGE, "Maksimal 5 hashtag per postingan.");
});

function makeFakeTx() {
  const calls: { method: string; args: unknown }[] = [];
  let nextId = 0;
  const tx = {
    hashtag: {
      upsert: async (args: { where: { name: string } }) => {
        calls.push({ method: "hashtag.upsert", args });
        return { id: `h${nextId++}`, name: args.where.name };
      },
      updateMany: async (args: unknown) => {
        calls.push({ method: "hashtag.updateMany", args });
        return { count: 1 };
      },
    },
    feedPostHashtag: {
      createMany: async (args: unknown) => {
        calls.push({ method: "feedPostHashtag.createMany", args });
        return { count: 1 };
      },
      findMany: async (args: unknown) => {
        calls.push({ method: "feedPostHashtag.findMany", args });
        return [{ hashtagId: "h0" }, { hashtagId: "h1" }];
      },
    },
  };
  return { tx, calls };
}

test("syncPostHashtags: upsert per tag (increment postCount) + junction createMany", async () => {
  const { tx, calls } = makeFakeTx();
  await syncPostHashtags(tx, "post1", "Halo #kucing dan #Anjing");
  const upserts = calls.filter((c) => c.method === "hashtag.upsert");
  assert.equal(upserts.length, 2);
  const first = upserts[0].args as {
    where: { name: string };
    create: { name: string; postCount: number };
    update: { postCount: { increment: number } };
  };
  assert.equal(first.where.name, "kucing");
  assert.equal(first.create.postCount, 1);
  assert.equal(first.update.postCount.increment, 1);
  const cm = calls.find((c) => c.method === "feedPostHashtag.createMany")!
    .args as { data: { feedPostId: string; hashtagId: string }[] };
  assert.deepEqual(
    cm.data.map((d) => d.feedPostId),
    ["post1", "post1"],
  );
});

test("syncPostHashtags: caption tanpa tag → tidak menyentuh db", async () => {
  const { tx, calls } = makeFakeTx();
  await syncPostHashtags(tx, "post1", "caption polos tanpa tag");
  assert.equal(calls.length, 0);
});

test("decrementHashtagCounts: baca junction lalu decrement tiap hashtagId", async () => {
  const { tx, calls } = makeFakeTx();
  await decrementHashtagCounts(tx, "post1");
  assert.equal(
    calls.filter((c) => c.method === "feedPostHashtag.findMany").length,
    1,
  );
  const upd = calls.find((c) => c.method === "hashtag.updateMany")!.args as {
    where: { id: { in: string[] }; postCount: { gt: number } };
    data: { postCount: { decrement: number } };
  };
  assert.deepEqual(upd.where.id.in, ["h0", "h1"]);
  assert.equal(upd.where.postCount.gt, 0); // guard: jangan minus
  assert.equal(upd.data.postCount.decrement, 1);
});
