import test from "node:test";
import assert from "node:assert/strict";
import { loadConfig } from "../src/config.mjs";
import { ToolRegistry } from "../src/registry.mjs";
import { isDeviceTool } from "../src/capabilities.mjs";

const config = loadConfig({ MODEL_MODE: "mock" });
const registry = ToolRegistry.fromFile(config.paths.tools, config.paths.toolDefinition);

test("工具目录覆盖系统操作、记录修改、记忆与公开信息能力", () => {
  assert.deepEqual(registry.names().sort(), [
    "create_calendar_event",
    "create_reminder",
    "delete_calendar_event",
    "delete_memory",
    "delete_reminder",
    "fetch_web_content",
    "find_free_slots",
    "get_activity_summary",
    "get_playback_state",
    "get_weather",
    "list_calendar_events",
    "list_memory",
    "list_reminders",
    "open_navigation",
    "pause_music",
    "play_music",
    "prepare_message",
    "resume_music",
    "search_merchant_prices",
    "search_music_library",
    "search_places",
    "search_web",
    "set_memory",
    "skip_music_track",
    "summarize_shared_content",
    "update_calendar_event",
    "update_reminder"
  ]);
});

test("音乐工具需要音乐库授权且不需要逐次确认", () => {
  const play = registry.get("play_music");
  assert.equal(play.skill, "music");
  assert.deepEqual(play.requiresAuthorization, ["music"]);
  assert.equal(play.requiresConfirmation, false);
  assert.equal(registry.validateArguments("play_music", {}).ok, false);
  assert.equal(registry.validateArguments("play_music", { trackId: "music_demo_1" }).ok, true);
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

test("周期规则只接受日／周／月／年与合法星期", () => {
  const base = { title: "喝水", timezone: "Asia/Shanghai" };
  const good = registry.validateArguments("create_reminder", {
    ...base,
    recurrence: { frequency: "weekly", interval: 1, weekdays: [1, 3, 5], count: 12 }
  });
  assert.equal(good.ok, true);
  assert.equal(
    registry.validateArguments("create_reminder", {
      ...base,
      recurrence: { frequency: "hourly" }
    }).ok,
    false
  );
  assert.equal(
    registry.validateArguments("create_reminder", {
      ...base,
      recurrence: { frequency: "weekly", weekdays: [8] }
    }).ok,
    false
  );
});

test("未知工具不通过白名单校验", () => {
  assert.equal(registry.get("run_shell"), null);
  assert.equal(registry.validateArguments("run_shell", {}).ok, false);
});

test("商户价格工具要求商户名并支持分店、城市和条数限制", () => {
  assert.equal(registry.validateArguments("search_merchant_prices", {}).ok, false);
  assert.equal(
    registry.validateArguments("search_merchant_prices", {
      merchant: "海底捞",
      branch: "西湖店",
      city: "杭州",
      limit: 5
    }).ok,
    true
  );
  assert.equal(
    registry.validateArguments("search_merchant_prices", { merchant: "海底捞", limit: 20 }).ok,
    false
  );
});

test("写操作带有确认策略", () => {
  assert.equal(registry.get("create_reminder").requiresConfirmation, true);
  assert.equal(registry.get("create_calendar_event").requiresConfirmation, true);
  assert.equal(registry.get("get_weather").requiresConfirmation, false);
});

test("EXECUTION_MODE 支持 device/ios 并统一为 ios", () => {
  assert.equal(loadConfig({ MODEL_MODE: "mock", EXECUTION_MODE: "device" }).executionMode, "ios");
  assert.equal(loadConfig({ MODEL_MODE: "mock", EXECUTION_MODE: "ios" }).executionMode, "ios");
  assert.throws(
    () => loadConfig({ MODEL_MODE: "mock", EXECUTION_MODE: "real" }),
    /EXECUTION_MODE 必须是 mock、device 或 ios/
  );
});

test("设备工具清单只包含手机系统能力，摘要仍由后端模型处理", () => {
  assert.equal(isDeviceTool("create_reminder"), true);
  assert.equal(isDeviceTool("play_music"), true);
  assert.equal(isDeviceTool("summarize_shared_content"), false);
});
