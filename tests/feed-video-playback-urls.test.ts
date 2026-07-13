import assert from "node:assert/strict";
import test from "node:test";

import {
  buildFeedVideoPlaybackUrls,
  bunnyGuidFromConfiguredCdnUrl,
} from "../lib/feed/video-playback-urls";

const OLD_ENV = { ...process.env };

test.afterEach(() => {
  process.env = { ...OLD_ENV };
});

test("buildFeedVideoPlaybackUrls keeps canonical HLS and adds 480p data-saver URL", () => {
  process.env.BUNNY_LIBRARY_ID = "123";
  process.env.BUNNY_API_KEY = "api-key";
  process.env.BUNNY_CDN_HOSTNAME = "vz-example.b-cdn.net";
  process.env.BUNNY_MP4_480_ENABLED = "true";
  delete process.env.BUNNY_TOKEN_SECURITY_KEY;

  const urls = buildFeedVideoPlaybackUrls({
    videoUrl: "https://vz-example.b-cdn.net/abc-123/playlist.m3u8",
    videoGuid: "abc-123",
  });

  assert.equal(
    urls.videoUrl,
    "https://vz-example.b-cdn.net/abc-123/playlist.m3u8",
  );
  assert.equal(
    urls.videoDataSaverUrl,
    "https://vz-example.b-cdn.net/abc-123/play_480p.mp4",
  );
});

test("buildFeedVideoPlaybackUrls signs HLS as directory token and MP4 as path token", () => {
  process.env.BUNNY_LIBRARY_ID = "123";
  process.env.BUNNY_API_KEY = "api-key";
  process.env.BUNNY_CDN_HOSTNAME = "vz-example.b-cdn.net";
  process.env.BUNNY_MP4_480_ENABLED = "true";
  process.env.BUNNY_TOKEN_SECURITY_KEY = "secret";

  const urls = buildFeedVideoPlaybackUrls({
    videoUrl: "https://vz-example.b-cdn.net/abc-123/playlist.m3u8",
    videoGuid: "abc-123",
  });

  assert.match(urls.videoUrl ?? "", /\/bcdn_token=[^/]+\/abc-123\/playlist\.m3u8$/);
  assert.match(urls.videoUrl ?? "", /token_path=%2Fabc-123%2F/);
  assert.match(urls.videoDataSaverUrl ?? "", /\/abc-123\/play_480p\.mp4\?/);
  assert.match(urls.videoDataSaverUrl ?? "", /token=/);
  assert.match(urls.videoDataSaverUrl ?? "", /expires=/);
});

test("buildFeedVideoPlaybackUrls omits data-saver URL without Bunny guid", () => {
  delete process.env.BUNNY_LIBRARY_ID;
  delete process.env.BUNNY_API_KEY;
  delete process.env.BUNNY_CDN_HOSTNAME;

  const urls = buildFeedVideoPlaybackUrls({
    videoUrl: "https://cdn.example.com/legacy.mp4",
    videoGuid: null,
  });

  assert.equal(urls.videoUrl, "https://cdn.example.com/legacy.mp4");
  assert.equal(urls.videoDataSaverUrl, null);
});

test("buildFeedVideoPlaybackUrls rejects unsafe explicit Bunny guid", () => {
  process.env.BUNNY_CDN_HOSTNAME = "vz-example.b-cdn.net";
  process.env.BUNNY_MP4_480_ENABLED = "true";

  const urls = buildFeedVideoPlaybackUrls({
    videoUrl: "https://cdn.example.com/legacy.mp4",
    videoGuid: "../outside",
  });

  assert.equal(urls.videoDataSaverUrl, null);
});

test("buildFeedVideoPlaybackUrls omits data-saver URL while 480 flag is disabled", () => {
  process.env.BUNNY_LIBRARY_ID = "123";
  process.env.BUNNY_API_KEY = "api-key";
  process.env.BUNNY_CDN_HOSTNAME = "vz-example.b-cdn.net";
  process.env.BUNNY_MP4_480_ENABLED = "false";

  const urls = buildFeedVideoPlaybackUrls({
    videoUrl: "https://vz-example.b-cdn.net/abc-123/playlist.m3u8",
    videoGuid: "abc-123",
  });

  assert.equal(
    urls.videoUrl,
    "https://vz-example.b-cdn.net/abc-123/playlist.m3u8",
  );
  assert.equal(urls.videoDataSaverUrl, null);
});

test("buildFeedVideoPlaybackUrls omits data-saver URL when Bunny config is missing", () => {
  delete process.env.BUNNY_LIBRARY_ID;
  delete process.env.BUNNY_API_KEY;
  delete process.env.BUNNY_CDN_HOSTNAME;

  const urls = buildFeedVideoPlaybackUrls({
    videoUrl: "https://cdn.example.com/legacy.mp4",
    videoGuid: "abc-123",
  });

  assert.equal(urls.videoUrl, "https://cdn.example.com/legacy.mp4");
  assert.equal(urls.videoDataSaverUrl, null);
});

test("buildFeedVideoPlaybackUrls infers Bunny guid from configured CDN canonical path", () => {
  process.env.BUNNY_LIBRARY_ID = "123";
  process.env.BUNNY_API_KEY = "api-key";
  process.env.BUNNY_CDN_HOSTNAME = "vz-example.b-cdn.net";
  process.env.BUNNY_MP4_480_ENABLED = "true";

  assert.equal(
    bunnyGuidFromConfiguredCdnUrl(
      "https://vz-example.b-cdn.net/abc-123/playlist.m3u8",
    ),
    "abc-123",
  );
  assert.equal(
    bunnyGuidFromConfiguredCdnUrl(
      "https://vz-example.b-cdn.net/abc-123/play_720p.mp4",
    ),
    "abc-123",
  );

  const urls = buildFeedVideoPlaybackUrls({
    videoUrl: "https://vz-example.b-cdn.net/abc-123/playlist.m3u8",
    videoGuid: null,
  });

  assert.equal(
    urls.videoDataSaverUrl,
    "https://vz-example.b-cdn.net/abc-123/play_480p.mp4",
  );
});

test("bunnyGuidFromConfiguredCdnUrl rejects different host and noncanonical paths", () => {
  process.env.BUNNY_CDN_HOSTNAME = "vz-example.b-cdn.net";

  assert.equal(
    bunnyGuidFromConfiguredCdnUrl(
      "https://evil.example.com/abc-123/playlist.m3u8",
    ),
    null,
  );
  assert.equal(
    bunnyGuidFromConfiguredCdnUrl(
      "https://vz-example.b-cdn.net/abc-123/thumbnail.jpg",
    ),
    null,
  );
  assert.equal(bunnyGuidFromConfiguredCdnUrl("not a url"), null);
});
