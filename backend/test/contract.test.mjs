import test from "node:test";
import assert from "node:assert/strict";
import { loadConfig } from "../src/config.mjs";
import { ToolRegistry } from "../src/registry.mjs";

const config = loadConfig({ MODEL_MODE: "mock" });
const registry = ToolRegistry.fromFile(config.paths.tools, config.paths.toolDefinition);

test("工具目录覆盖总纲要求的 9 个工具", () => {
  assert.deepEqual(registry.names().sort(), [
    "create_calendar_event",
    "create_reminder",
    "get_activity_summary",
    "get_weather",
    "list_calendar_events",
    "open_navigation",
    "prepare_message",
    "search_places",
    "summarize_shared_content"
  ]);
});

test("create_reminder 必填 title 与 timezone", () => {
  assert.equal(registry.validateArguments("create_reminder", { title: "取快递" }).ok, false);
  assert.equal(
    registry.validateArguments("create_reminder", { title: "取快递", timezone: "Asia/Shanghai" }).ok,
    true
  );
});

test("拒绝未声明的额外字段", () => {
  const result = registry.validateArguments("create_reminder", {
    title: "取快递",
    timezone: "Asia/Shanghai",
    rawPath: "/tmp/secret"
  });
  assert.equal(result.ok, false);
  assert.match(result.errors.join(" "), /不允许的额外字段/);
});

test("dueAt 必须是带偏移的 ISO 8601 时间", () => {
  const bad = registry.validateArguments("create_reminder", {
    title: "取快递",
    timezone: "Asia/Shanghai",
    dueAt: "明天下午三点"
  });
  assert.equal(bad.ok, false);
  const good = registry.validateArguments("create_reminder", {
    title: "取快递",
    timezone: "Asia/Shanghai",
    dueAt: "2026-11-10T15:00:00+08:00"
  });
  assert.equal(good.ok, true);
});

test("未知工具不通过白名单校验", () => {
  assert.equal(registry.get("run_shell"), null);
  assert.equal(registry.validateArguments("run_shell", {}).ok, false);
});

test("写操作带有确认策略", () => {
  assert.equal(registry.get("create_reminder").requiresConfirmation, true);
  assert.equal(registry.get("create_calendar_event").requiresConfirmation, true);
  assert.equal(registry.get("get_weather").requiresConfirmation, false);
});
