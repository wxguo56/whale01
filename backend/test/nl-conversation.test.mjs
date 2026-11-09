import test from "node:test";
import assert from "node:assert/strict";
import { createTestRuntime, FIXED_NOW, TIMEZONE } from "./helpers.mjs";

test("同一 conversationId 保留跨轮消息与能力事实", async () => {
  const calls = [];
  const adapter = {
    async chat({ messages }) {
      calls.push(structuredClone(messages));
      return {
        content: calls.length === 1 ? "我可以帮你处理提醒、日程、天气和演示音乐。" : "可以，提醒和日程都能帮你。",
        toolCalls: []
      };
    }
  };
  const { agent, conversations } = await createTestRuntime({ adapter });

  const first = await agent.start({
    text: "你都有什么技能",
    now: FIXED_NOW,
    timezone: TIMEZONE,
    conversationId: "conv_test_0001"
  });
  assert.equal(first.conversationId, "conv_test_0001");

  const second = await agent.start({
    text: "那提醒和日程呢",
    now: FIXED_NOW,
    timezone: TIMEZONE,
    conversationId: "conv_test_0001"
  });
  assert.equal(second.conversationId, "conv_test_0001");

  assert.equal(calls.length, 2);
  const secondMessages = calls[1];
  assert.equal(secondMessages[0].role, "system");
  assert.match(secondMessages[0].content, /当前能力事实/);
  assert.match(secondMessages[0].content, /模拟执行/);
  assert.ok(secondMessages.some((message) => message.role === "user" && message.content === "你都有什么技能"));
  assert.ok(
    secondMessages.some(
      (message) => message.role === "assistant" && message.content.includes("提醒、日程、天气")
    )
  );

  const summary = conversations.summary("conv_test_0001");
  assert.equal(summary.messages.length, 4);
});

test("不同会话之间不共享历史", async () => {
  let seen = [];
  const adapter = {
    async chat({ messages }) {
      seen = messages;
      return { content: "好的。", toolCalls: [] };
    }
  };
  const { agent } = await createTestRuntime({ adapter });
  await agent.start({
    text: "第一段话",
    now: FIXED_NOW,
    timezone: TIMEZONE,
    conversationId: "conv_test_0002"
  });
  await agent.start({
    text: "第二段话",
    now: FIXED_NOW,
    timezone: TIMEZONE,
    conversationId: "conv_test_0003"
  });
  assert.equal(seen.some((message) => message.content === "第一段话"), false);
});

test("非法 conversationId 被拒绝", async () => {
  const { agent } = await createTestRuntime();
  await assert.rejects(
    () =>
      agent.start({
        text: "你好",
        now: FIXED_NOW,
        timezone: TIMEZONE,
        conversationId: "someone-else"
      }),
    /conversationId 格式非法/
  );
});

test("待确认任务写入会话并在确认后关闭", async () => {
  const { agent, conversations } = await createTestRuntime();
  const pending = await agent.start({
    text: "明天下午三点提醒我取快递",
    now: FIXED_NOW,
    timezone: TIMEZONE,
    autoConfirm: false,
    conversationId: "conv_test_0004"
  });
  assert.equal(pending.status, "awaiting_confirmation");
  let tasks = conversations.tasks("conv_test_0004");
  assert.equal(tasks.length, 1);
  assert.equal(tasks[0].state, "waiting_confirmation");
  assert.equal(tasks[0].knownArguments.title, "取快递");

  await agent.confirm(pending.turnId, pending.pending[0].operationId, true);
  tasks = conversations.tasks("conv_test_0004");
  assert.equal(tasks[0].state, "completed");
});

