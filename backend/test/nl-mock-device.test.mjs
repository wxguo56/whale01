import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { MockDeviceExecutor } from "../src/mockDevice.mjs";

async function executor() {
  const dir = await mkdtemp(join(tmpdir(), "whale01-device-"));
  return new MockDeviceExecutor({
    remindersPath: join(dir, "reminders.json"),
    calendarPath: join(dir, "calendar.json")
  });
}

test("模拟音乐可查询、播放、暂停、继续与切歌", async () => {
  const device = await executor();
  const context = { conversationId: "conv_test_music", permissions: { music: "granted" } };

  const search = await device.execute({ tool: "search_music_library", arguments: {}, ...context });
  assert.equal(search.status, "success");
  assert.equal(search.data.tracks.length, 3);
  assert.equal(search.data.simulated, true);

  const selected = search.data.tracks.find((track) => track.title === "夜航");
  const play = await device.execute({ tool: "play_music", arguments: { trackId: selected.trackId }, ...context });
  assert.equal(play.status, "success");
  assert.equal(play.data.state, "playing");
  assert.equal(play.data.track.title, "夜航");
  assert.equal(play.data.audioOutput, false);

  const pause = await device.execute({ tool: "pause_music", arguments: {}, ...context });
  assert.equal(pause.data.state, "paused");

  const resume = await device.execute({ tool: "resume_music", arguments: {}, ...context });
  assert.equal(resume.data.state, "playing");

  const skip = await device.execute({ tool: "skip_music_track", arguments: { direction: "next" }, ...context });
  assert.equal(skip.status, "success");
  assert.equal(skip.data.atBoundary, true);

  const state = await device.execute({ tool: "get_playback_state", arguments: {}, ...context });
  assert.equal(state.data.state, "playing");
  assert.equal(state.data.track.title, "夜航");
});

test("音乐未授权时不执行", async () => {
  const device = await executor();
  const result = await device.execute({
    tool: "play_music",
    arguments: { trackId: "music_demo_1" },
    conversationId: "conv_test_music2",
    permissions: { music: "denied" }
  });
  assert.equal(result.status, "needs_authorization");
  assert.equal(result.error.permission, "music");
});

test("杭州次日天气与健康无数据保持事实边界", async () => {
  const device = await executor();
  const weather = await device.execute({
    tool: "get_weather",
    arguments: {
      locationName: "杭州",
      startAt: "2026-11-10T00:00:00+08:00",
      endAt: "2026-11-10T23:59:59+08:00",
      timezone: "Asia/Shanghai"
    },
    permissions: { location: "granted" }
  });
  assert.equal(weather.data.condition, "rainy");
  assert.equal(weather.data.simulated, true);

  const activity = await device.execute({
    tool: "get_activity_summary",
    arguments: {
      startAt: "2026-11-09T00:00:00+08:00",
      endAt: "2026-11-09T23:59:59+08:00",
      timezone: "Asia/Shanghai"
    },
    permissions: { activityRead: "unknown" }
  });
  assert.equal(activity.data.state, "no_data");
  assert.match(activity.data.note, /不能推断为 0/);
});
