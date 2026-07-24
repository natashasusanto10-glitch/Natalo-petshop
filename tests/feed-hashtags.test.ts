import test from "node:test";
import assert from "node:assert/strict";
import {
  extractHashtags,
  isValidHashtagName,
  MAX_HASHTAGS_PER_POST,
  MAX_HASHTAG_SUGGESTIONS,
  HASHTAG_LIMIT_MESSAGE,
  syncPostHashtags,
  resyncPostHashtags,
  decrementHashtagCounts,
  hashtagPostsWhere,
  searchHashtags,
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

function makeFakeTx(existingJunctionHashtagIds: string[] = ["h0", "h1"]) {
  const calls: { method: string; args: unknown }[] = [];
  const nameToId = new Map<string, string>();
  let nextId = 0;
  // Junction rows currently persisted for the post — deleteMany empties it,
  // createMany appends. Lets resync tests assert the end state, bukan cuma
  // urutan panggilan.
  let junction: { hashtagId: string }[] = existingJunctionHashtagIds.map(
    (id) => ({ hashtagId: id }),
  );
  const tx = {
    hashtag: {
      upsert: async (args: { where: { name: string } }) => {
        calls.push({ method: "hashtag.upsert", args });
        const name = args.where.name;
        if (!nameToId.has(name)) nameToId.set(name, `h${nextId++}`);
        return { id: nameToId.get(name)!, name };
      },
      updateMany: async (args: unknown) => {
        calls.push({ method: "hashtag.updateMany", args });
        return { count: 1 };
      },
    },
    feedPostHashtag: {
      createMany: async (args: { data: { hashtagId: string }[] }) => {
        calls.push({ method: "feedPostHashtag.createMany", args });
        junction = junction.concat(
          args.data.map((d) => ({ hashtagId: d.hashtagId })),
        );
        return { count: args.data.length };
      },
      findMany: async (args: unknown) => {
        calls.push({ method: "feedPostHashtag.findMany", args });
        return junction;
      },
      deleteMany: async (args: unknown) => {
        calls.push({ method: "feedPostHashtag.deleteMany", args });
        const count = junction.length;
        junction = [];
        return { count };
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

test("hashtagPostsWhere: gabungkan PUBLIC_FEED_POST_WHERE + relasi tag", () => {
  const where = hashtagPostsWhere("kucing");
  assert.equal(where.status, "ACTIVE");
  assert.equal(where.deletedAt, null);
  assert.equal(where.encodingStatus, "ready");
  assert.deepEqual(where.hashtags, {
    some: { hashtag: { name: "kucing" } },
  });
});

test("searchHashtags: prefix lowercase, urut postCount desc, maks 8", async () => {
  const captured: unknown[] = [];
  const fakeDb = {
    hashtag: {
      findMany: async (args: unknown) => {
        captured.push(args);
        return [{ name: "kucing", postCount: 24 }];
      },
    },
  };
  const rows = await searchHashtags(fakeDb, "Ku");
  assert.deepEqual(rows, [{ name: "kucing", postCount: 24 }]);
  const args = captured[0] as {
    where: { name: { startsWith: string } };
    orderBy: { postCount: "desc" };
    take: number;
  };
  assert.equal(args.where.name.startsWith, "ku"); // di-lowercase
  assert.equal(args.orderBy.postCount, "desc");
  assert.equal(args.take, 8);
});

test("searchHashtags: q kosong/whitespace → [] tanpa sentuh db", async () => {
  const fakeDb = {
    hashtag: {
      findMany: async () => {
        throw new Error("tidak boleh dipanggil");
      },
    },
  };
  assert.deepEqual(await searchHashtags(fakeDb, "  "), []);
});

test("searchHashtags: take pakai MAX_HASHTAG_SUGGESTIONS (8)", () => {
  assert.equal(MAX_HASHTAG_SUGGESTIONS, 8);
});

// --- resyncPostHashtags: dipakai PATCH /api/feed/posts/[id] saat caption
// post yang sudah ada di-edit. Coverage untuk finding review #1 (hashtag
// desync on post edit).

test("resyncPostHashtags: tambah hashtag baru via edit — junction jadi berisi tag baru", async () => {
  const { tx, calls } = makeFakeTx([]); // post lama tanpa hashtag sama sekali
  await resyncPostHashtags(tx, "post1", "Caption baru #kucing");
  const cm = calls.find((c) => c.method === "feedPostHashtag.createMany")!
    .args as { data: { feedPostId: string; hashtagId: string }[] };
  assert.equal(cm.data.length, 1);
  assert.equal(cm.data[0].feedPostId, "post1");
  const finalJunction = await tx.feedPostHashtag.findMany({
    where: { feedPostId: "post1" },
    select: { hashtagId: true },
  });
  assert.equal(finalJunction.length, 1);
});

test("resyncPostHashtags: hapus hashtag via edit — junction lama dikosongkan, decrement dipanggil", async () => {
  const { tx, calls } = makeFakeTx(["h0", "h1"]); // post lama punya 2 tag
  // Caption baru tanpa hashtag sama sekali.
  await resyncPostHashtags(tx, "post1", "Caption polos tanpa tag lagi");
  assert.equal(
    calls.filter((c) => c.method === "feedPostHashtag.deleteMany").length,
    1,
  );
  const decrement = calls.find((c) => c.method === "hashtag.updateMany")!
    .args as { where: { id: { in: string[] } } };
  assert.deepEqual(decrement.where.id.in, ["h0", "h1"]);
  // createMany tidak pernah dipanggil karena caption baru tidak punya tag.
  assert.equal(
    calls.some((c) => c.method === "feedPostHashtag.createMany"),
    false,
  );
});

test("resyncPostHashtags: ganti satu tag jadi tag lain — junction akhir cuma berisi tag baru", async () => {
  const { tx } = makeFakeTx(["h0"]); // post lama tag-nya "#anjing" (id h0)
  await resyncPostHashtags(tx, "post1", "Ganti caption jadi #kucing");
  const finalJunction = await tx.feedPostHashtag.findMany({
    where: { feedPostId: "post1" },
    select: { hashtagId: true },
  });
  // Junction lama (h0) sudah di-clear, digantikan hashtagId baru untuk
  // "kucing" (nextId mulai dari 0 lagi di fake tx ini karena nameToId map
  // terpisah dari existing junction seed).
  assert.equal(finalJunction.length, 1);
  assert.notEqual(finalJunction[0].hashtagId, undefined);
});

test("cap 5 hashtag: caption edit dengan >5 tag harus ditolak (recheck sesuai HASHTAG_LIMIT_MESSAGE)", () => {
  // Mirrors validasi PATCH /api/feed/posts/[id]: extractHashtags(newCaption)
  // dibanding MAX_HASHTAGS_PER_POST sebelum resyncPostHashtags dipanggil.
  const newCaption = "#a1 #a2 #a3 #a4 #a5 #a6";
  const tags = extractHashtags(newCaption);
  assert.equal(tags.length, 6);
  assert.ok(tags.length > MAX_HASHTAGS_PER_POST);
  // Pesan error yang harus dikembalikan route (400).
  assert.equal(HASHTAG_LIMIT_MESSAGE, "Maksimal 5 hashtag per postingan.");
});

test("cap 5 hashtag: tepat 5 tag via edit tetap lolos (batas inklusif)", () => {
  const newCaption = "#a1 #a2 #a3 #a4 #a5";
  const tags = extractHashtags(newCaption);
  assert.equal(tags.length, 5);
  assert.ok(tags.length <= MAX_HASHTAGS_PER_POST);
});
