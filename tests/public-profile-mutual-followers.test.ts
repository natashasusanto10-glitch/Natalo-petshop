import assert from "node:assert/strict";
import test from "node:test";
import {
  buildMutualFollowerWhere,
  loadOfficialMutualFollowers,
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

test("mutuals are gated to authenticated official non-owner viewers", async () => {
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

  for (const input of [
    { viewerUserId: null, targetUserId: "official-1", isOfficial: true, isOwner: false },
    { viewerUserId: "viewer-1", targetUserId: "user-1", isOfficial: false, isOwner: false },
    { viewerUserId: "official-1", targetUserId: "official-1", isOfficial: true, isOwner: true },
  ]) {
    assert.deepEqual(await loadOfficialMutualFollowers(input, dependencies), {
      items: [],
      totalCount: 0,
    });
  }
  assert.equal(calls, 0);
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

  const result = await loadOfficialMutualFollowers(
    {
      viewerUserId: "viewer-1",
      targetUserId: "official-1",
      isOfficial: true,
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

test("optional mutual failure returns empty summary", async () => {
  const dependencies: MutualFollowerDependencies = {
    findMany: async () => {
      throw new Error("database unavailable");
    },
    count: async () => 4,
  };
  const result = await loadOfficialMutualFollowers(
    {
      viewerUserId: "viewer-1",
      targetUserId: "official-1",
      isOfficial: true,
      isOwner: false,
    },
    dependencies,
  );
  assert.deepEqual(result, { items: [], totalCount: 0 });
});
