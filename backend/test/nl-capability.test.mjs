import test from "node:test";
import assert from "node:assert/strict";
import { loadConfig } from "../src/config.mjs";
import { ToolRegistry } from "../src/registry.mjs";
import { MockDeviceExecutor } from "../src/mockDevice.mjs";
import { buildCapabilityManifest, allowedToolNames } from "../src/capabilities.mjs";
import { createTestRuntime, FIXED_NOW, TIMEZONE } from "./helpers.mjs";

const config = loadConfig({ MODEL_MODE: "mock" });
const registry = ToolRegistry.fromFile(config.paths.tools, config.paths.toolDefinition);
const executor = new MockDeviceExecutor({});

test("能力表区分实现、授权与模拟执行", () => {
  const manifest = buildCapabilityManifest({
    registry,
    implemented: executor.capabilities(),
    permissions: { reminder: "granted", calendarRead: "denied", music: "unknown" },
    executionMode: "mock"
  });
  assert.equal(manifest.length, 15);
  assert.ok(manifest.every((item) => item.executionMode === "mock"));

  const reminder = manifest.find((item) => item.name === "create_reminder");
  assert.equal(reminder.availability, "available");
  assert.equal(reminder.authorization, "granted");

  const calendar = manifest.find((item) => item.name === "list_calendar_events");
  assert.equal(calendar.availability, "needs_authorization");
  assert.equal(calendar.authorization, "denied");

  const music = manifest.find((item) => item.name === "play_music");
  assert.equal(music.availability, "available");
  assert.equal(music.authorization, "unknown");
  assert.match(music.reason, /权限状态未知/);
});

test("未实现的工具不会暴露给模型", () => {
  const manifest = buildCapabilityManifest({
    registry,
    implemented: ["create_reminder"],
    permissions: {},
    executionMode: "mock"
  });
  const allowed = allowedToolNames(manifest);
  assert.deepEqual(allowed, ["create_reminder"]);
  const listed = registry.listForModel({ allowed });
  assert.deepEqual(listed.map((tool) => tool.function.name), ["create_reminder"]);
});

test("拒绝音乐权限时模型工具列表不含音乐工具", async () => {
  let toolNames = [];
  const adapter = {
    async chat({ tools }) {
      toolNames = tools.map((tool) => tool.function.name);
      return { content: "音乐权限未开启，可以先去设置里授权。", toolCalls: [] };
    }
  };
  const { agent } = await createTestRuntime({ adapter });
  await agent.start({
    text: "放首歌",
    now: FIXED_NOW,
    timezone: TIMEZONE,
    conversationId: "conv_test_0005",
    permissions: { music: "denied" }
  });
  assert.equal(toolNames.includes("play_music"), false);
  assert.equal(toolNames.includes("search_music_library"), false);
  assert.equal(toolNames.includes("create_reminder"), true);
});
