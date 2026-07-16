import assert from "node:assert/strict";
import test from "node:test";
import {
  buildMutualFollowerWhere,
  loadMutualFollowers,
  type MutualFollowerDependencies,
} from "@/lib/social/profile-mutual-followers";

test("mutual query intersects viewer following with target followers", () => {
  assert.deepEqual(buildMutualFollowerWhere("viewer-1", "official-1"), {
    followingId: "official-1",
    follower: {
      followers: {
        some: { followerId: "viewer-1" },
      },
    },
  });
});

test("mutuals are gated only to authenticated non-owner viewers", async () => {
  let calls = 0;
  const dependencies: MutualFollowerDependencies = {
    findMany: async () => {
      calls += 1;
      return [];
    },
    count: async () => {
      calls += 1;
      return 0;
    },
  };

  // Not logged in, or viewing own profile → never query, regardless of
  // whether the target is official or a regular account.
  for (const input of [
    { viewerUserId: null, targetUserId: "official-1", isOwner: false },
    { viewerUserId: null, targetUserId: "user-1", isOwner: false },
    { viewerUserId: "official-1", targetUserId: "official-1", isOwner: true },
    { viewerUserId: "user-1", targetUserId: "user-1", isOwner: true },
  ]) {
    assert.deepEqual(await loadMutualFollowers(input, dependencies), {
      items: [],
      totalCount: 0,
    });
  }
  assert.equal(calls, 0);
});

test("mutuals ARE computed for regular (non-official) profiles", async () => {
  let calls = 0;
  const dependencies: MutualFollowerDependencies = {
    findMany: async () => {
      calls += 1;
      return [
        {
          follower: {
            id: "shared-1",
            name: "Rani",
            username: "rani",
            profilePhotoUrl: null,
            role: "CUSTOMER",
          },
        },
      ];
    },
    count: async () => {
      calls += 1;
      return 3;
    },
  };

  const result = await loadMutualFollowers(
    { viewerUserId: "viewer-1", targetUserId: "regular-1", isOwner: false },
    dependencies,
  );

  assert.equal(calls, 2);
  assert.equal(result.totalCount, 3);
  assert.equal(result.items[0]?.name, "Rani");
});

test("mutuals brandify admin previews and preserve total count", async () => {
  const dependencies: MutualFollowerDependencies = {
    findMany: async () => [
      {
        follower: {
          id: "admin-2",
          name: "Private Admin Name",
          username: "admin-two",
          profilePhotoUrl: "https://cdn.example/admin.jpg",
          role: "ADMIN",
        },
      },
      {
        follower: {
          id: "user-2",
          name: "Mona",
          username: "mona",
          profilePhotoUrl: "https://cdn.example/mona.jpg",
          role: "CUSTOMER",
        },
      },
    ],
    count: async () => 7,
  };

  const result = await loadMutualFollowers(
    {
      viewerUserId: "viewer-1",
      targetUserId: "official-1",
      isOwner: false,
    },
    dependencies,
  );

  assert.equal(result.totalCount, 7);
  assert.deepEqual(result.items[0], {
    id: "admin-2",
    name: "Natalo Petshop Official",
    username: "admin-two",
    profilePhotoUrl: null,
    isOfficial: true,
  });
  assert.equal(result.items[1]?.name, "Mona");
});

test("legacy mutual previews always expose a stable non-empty public label", async () => {
  const dependencies: MutualFollowerDependencies = {
    findMany: async () => [
      {
        follower: {
          id: "named-user",
          name: "  Mona  ",
          username: "mona",
          profilePhotoUrl: null,
          role: "CUSTOMER",
        },
      },
      {
        follower: {
          id: "username-user",
          name: "   ",
          username: "  legacy.user  ",
          profilePhotoUrl: null,
          role: "CUSTOMER",
        },
      },
      {
        follower: {
          id: "anonymous-user",
          name: null,
          username: "   ",
          profilePhotoUrl: null,
          role: "CUSTOMER",
        },
      },
      {
        follower: {
          id: "admin-user",
          name: null,
          username: null,
          profilePhotoUrl: "https://cdn.example/private-admin.jpg",
          role: "ADMIN",
        },
      },
    ],
    count: async () => 9,
  };

  const result = await loadMutualFollowers(
    {
      viewerUserId: "viewer-1",
      targetUserId: "official-1",
      isOwner: false,
    },
    dependencies,
  );

  assert.equal(result.totalCount, 9);
  assert.deepEqual(
    result.items.map((item) => item.name),
    [
      "Mona",
      "@legacy.user",
      "Pengguna Natalo",
      "Natalo Petshop Official",
    ],
  );
  assert.equal(result.items[3]?.profilePhotoUrl, null);
  assert.equal(result.items[3]?.isOfficial, true);
});

test("legacy username fallback removes repeated sigils and surrounding space", async () => {
  const dependencies: MutualFollowerDependencies = {
    findMany: async () => [
      {
        follower: {
          id: "legacy-username-user",
          name: null,
          username: "  @@  legacy.user  ",
          profilePhotoUrl: null,
          role: "CUSTOMER",
        },
      },
    ],
    count: async () => 1,
  };

  const result = await loadMutualFollowers(
    {
      viewerUserId: "viewer-1",
      targetUserId: "official-1",
      isOwner: false,
    },
    dependencies,
  );

  assert.equal(result.totalCount, 1);
  assert.equal(result.items[0]?.name, "@legacy.user");
});

test("optional mutual failure returns empty summary", async () => {
  const dependencies: MutualFollowerDependencies = {
    findMany: async () => {
      throw new Error("database unavailable");
    },
    count: async () => 4,
  };
  const result = await loadMutualFollowers(
    {
      viewerUserId: "viewer-1",
      targetUserId: "official-1",
      isOwner: false,
    },
    dependencies,
  );
  assert.deepEqual(result, { items: [], totalCount: 0 });
});
