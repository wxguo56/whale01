import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createRuntime } from "../src/runtime.mjs";

export async function createTestRuntime(overrides = {}, envOverrides = {}) {
  const dir = await mkdtemp(join(tmpdir(), "whale01-"));
  const runtime = await createRuntime(
    {
      ...process.env,
      MODEL_MODE: "mock",
      EXECUTION_MODE: "mock",
      ...envOverrides,
      OPERATION_LOG_PATH: join(dir, "operations.jsonl"),
      REMINDERS_PATH: join(dir, "reminders.json"),
      CALENDAR_PATH: join(dir, "calendar.json"),
      TURNS_PATH: join(dir, "turns")
    },
    overrides
  );
  return { ...runtime, dir };
}

export const FIXED_NOW = "2026-11-09T10:00:00+08:00";
export const TIMEZONE = "Asia/Shanghai";
