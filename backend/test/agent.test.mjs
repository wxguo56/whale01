import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { createTestRuntime, FIXED_NOW, TIMEZONE } from "./helpers.mjs";

test("自动确认时完成创建提醒闭环", async () => {
  const { agent, dir } = await createTestRuntime();
  const result = await agent.start({
    text: "明天下午三点提醒我取快递",
    now: FIXED_NOW,
    timezone: TIMEZONE,
    autoConfirm: true
  });

  assert.equal(result.status, "completed");
  const toolResult = result.events.find((event) => event.type === "tool.result");
  assert.equal(toolResult.payload.status, "success");
  assert.equal(toolResult.payload.data.dueAt, "2026-11-10T15:00:00+08:00");
  assert.match(result.reply, /已创建提醒/);

  const records = JSON.parse(await readFile(join(dir, "reminders.json"), "utf8"));
  assert.equal(records.length, 1);
  assert.equal(records[0].title, "取快递");
});

test("确认前不写入，确认后才执行", async () => {
  const { agent, dir } = await createTestRuntime();
  const pending = await agent.start({
    text: "明天下午三点提醒我取快递",
    now: FIXED_NOW,
    timezone: TIMEZONE,
    autoConfirm: false
  });

  assert.equal(pending.status, "awaiting_confirmation");
  assert.equal(pending.pending.length, 1);
  await assert.rejects(() => readFile(join(dir, "reminders.json"), "utf8"), /ENOENT/);

  const done = await agent.confirm(pending.turnId, pending.pending[0].operationId, true);
  assert.equal(done.status, "completed");
  const records = JSON.parse(await readFile(join(dir, "reminders.json"), "utf8"));
  assert.equal(records.length, 1);
});

test("取消确认不写入系统", async () => {
  const { agent, dir } = await createTestRuntime();
  const pending = await agent.start({
    text: "明天下午三点提醒我取快递",
    now: FIXED_NOW,
    timezone: TIMEZONE,
    autoConfirm: false
  });
  const done = await agent.confirm(pending.turnId, pending.pending[0].operationId, false);

  assert.equal(done.status, "completed");
  assert.match(done.reply, /已取消/);
  await assert.rejects(() => readFile(join(dir, "reminders.json"), "utf8"), /ENOENT/);
});

test("缺少具体时间时追问且不调用工具", async () => {
  const { agent } = await createTestRuntime();
  const result = await agent.start({
    text: "明天提醒我取快递",
    now: FIXED_NOW,
    timezone: TIMEZONE,
    autoConfirm: true
  });

  assert.equal(result.status, "completed");
  assert.match(result.reply, /几点/);
  assert.equal(result.events.some((event) => event.type === "tool.requested"), false);
});

test("模型循环到达上限后停止并说明未完成", async () => {
  let callIndex = 0;
  const loopingAdapter = {
    async chat() {
      callIndex += 1;
      return {
        content: "",
        toolCalls: [
          {
            id: `call_loop_${callIndex}`,
            name: "get_activity_summary",
            arguments: JSON.stringify({
              startAt: "2026-11-09T00:00:00+08:00",
              endAt: "2026-11-10T00:00:00+08:00",
              timezone: TIMEZONE,
              metrics: ["steps"]
            })
          }
        ]
      };
    }
  };
  const { agent } = await createTestRuntime({ adapter: loopingAdapter });
  const result = await agent.start({
    text: "看我今天走了多少步",
    now: FIXED_NOW,
    timezone: TIMEZONE,
    autoConfirm: true
  });

  assert.equal(result.status, "completed_with_limits");
  const limit = result.events.find((event) => event.type === "turn.limit_reached");
  assert.ok(limit);
  assert.match(limit.payload.message, /上限/);
  assert.ok(callIndex <= 5);
});

test("延迟执行模式下回传工具结果后继续", async () => {
  const { agent } = await createTestRuntime();
  const started = await agent.start({
    text: "明天下午三点提醒我取快递",
    now: FIXED_NOW,
    timezone: TIMEZONE,
    autoConfirm: true,
    deferExecution: true
  });

  assert.equal(started.status, "awaiting_tool_results");
  assert.equal(started.pending.length, 1);
  const pending = started.pending[0];
  const done = await agent.submitToolResults(started.turnId, [
    {
      toolCallId: pending.toolCallId,
      status: "success",
      data: {
        recordId: "REM-DEVICE-1",
        title: "取快递",
        dueAt: "2026-11-10T15:00:00+08:00",
        timezone: TIMEZONE
      }
    }
  ]);

  assert.equal(done.status, "completed");
  assert.match(done.reply, /已创建提醒/);
});
