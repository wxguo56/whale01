import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { createTestRuntime, FIXED_NOW, TIMEZONE } from "./helpers.mjs";
import { buildTaskPlan } from "../src/taskPlan.mjs";

test("解释或否定请求不产生执行计划，也不向模型开放执行工具", async () => {
  let exposed;
  const { agent } = await createTestRuntime({ adapter: { chat: async ({ tools }) => {
    exposed = tools;
    return { content: "天气指一定区域的大气状态。", toolCalls: [] };
  } } });
  assert.equal(buildTaskPlan("假如我要导航回家"), null);
  const result = await agent.start({ text: "天气这个词怎么解释", now: FIXED_NOW, timezone: TIMEZONE });
  assert.equal(exposed.length, 0);
  assert.equal(result.pending.length, 0);
  assert.equal(result.events.some(event => event.type === "tool.requested"), false);
});

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

test("模型自行补造 09:00 时被拦截并要求追问", async () => {
  let calls = 0;
  const adapter = {
    async chat() {
      calls += 1;
      if (calls === 1) {
        return {
          content: "",
          toolCalls: [
            {
              id: "call_invented_time",
              name: "create_reminder",
              arguments: JSON.stringify({
                title: "取快递",
                dueAt: "2026-11-10T09:00:00+08:00",
                timezone: TIMEZONE
              })
            }
          ]
        };
      }
      return { content: "明天几点提醒你取快递？", toolCalls: [] };
    }
  };
  const { agent } = await createTestRuntime({ adapter });
  const result = await agent.start({
    text: "明天提醒我取快递",
    now: FIXED_NOW,
    timezone: TIMEZONE,
    autoConfirm: true
  });

  assert.equal(result.status, "completed");
  assert.equal(result.events.some((event) => event.type === "tool.requested"), false);
  const rejected = result.events.find((event) => event.type === "tool.rejected");
  assert.equal(rejected.payload.error.code, "missing_time");
  assert.match(result.reply, /几点/);
});

test("只说三点时拦截并追问上午还是下午", async () => {
  let calls = 0;
  const adapter = {
    async chat() {
      calls += 1;
      if (calls === 1) {
        return {
          content: "",
          toolCalls: [
            {
              id: "call_missing_period",
              name: "create_reminder",
              arguments: JSON.stringify({
                title: "取快递",
                dueAt: "2026-11-10T15:00:00+08:00",
                timezone: TIMEZONE
              })
            }
          ]
        };
      }
      return { content: "三点是上午还是下午？", toolCalls: [] };
    }
  };
  const { agent } = await createTestRuntime({ adapter });
  const result = await agent.start({
    text: "明天三点提醒我取快递",
    now: FIXED_NOW,
    timezone: TIMEZONE,
    autoConfirm: true
  });

  assert.equal(result.status, "completed");
  assert.equal(result.events.some((event) => event.type === "tool.requested"), false);
  const rejected = result.events.find((event) => event.type === "tool.rejected");
  assert.equal(rejected.payload.error.code, "missing_period");
  assert.match(result.reply, /上午还是下午/);
});

test("修改待确认时间时沿用原下午上下文", async () => {
  const adapter = {
    async chat() {
      return {
        content: "",
        toolCalls: [
          {
            id: "call_edit_pm",
            name: "create_reminder",
            arguments: JSON.stringify({
              title: "取快递",
              dueAt: "2026-11-10T16:00:00+08:00",
              timezone: TIMEZONE
            })
          }
        ]
      };
    }
  };
  const { agent, conversations } = await createTestRuntime({ adapter });
  conversations.ensure("conv_test_edit_pm");
  conversations.upsertTask("conv_test_edit_pm", {
    taskId: "task-reminder-1",
    kind: "create_reminder",
    state: "waiting_confirmation",
    operationId: "op-old-preview",
    turnId: "turn_seed",
    knownArguments: { title: "取快递", dueAt: "2026-11-10T15:00:00+08:00", timezone: TIMEZONE }
  });
  const result = await agent.start({
    text: "改成四点，其他不变",
    now: FIXED_NOW,
    timezone: TIMEZONE,
    autoConfirm: false,
    conversationId: "conv_test_edit_pm"
  });

  assert.equal(result.status, "awaiting_confirmation");
  assert.equal(result.pending[0].arguments.dueAt, "2026-11-10T16:00:00+08:00");
});

