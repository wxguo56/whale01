import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { TurnStore } from "../src/turnStore.mjs";

test("服务重启后未完成快照标记为 interrupted，已完成快照保留", async () => {
  const dir = await mkdtemp(join(tmpdir(), "whale01-turns-"));
  const store = await TurnStore.open(dir);
  await store.flush({
    turnId: "turn_running",
    conversationId: "conv_1",
    status: "running",
    reply: "",
    events: [],
    pending: []
  });
  await store.flush({
    turnId: "turn_done",
    conversationId: "conv_1",
    status: "completed",
    reply: "完成",
    events: [],
    pending: []
  });

  const restarted = await TurnStore.open(dir);
  assert.equal(restarted.get("turn_running").status, "interrupted");
  assert.match(restarted.get("turn_running").interruptionNote, /服务重启/);
  assert.equal(restarted.get("turn_done").status, "completed");
  assert.equal(restarted.get("turn_done").reply, "完成");
  assert.equal(restarted.get("turn_missing"), null);
});
