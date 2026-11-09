import test from "node:test";
import assert from "node:assert/strict";
import {
  buildTaskPlan,
  finalizeTask,
  parseRadiusMeters,
  updateTaskFromToolResult
} from "../src/taskPlan.mjs";

test("半径解析支持公里、米、km 与中文数字", () => {
  assert.equal(parseRadiusMeters("找附近2公里的烧烤"), 2000);
  assert.equal(parseRadiusMeters("两公里内"), 2000);
  assert.equal(parseRadiusMeters("500米内"), 500);
  assert.equal(parseRadiusMeters("3km 内"), 3000);
  assert.equal(parseRadiusMeters("附近看看"), null);
});

test("附近查价任务保留定位、半径与价格缺口", () => {
  const task = buildTaskPlan("找附近2公里的烧烤，查一下价格");
  assert.ok(task);
  assert.equal(task.constraints.locationMode, "current");
  assert.equal(task.constraints.radiusMeters, 2000);
  assert.equal(task.constraints.priceRequested, true);
  assert.ok(task.remaining.includes("取得当前位置并搜索候选地点"));
  assert.ok(task.remaining.includes("取得可核对的价格来源"));
});

test("导航任务只在用户明确要求时建立", () => {
  assert.equal(buildTaskPlan("帮我看看明天下午的安排"), null);
  const task = buildTaskPlan("带我去");
  assert.ok(task);
  assert.equal(task.constraints.navigationRequested, true);
});

test("搜索成功后移除地点缺口并记录半径事实", () => {
  const task = buildTaskPlan("找附近2公里的咖啡店");
  updateTaskFromToolResult(task, "search_places", {
    status: "success",
    data: {
      count: 3,
      locationMode: "current",
      radiusMeters: 2000,
      radiusApplied: true,
      distanceType: "straight_line"
    }
  });
  assert.equal(task.remaining.length, 0);
  assert.equal(task.observations.length, 1);
  assert.equal(task.observations[0].radiusApplied, true);
});

test("未真正应用半径时保留核对缺口", () => {
  const task = buildTaskPlan("找附近2公里的咖啡店");
  updateTaskFromToolResult(task, "search_places", {
    status: "success",
    data: { count: 3, radiusMeters: 2000, radiusApplied: false }
  });
  assert.ok(task.remaining.includes("按半径核对候选"));
  assert.equal(finalizeTask(task).state, "completed_with_limits");
});

test("价格缺口未补齐时最终状态为部分完成", () => {
  const task = buildTaskPlan("附近烧烤多少钱");
  updateTaskFromToolResult(task, "search_places", {
    status: "success",
    data: { count: 4, locationMode: "current", radiusMeters: 2000, radiusApplied: true }
  });
  assert.deepEqual(task.remaining, ["取得可核对的价格来源"]);
  assert.equal(finalizeTask(task).state, "completed_with_limits");
});

test("明确地区附近搜索不建立当前位置约束", () => {
  const task = buildTaskPlan("查一下杭州西湖附近的咖啡店");
  assert.equal(task.constraints.locationMode, "region");
  assert.equal(task.constraints.region, "杭州西湖");
  assert.ok(task.remaining.includes("在明确地区搜索候选地点"));
  assert.ok(!task.remaining.includes("取得当前位置并搜索候选地点"));
});

test("我附近与公司附近仍按当前位置处理", () => {
  assert.equal(buildTaskPlan("我家附近的咖啡店").constraints.locationMode, "current");
  assert.equal(buildTaskPlan("公司附近的咖啡店").constraints.locationMode, "current");
});

test("地区搜索成功后移除地区缺口并保留 region 事实", () => {
  const task = buildTaskPlan("杭州西湖附近的咖啡店");
  updateTaskFromToolResult(task, "search_places", {
    status: "success",
    data: { count: 2, locationMode: "region", radiusMeters: null, radiusApplied: false }
  });
  assert.equal(task.remaining.length, 0);
  assert.equal(task.constraints.locationMode, "region");
  assert.equal(task.constraints.region, "杭州西湖");
});
