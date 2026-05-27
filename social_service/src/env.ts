import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { parse } from "dotenv";

const ENV_FILES = [".env.local", ".env.production.local", ".env"];
const REQUIRED_ENV = ["DATABASE_URL", "DIRECT_URL", "SESSION_SECRET"] as const;

export function loadSocialEnv() {
  for (const file of ENV_FILES) {
    const path = resolve(process.cwd(), file);
    if (existsSync(path)) {
      const parsed = parse(readFileSync(path));
      for (const [key, value] of Object.entries(parsed)) {
        if (!hasValue(process.env[key])) {
          process.env[key] = value;
        }
      }
    }
  }

  const missing = REQUIRED_ENV.filter((key) => !process.env[key]);
  if (missing.length > 0) {
    throw new Error(
      `[social] Missing required env: ${missing.join(", ")}. ` +
        "Use the same DATABASE_URL, DIRECT_URL, and SESSION_SECRET as Next.js.",
    );
  }

  const sessionSecret = process.env.SESSION_SECRET ?? "";
  if (sessionSecret.length < 32) {
    throw new Error("[social] SESSION_SECRET must be at least 32 characters.");
  }
}

function hasValue(value: string | undefined) {
  return typeof value === "string" && value.trim().length > 0;
}
