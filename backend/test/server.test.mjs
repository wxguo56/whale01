import test from "node:test";
import assert from "node:assert/strict";
import { startServer } from "../src/server.mjs";
import { createTestRuntime, FIXED_NOW, TIMEZONE } from "./helpers.mjs";

test("HTTP 闭环与事件流", async () => {
  const runtime = await createTestRuntime();
  const server = await startServer(runtime, { port: 0 });
  const { port } = server.address();
  const base = `http://127.0.0.1:${port}`;

  try {
    const health = await (await fetch(`${base}/healthz`)).json();
    assert.equal(health.status, "ok");
    assert.equal(health.contractVersion, "1.0");

    const response = await fetch(`${base}/v1/turns`, {
      method: "POST",
      headers: { "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify({
        text: "明天下午三点提醒我取快递",
        now: FIXED_NOW,
        timezone: TIMEZONE,
        autoConfirm: true
      })
    });
    const body = await response.json();
    assert.equal(body.status, "completed");
    assert.equal(body.events.find((event) => event.type === "tool.result").payload.status, "success");

    const snapshot = await (await fetch(`${base}/v1/turns/${body.turnId}`)).json();
    assert.equal(snapshot.turnId, body.turnId);

    const streamResponse = await fetch(`${base}/v1/turns`, {
      method: "POST",
      headers: { "content-type": "application/json", accept: "text/event-stream" },
      body: JSON.stringify({
        text: "明天下午三点提醒我取快递",
        now: FIXED_NOW,
        timezone: TIMEZONE,
        autoConfirm: true
      })
    });
    const streamText = await streamResponse.text();
    assert.match(streamResponse.headers.get("content-type"), /text\/event-stream/);
    assert.match(streamText, /event: tool\.result/);
    assert.match(streamText, /event: turn\.snapshot/);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test("HTTP 默认不自动确认写操作", async () => {
  const runtime = await createTestRuntime();
  const server = await startServer(runtime, { port: 0 });
  const { port } = server.address();
  const base = `http://127.0.0.1:${port}`;

  try {
    const response = await fetch(`${base}/v1/turns`, {
      method: "POST",
      headers: { "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify({
        text: "明天下午三点提醒我取快递",
        now: FIXED_NOW,
        timezone: TIMEZONE
      })
    });
    const body = await response.json();
    assert.equal(body.status, "awaiting_confirmation");
    assert.equal(body.pending.length, 1);
    assert.equal(body.events.some((event) => event.type === "tool.result"), false);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test("设备模式 HTTP：挂起手机工具、标注执行位置并接受回传", async () => {
  const runtime = await createTestRuntime({}, { EXECUTION_MODE: "ios" });
  const server = await startServer(runtime, { port: 0 });
  const { port } = server.address();
  const base = `http://127.0.0.1:${port}`;

  try {
    const health = await (await fetch(`${base}/healthz`)).json();
    assert.equal(health.executionMode, "ios");
    assert.equal(health.requiresDeferExecution, true);

    const capabilities = await (await fetch(`${base}/v1/capabilities`)).json();
    const reminder = capabilities.capabilities.find((item) => item.name === "create_reminder");
    const summarize = capabilities.capabilities.find((item) => item.name === "summarize_shared_content");
    assert.equal(reminder.executionLocation, "phone");
    assert.equal(summarize.executionLocation, "backend");

    const rejected = await fetch(`${base}/v1/turns`, {
      method: "POST",
      headers: { "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify({
        text: "明天下午三点提醒我取快递",
        now: FIXED_NOW,
        timezone: TIMEZONE
      })
    });
    assert.equal(rejected.status, 400);
    assert.equal((await rejected.json()).error.code, "device_mode_requires_defer");

    const response = await fetch(`${base}/v1/turns`, {
      method: "POST",
      headers: { "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify({
        text: "明天下午三点提醒我取快递",
        now: FIXED_NOW,
        timezone: TIMEZONE,
        deferExecution: true,
        conversationId: "conv_device_http"
      })
    });
    const started = await response.json();
    assert.equal(started.status, "awaiting_tool_results");
    assert.equal(started.pending.length, 1);
    assert.equal(started.pending[0].tool, "create_reminder");

    const pending = started.pending[0];
    const completedResponse = await fetch(`${base}/v1/turns/${started.turnId}/tool-results`, {
      method: "POST",
      headers: { "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify({
        results: [
          {
            toolCallId: pending.toolCallId,
            status: "success",
            data: {
              recordId: "REM-IOS-HTTP-1",
              title: "取快递",
              dueAt: "2026-11-10T15:00:00+08:00",
              timezone: TIMEZONE,
              listName: "提醒事项",
              source: "eventkit",
              simulated: false
            }
          }
        ]
      })
    });
    const completed = await completedResponse.json();
    assert.equal(completed.status, "completed");
    assert.match(completed.reply, /已创建提醒/);
    assert.ok(
      completed.events.some(
        (event) => event.type === "tool.result" && event.payload.status === "success"
      )
    );
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test("配置 WHALE_AUTH_TOKEN 后 /v1 要求 Bearer，healthz 保持公开", async () => {
  const runtime = await createTestRuntime({}, { WHALE_AUTH_TOKEN: "test-token" });
  const server = await startServer(runtime, { port: 0 });
  const { port } = server.address();
  const base = `http://127.0.0.1:${port}`;

  try {
    const health = await (await fetch(`${base}/healthz`)).json();
    assert.equal(health.authRequired, true);

    const unauthorized = await fetch(`${base}/v1/capabilities`);
    assert.equal(unauthorized.status, 401);
    assert.equal((await unauthorized.json()).error.code, "unauthorized");

    const authorized = await fetch(`${base}/v1/capabilities`, {
      headers: { authorization: "Bearer test-token" }
    });
    assert.equal(authorized.status, 200);

    const turn = await fetch(`${base}/v1/turns`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: "Bearer test-token"
      },
      body: JSON.stringify({
        text: "明天下午三点提醒我取快递",
        now: FIXED_NOW,
        timezone: TIMEZONE,
        autoConfirm: true
      })
    });
    assert.equal(turn.status, 200);
    assert.equal((await turn.json()).status, "completed");
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test("多身份 Token：B 不能读取、确认或提交 A 的任务，也不能重置 A 的会话", async () => {
  const runtime = await createTestRuntime(
    {},
    { EXECUTION_MODE: "ios", WHALE_AUTH_TOKENS: "token-a,token-b" }
  );
  const server = await startServer(runtime, { port: 0 });
  const { port } = server.address();
  const base = `http://127.0.0.1:${port}`;
  const asA = {
    "content-type": "application/json",
    authorization: "Bearer token-a"
  };
  const asB = {
    "content-type": "application/json",
    authorization: "Bearer token-b"
  };

  try {
    const started = await (
      await fetch(`${base}/v1/turns`, {
        method: "POST",
        headers: asA,
        body: JSON.stringify({
          text: "明天下午三点提醒我取快递",
          now: FIXED_NOW,
          timezone: TIMEZONE,
          deferExecution: true,
          conversationId: "conv_owner_a1"
        })
      })
    ).json();
    assert.equal(started.status, "awaiting_tool_results");

    const deniedSnapshot = await fetch(`${base}/v1/turns/${started.turnId}`, { headers: asB });
    assert.equal(deniedSnapshot.status, 403);
    assert.equal((await deniedSnapshot.json()).error.code, "forbidden_turn");

    const pending = started.pending[0];
    const deniedResults = await fetch(`${base}/v1/turns/${started.turnId}/tool-results`, {
      method: "POST",
      headers: asB,
      body: JSON.stringify({ results: [{ toolCallId: pending.toolCallId, status: "success", data: {} }] })
    });
    assert.equal(deniedResults.status, 403);

    const deniedConversation = await fetch(`${base}/v1/conversations/conv_owner_a1`, { headers: asB });
    assert.equal(deniedConversation.status, 403);
    const deniedReset = await fetch(`${base}/v1/conversations/conv_owner_a1`, {
      method: "DELETE",
      headers: asB
    });
    assert.equal(deniedReset.status, 403);

    const ownedSnapshot = await fetch(`${base}/v1/turns/${started.turnId}`, { headers: asA });
    assert.equal(ownedSnapshot.status, 200);
    assert.equal((await ownedSnapshot.json()).turnId, started.turnId);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test("多身份 Token：B 不能确认 A 的待确认操作", async () => {
  const runtime = await createTestRuntime({}, { WHALE_AUTH_TOKENS: "token-a,token-b" });
  const server = await startServer(runtime, { port: 0 });
  const { port } = server.address();
  const base = `http://127.0.0.1:${port}`;

  try {
    const started = await (
      await fetch(`${base}/v1/turns`, {
        method: "POST",
        headers: { "content-type": "application/json", authorization: "Bearer token-a" },
        body: JSON.stringify({
          text: "明天下午三点提醒我取快递",
          now: FIXED_NOW,
          timezone: TIMEZONE,
          autoConfirm: false
        })
      })
    ).json();
    assert.equal(started.status, "awaiting_confirmation");
    const operationId = started.pending[0].operationId;

    const denied = await fetch(`${base}/v1/turns/${started.turnId}/confirm`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: "Bearer token-b" },
      body: JSON.stringify({ operationId, confirmed: true })
    });
    assert.equal(denied.status, 403);
    assert.equal((await denied.json()).error.code, "forbidden_turn");
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});
