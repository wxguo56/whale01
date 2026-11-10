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

test("提醒可查询、改期、标记完成并删除，不会新增重复记录", async () => {
  const { dir } = await createTestRuntime();
  const remindersPath = join(dir, "reminders.json");
  const executor = new MockDeviceExecutor({ remindersPath });
  const created = await executor.execute({
    tool: "create_reminder",
    arguments: { title: "交报告", dueAt: "2026-11-11T15:00:00+08:00", timezone: "Asia/Shanghai" },
    operationId: "op_reminder_lifecycle",
    turnId: "turn_test"
  });
  assert.equal(created.status, "success");

  const listed = await executor.execute({ tool: "list_reminders", arguments: {} });
  assert.equal(listed.data.count, 1);

  const updated = await executor.execute({
    tool: "update_reminder",
    arguments: { recordId: created.data.recordId, dueAt: "2026-11-11T16:00:00+08:00", completed: true }
  });
  assert.equal(updated.status, "success");
  assert.equal(updated.data.completed, true);
  const recordsAfterUpdate = JSON.parse(await readFile(remindersPath, "utf8"));
  assert.equal(recordsAfterUpdate.length, 1);

  const deleted = await executor.execute({
    tool: "delete_reminder",
    arguments: { recordId: created.data.recordId }
  });
  assert.equal(deleted.data.deleted, true);
  const remaining = JSON.parse(await readFile(remindersPath, "utf8"));
  assert.equal(remaining.length, 0);
});

test("偏好可保存、读取和删除，搜索结果明确标注模拟", async () => {
  const executor = new MockDeviceExecutor({});
  const saved = await executor.execute({
    tool: "set_memory",
    arguments: { key: "饮食", value: "不吃辣" }
  });
  assert.equal(saved.status, "success");
  const listed = await executor.execute({ tool: "list_memory", arguments: {} });
  assert.equal(listed.data.count, 1);
  const removed = await executor.execute({ tool: "delete_memory", arguments: { key: "饮食" } });
  assert.equal(removed.data.deleted, true);

  const search = await executor.execute({ tool: "search_web", arguments: { query: "杭州烧烤" } });
  assert.equal(search.status, "success");
  assert.equal(search.data.simulated, true);
});

test("空档查询跳过占用时段并标注模拟来源", async () => {
  const executor = new MockDeviceExecutor({});
  const result = await executor.execute({
    tool: "find_free_slots",
    arguments: {
      startAt: "2026-11-10T09:00:00+08:00",
      endAt: "2026-11-10T12:00:00+08:00",
      timezone: "Asia/Shanghai",
      durationMinutes: 60,
      dayStart: "09:00",
      dayEnd: "12:00",
      limit: 3
    }
  });
  assert.equal(result.status, "success");
  assert.equal(result.data.simulated, true);
  assert.equal(result.data.source, "mock_calendar");
  assert.ok(result.data.count >= 1);
  assert.ok(result.data.slots.every((slot) => slot.durationMinutes === 60));
  assert.ok(result.data.slots.every((slot) => Date.parse(slot.endAt) > Date.parse(slot.startAt)));
});

test("空档查询拒绝反向时间范围", async () => {
  const executor = new MockDeviceExecutor({});
  const result = await executor.execute({
    tool: "find_free_slots",
    arguments: {
      startAt: "2026-11-10T12:00:00+08:00",
      endAt: "2026-11-10T09:00:00+08:00",
      timezone: "Asia/Shanghai"
    }
  });
  assert.equal(result.status, "failed");
  assert.equal(result.error.code, "invalid_time_range");
});

test("周期提醒保存重复规则并使用同一 operationId 去重", async () => {
  const { dir } = await createTestRuntime();
  const remindersPath = join(dir, "reminders.json");
  const executor = new MockDeviceExecutor({ remindersPath });
  const args = {
    title: "喝水",
    dueAt: "2026-11-10T09:00:00+08:00",
    timezone: "Asia/Shanghai",
    recurrence: { frequency: "daily", interval: 1, count: 30 }
  };
  const first = await executor.execute({
    tool: "create_reminder",
    arguments: args,
    operationId: "op_recurring",
    turnId: "turn_recurring"
  });
  const second = await executor.execute({
    tool: "create_reminder",
    arguments: args,
    operationId: "op_recurring",
    turnId: "turn_recurring"
  });
  assert.equal(first.status, "success");
  assert.deepEqual(first.data.recurrence, args.recurrence);
  assert.equal(second.deduplicated, true);
  const records = JSON.parse(await readFile(remindersPath, "utf8"));
  assert.equal(records.length, 1);
  assert.deepEqual(records[0].recurrence, args.recurrence);
});
