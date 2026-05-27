import { loadSocialEnv } from "./env";

try {
  loadSocialEnv();
  // eslint-disable-next-line no-console
  console.log(
    "[social] env ok: DATABASE_URL, DIRECT_URL, and SESSION_SECRET are available.",
  );
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  // eslint-disable-next-line no-console
  console.error(message);
  process.exitCode = 1;
}