test("同一时间修改日期时允许沿用已确认时间", async () => {
  const adapter = {
    async chat() {
      return {
        content: "",
        toolCalls: [
          {
            id: "call_edit_date",
            name: "create_reminder",
            arguments: JSON.stringify({
              title: "取快递",
              dueAt: "2026-11-11T15:00:00+08:00",
              timezone: TIMEZONE
            })
          }
        ]
      };
    }
  };
  const { agent, conversations } = await createTestRuntime({ adapter });
  conversations.ensure("conv_test_edit_date");
  conversations.upsertTask("conv_test_edit_date", {
    taskId: "task-reminder-1",
    kind: "create_reminder",
    state: "waiting_confirmation",
    operationId: "op-old-preview",
    turnId: "turn_seed",
    knownArguments: { title: "取快递", dueAt: "2026-11-10T15:00:00+08:00", timezone: TIMEZONE }
  });
  const result = await agent.start({
    text: "换成后天，同一时间",
    now: FIXED_NOW,
    timezone: TIMEZONE,
    autoConfirm: false,
    conversationId: "conv_test_edit_date"
  });

  assert.equal(result.status, "awaiting_confirmation");
  assert.equal(result.pending[0].arguments.dueAt, "2026-11-11T15:00:00+08:00");
});

test("动作命令只回文字时强制改调工具", async () => {
  let calls = 0;
  const adapter = {
    async chat() {
      calls += 1;
      if (calls === 1) return { content: "已暂停。", toolCalls: [] };
      if (calls === 2) {
        return {
          content: "",
          toolCalls: [{ id: "call_pause", name: "pause_music", arguments: JSON.stringify({}) }]
        };
      }
      return { content: "已暂停《雨天电台》。", toolCalls: [] };
    }
  };
  const { agent, executor } = await createTestRuntime({ adapter });
  executor.seedPlayback("conv_test_pause", {
    state: "playing",
    sessionId: "music-session-1",
    trackId: "music_demo_2",
    queue: ["music_demo_2"]
  });
  const result = await agent.start({
    text: "暂停",
    now: FIXED_NOW,
    timezone: TIMEZONE,
    autoConfirm: true,
    conversationId: "conv_test_pause"
  });

  assert.equal(result.status, "completed");
  const requested = result.events.find((event) => event.type === "tool.requested");
  assert.equal(requested.payload.tool, "pause_music");
  const toolResult = result.events.find((event) => event.type === "tool.result");
  assert.equal(toolResult.payload.status, "success");
  assert.match(result.reply, /已暂停/);
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

test("回家导航没有地址时不搜索“家”，只追问", async () => {
  let calls = 0;
  const adapter = {
    async chat() {
      calls += 1;
      if (calls === 1) {
        return {
          content: "",
          toolCalls: [
            {
              id: "call_home_1",
              name: "search_places",
              arguments: JSON.stringify({ query: "家", locationMode: "current" })
            }
          ]
        };
      }
      return { content: "请告诉我你的详细家庭地址，我再解析目的地。", toolCalls: [] };
    }
  };
  const { agent } = await createTestRuntime({ adapter }, { EXECUTION_MODE: "ios" });
  const result = await agent.start({
    text: "导航回家",
    now: FIXED_NOW,
    timezone: TIMEZONE,
    deferExecution: true
  });

  assert.equal(result.status, "completed_with_limits");
  assert.equal(result.pending.length, 0);
  assert.ok(
    result.events.some(
      (event) =>
        event.type === "tool.rejected" &&
        event.payload.error?.code === "missing_home_address"
    )
  );
});

test("设备模式下必须延迟执行，且能力表标注手机执行位置", async () => {
  const { agent } = await createTestRuntime({}, { EXECUTION_MODE: "ios" });

  await assert.rejects(
    () =>
      agent.start({
        text: "明天下午三点提醒我取快递",
        now: FIXED_NOW,
        timezone: TIMEZONE
      }),
    (error) => error.code === "device_mode_requires_defer"
  );

  const capabilities = agent.capabilities();
  const reminder = capabilities.find((item) => item.name === "create_reminder");
  const summarize = capabilities.find((item) => item.name === "summarize_shared_content");
  assert.equal(reminder.executionMode, "ios");
  assert.equal(reminder.executionLocation, "phone");
  assert.equal(reminder.implemented, true);
  assert.equal(summarize.executionLocation, "backend");
  assert.equal(summarize.implemented, false);
  assert.equal(summarize.availability, "not_implemented");
});

test("设备模式下模拟摘要工具不可用，只挂起手机工具", async () => {
  let callIndex = 0;
  const adapter = {
    async chat() {
      callIndex += 1;
      if (callIndex === 1) {
        return {
          content: "",
          toolCalls: [
            {
              id: "call_summary_1",
              name: "summarize_shared_content",
              arguments: JSON.stringify({ contentId: "content_1", maxPoints: 3 })
            },
            {
              id: "call_reminder_1",
              name: "create_reminder",
              arguments: JSON.stringify({
                title: "取快递",
                timezone: TIMEZONE,
                dueAt: "2026-11-10T15:00:00+08:00"
              })
            }
          ]
        };
      }
      return { content: "已完成", toolCalls: [] };
    }
  };
  const { agent } = await createTestRuntime({ adapter }, { EXECUTION_MODE: "ios" });

  const started = await agent.start({
    text: "总结这篇文章，再提醒我明天下午三点取快递",
    now: FIXED_NOW,
    timezone: TIMEZONE,
    deferExecution: true
  });

  assert.equal(started.status, "awaiting_tool_results");
  assert.deepEqual(started.pending.map((item) => item.tool), ["create_reminder"]);
  assert.ok(
    started.events.some(
      (event) =>
        event.type === "tool.rejected" &&
        event.payload.tool === "summarize_shared_content" &&
        event.payload.status === "unsupported"
    )
  );

  const done = await agent.submitToolResults(started.turnId, [
    {
      toolCallId: started.pending[0].toolCallId,
      status: "success",
      data: {
        recordId: "REM-DEVICE-2",
        title: "取快递",
        dueAt: "2026-11-10T15:00:00+08:00",
        timezone: TIMEZONE
      }
    }
  ]);
  assert.equal(done.status, "completed");
  assert.equal(done.reply, "已完成");
});

test("查日历空档后生成日程确认，确认前不写入", async () => {
  let callIndex = 0;
  const adapter = {
    async chat() {
      callIndex += 1;
      if (callIndex === 1) {
        return {
          content: "",
          toolCalls: [
            {
              id: "call_free_slots",
              name: "find_free_slots",
              arguments: JSON.stringify({
                startAt: "2026-11-10T09:00:00+08:00",
                endAt: "2026-11-10T12:00:00+08:00",
                timezone: TIMEZONE,
                durationMinutes: 60,
                dayStart: "09:00",
                dayEnd: "12:00",
                limit: 3
              })
            }
          ]
        };
      }
      if (callIndex === 2) {
        return {
          content: "找到可选空档，先为你准备日程预览。",
          toolCalls: [
            {
              id: "call_create_from_slot",
              name: "create_calendar_event",
              arguments: JSON.stringify({
                title: "和产品对齐",
                startAt: "2026-11-10T10:00:00+08:00",
                endAt: "2026-11-10T11:00:00+08:00",
                timezone: TIMEZONE
              })
            }
          ]
        };
      }
      return { content: "日程已写入。", toolCalls: [] };
    }
  };
  const { agent, dir } = await createTestRuntime({ adapter });
  const pending = await agent.start({
    text: "明天上午找个空档安排和产品对齐",
    now: FIXED_NOW,
    timezone: TIMEZONE,
    autoConfirm: false
  });

  assert.equal(pending.status, "awaiting_confirmation");
  assert.equal(pending.pending[0].tool, "create_calendar_event");
  const slotResult = pending.events.find(
    (event) => event.type === "tool.result" && event.payload.tool === "find_free_slots"
  );
  assert.equal(slotResult.payload.status, "success");
  assert.ok(slotResult.payload.data.count >= 1);
  await assert.rejects(() => readFile(join(dir, "calendar.json"), "utf8"), /ENOENT/);

  const done = await agent.confirm(pending.turnId, pending.pending[0].operationId, true);
  assert.equal(done.status, "completed");
  const records = JSON.parse(await readFile(join(dir, "calendar.json"), "utf8"));
  assert.equal(records.length, 1);
  assert.equal(records[0].title, "和产品对齐");
});
