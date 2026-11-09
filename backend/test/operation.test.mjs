import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { MockDeviceExecutor } from "../src/mockDevice.mjs";
import { OperationLog } from "../src/operationLog.mjs";
import { createTestRuntime } from "./helpers.mjs";

test("同一 operationId 重复执行只写入一条提醒", async () => {
  const { dir } = await createTestRuntime();
  const remindersPath = join(dir, "reminders.json");
  const executor = new MockDeviceExecutor({ remindersPath });
  const args = {
    title: "取快递",
    dueAt: "2026-11-10T15:00:00+08:00",
    timezone: "Asia/Shanghai"
  };

  const first = await executor.execute({
    tool: "create_reminder",
    arguments: args,
    operationId: "op_same",
    turnId: "turn_test"
  });
  const second = await executor.execute({
    tool: "create_reminder",
    arguments: args,
    operationId: "op_same",
    turnId: "turn_test"
  });

  assert.equal(first.status, "success");
  assert.equal(first.deduplicated, false);
  assert.equal(second.deduplicated, true);
  assert.equal(second.data.recordId, first.data.recordId);
  const records = JSON.parse(await readFile(remindersPath, "utf8"));
  assert.equal(records.length, 1);
});

test("操作日志在重启后可读，started 状态可被识别", async () => {
  const { config } = await createTestRuntime();
  const log = await OperationLog.open(config.paths.operationLog);
  await log.begin({
    operationId: "op_restart",
    turnId: "turn_restart",
    tool: "create_reminder",
    arguments: { title: "取快递", timezone: "Asia/Shanghai" }
  });

  const reopened = await OperationLog.open(config.paths.operationLog);
  const entry = reopened.get("op_restart");
  assert.equal(entry.status, "started");
  assert.equal(entry.tool, "create_reminder");
});
