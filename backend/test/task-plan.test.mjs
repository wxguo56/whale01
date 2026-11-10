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
  assert.equal(buildTaskPlan("把照片发过去"), null);
  const task = buildTaskPlan("带我去");
  assert.ok(task);
  assert.equal(task.constraints.navigationRequested, true);
});

test("回家导航要求先取得真实家庭地址，不能直接当已规划", () => {
  const task = buildTaskPlan("导航回家");
  assert.ok(task);
  assert.equal(task.constraints.navigationRequested, true);
  assert.equal(task.constraints.homeNavigation, true);
  assert.ok(task.remaining.includes("取得家庭地址并解析真实目的地"));
  assert.ok(task.remaining.includes("把选定地点交给系统地图"));

  updateTaskFromToolResult(task, "search_places", {
    status: "success",
    data: { count: 1, locationMode: "region", radiusApplied: false }
  });
  assert.deepEqual(task.remaining, ["把选定地点交给系统地图"]);
  assert.equal(finalizeTask(task).state, "completed_with_limits");
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

test("价格证据匹配分店后移除价格缺口", () => {
  const task = buildTaskPlan("杭州西湖附近的海底捞多少钱");
  updateTaskFromToolResult(task, "search_places", {
    status: "success",
    data: { count: 1, locationMode: "region", radiusApplied: false }
  });
  updateTaskFromToolResult(task, "search_merchant_prices", {
    status: "success",
    data: {
      priceDataAvailable: true,
      verified: false,
      source: "public_web",
      evidence: [{ amount: 120, kind: "per_person", branchMatch: "matched" }]
    }
  });
  assert.deepEqual(task.remaining, []);
  assert.equal(task.observations.at(-1).evidenceCount, 1);
});

test("价格证据分店未匹配时保留核对缺口", () => {
  const task = buildTaskPlan("杭州西湖附近的海底捞多少钱");
  updateTaskFromToolResult(task, "search_places", {
    status: "success",
    data: { count: 1, locationMode: "region", radiusApplied: false }
  });
  updateTaskFromToolResult(task, "search_merchant_prices", {
    status: "success",
    data: {
      priceDataAvailable: true,
      verified: false,
      source: "public_web",
      evidence: [{ amount: 120, kind: "per_person", branchMatch: "city_only" }]
    }
  });
  assert.deepEqual(task.remaining, ["核对价格对应的分店"]);
  assert.equal(finalizeTask(task).state, "completed_with_limits");
});

test("价格证据为空时不把缺口当作已补齐", () => {
  const task = buildTaskPlan("附近烧烤多少钱");
  updateTaskFromToolResult(task, "search_places", {
    status: "success",
    data: { count: 4, locationMode: "current", radiusMeters: null, radiusApplied: true }
  });
  updateTaskFromToolResult(task, "search_merchant_prices", {
    status: "success",
    data: { priceDataAvailable: false, verified: false, evidence: [] }
  });
  assert.deepEqual(task.remaining, ["取得可核对的价格来源"]);
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