test("修改同一待确认任务时旧操作被取代", async () => {
  let index = 0;
  const adapter = {
    async chat() {
      index += 1;
      const dueAt = index === 1 ? "2026-11-10T15:00:00+08:00" : "2026-11-11T16:00:00+08:00";
      return {
        content: "",
        toolCalls: [
          {
            id: `call_edit_${index}`,
            name: "create_reminder",
            arguments: JSON.stringify({ title: "取快递", dueAt, timezone: TIMEZONE })
          }
        ]
      };
    }
  };
  const { agent, conversations } = await createTestRuntime({ adapter });
  const first = await agent.start({
    text: "明天下午三点提醒我取快递",
    now: FIXED_NOW,
    timezone: TIMEZONE,
    autoConfirm: false,
    conversationId: "conv_test_0006"
  });
  const second = await agent.start({
    text: "改成后天下午四点，其他不变",
    now: FIXED_NOW,
    timezone: TIMEZONE,
    autoConfirm: false,
    conversationId: "conv_test_0006"
  });

  assert.equal(second.pending[0].arguments.dueAt, "2026-11-11T16:00:00+08:00");
  const tasks = conversations.tasks("conv_test_0006");
  const oldTask = tasks.find((task) => task.operationId === first.pending[0].operationId);
  assert.equal(oldTask.state, "superseded");
  const refreshed = agent.snapshot(first.turnId);
  assert.equal(refreshed.status, "superseded");
  await assert.rejects(
    () => agent.confirm(first.turnId, first.pending[0].operationId, true),
    /不能确认/
  );
});

test("转话题前取消待确认任务并继续新请求", async () => {
  let index = 0;
  let secondTools = [];
  const adapter = {
    async chat({ tools }) {
      index += 1;
      if (index === 1) {
        return {
          content: "",
          toolCalls: [
            {
              id: "call_pending_reminder",
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
      if (index === 2) secondTools = tools.map((tool) => tool.function.name);
      if (index >= 3) return { content: "杭州明天小雨，记得带伞。", toolCalls: [] };
      return {
        content: "",
        toolCalls: [
          { id: "call_cancel", name: "cancel_active_task", arguments: "{}" },
          {
            id: "call_weather",
            name: "get_weather",
            arguments: JSON.stringify({
              locationName: "杭州",
              startAt: "2026-11-10T00:00:00+08:00",
              endAt: "2026-11-10T23:59:59+08:00",
              timezone: TIMEZONE
            })
          }
        ]
      };
    }
  };
  const { agent, conversations } = await createTestRuntime({ adapter });
  await agent.start({
    text: "明天下午三点提醒我取快递",
    now: FIXED_NOW,
    timezone: TIMEZONE,
    autoConfirm: false,
    conversationId: "conv_test_0007"
  });
  const second = await agent.start({
    text: "先不管提醒了，查一下明天杭州天气",
    now: FIXED_NOW,
    timezone: TIMEZONE,
    conversationId: "conv_test_0007"
  });

  assert.equal(secondTools.includes("cancel_active_task"), true);
  assert.equal(second.status, "completed");
  assert.ok(
    second.events.some((event) => event.type === "tool.result" && event.payload.tool === "get_weather")
  );
  const task = conversations.tasks("conv_test_0007")[0];
  assert.equal(task.state, "cancelled");
});

test("同一轮重复的成功动作只执行一次", async () => {
  let index = 0;
  const pauseArgs = JSON.stringify({ sessionId: "music-session-1" });
  const adapter = {
    async chat() {
      index += 1;
      if (index === 1) {
        return { content: "", toolCalls: [{ id: "call_pause_1", name: "pause_music", arguments: pauseArgs }] };
      }
      if (index === 2) {
        return { content: "", toolCalls: [{ id: "call_pause_2", name: "pause_music", arguments: pauseArgs }] };
      }
      return { content: "已经暂停了。", toolCalls: [] };
    }
  };
  const executor = {
    capabilities: () => ["pause_music"],
    async execute() {
      return { status: "success", data: { state: "paused" }, error: null, deduplicated: false };
    }
  };
  const { agent } = await createTestRuntime({ adapter, executor });
  const result = await agent.start({
    text: "暂停",
    now: FIXED_NOW,
    timezone: TIMEZONE,
    conversationId: "conv_test_0008"
  });

  const pauseResults = result.events.filter(
    (event) => event.type === "tool.result" && event.payload.tool === "pause_music"
  );
  assert.equal(pauseResults.length, 1);
  assert.equal(result.reply, "已经暂停了。");
});
