import test from "node:test";
import assert from "node:assert/strict";
import { FIXED_NOW, TIMEZONE } from "./helpers.mjs";
import { parseReminderIntent } from "../src/time.mjs";

test("明天下午三点解析为固定时钟下的 15:00", () => {
  const intent = parseReminderIntent("明天下午三点提醒我取快递", FIXED_NOW, TIMEZONE);
  assert.equal(intent.title, "取快递");
  assert.equal(intent.dueAt, "2026-11-10T15:00:00+08:00");
  assert.equal(intent.needsTime, false);
  assert.equal(intent.needsPeriod, false);
});

test("无日期待办不补造截止时间", () => {
  const intent = parseReminderIntent("创建待办：买牛奶", FIXED_NOW, TIMEZONE);
  assert.equal(intent.title, "买牛奶");
  assert.equal(intent.dueAt, null);
  assert.equal(intent.needsTime, false);
});

test("只有日期没有时刻时要求追问", () => {
  const intent = parseReminderIntent("明天提醒我取快递", FIXED_NOW, TIMEZONE);
  assert.equal(intent.needsTime, true);
  assert.equal(intent.dueAt, null);
});

test("缺少上午下午时要求澄清", () => {
  const intent = parseReminderIntent("明天三点提醒我取快递", FIXED_NOW, TIMEZONE);
  assert.equal(intent.needsPeriod, true);
  assert.equal(intent.dueAt, null);
});

test("其他时区按设备时区计算偏移", () => {
  const intent = parseReminderIntent("明天下午三点提醒我取快递", "2026-11-09T10:00:00Z", "Europe/Berlin");
  assert.equal(intent.dueAt, "2026-11-10T15:00:00+01:00");
});
