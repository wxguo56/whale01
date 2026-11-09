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
