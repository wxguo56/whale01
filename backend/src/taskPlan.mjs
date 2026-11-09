const NEARBY_PATTERN = /附近|周边|离我|当前位置|我这|旁边/;
const MERCHANT_PATTERN = /店|餐厅|咖啡|烧烤|火锅|商场|超市|酒吧|饭店|馆|摊/;
const PRICE_PATTERN = /价格|多少钱|人均|预算|贵不贵|性价比|菜单|收费/;
const NAVIGATION_PATTERN = /导航|带我去|怎么走|路线|过去/;

const CHINESE_NUMBERS = {
  一: 1,
  二: 2,
  两: 2,
  三: 3,
  四: 4,
  五: 5,
  六: 6,
  七: 7,
  八: 8,
  九: 9,
  十: 10
};

export function parseRadiusMeters(text) {
  const match = /([0-9]+(?:\.[0-9]+)?|[一二两三四五六七八九十]{1,3})\s*(公里|千米|km|KM|米|m)(?![a-zA-Z])/.exec(
    text
  );
  if (!match) return null;
  const raw = match[1];
  const value = /^[0-9]/.test(raw) ? Number(raw) : CHINESE_NUMBERS[raw];
  if (!Number.isFinite(value) || value <= 0) return null;
  const unit = match[2];
  const meters = unit === "公里" || unit === "千米" || unit.toLowerCase() === "km" ? value * 1000 : value;
  return Math.min(Math.max(Math.round(meters), 100), 50_000);
}

export function buildTaskPlan(text) {
  const input = String(text ?? "").trim();
  if (!input) return null;

  const nearby = NEARBY_PATTERN.test(input);
  const merchant = MERCHANT_PATTERN.test(input);
  const priceRequested = PRICE_PATTERN.test(input) && (nearby || merchant);
  const navigationRequested = NAVIGATION_PATTERN.test(input);
  const radiusMeters = parseRadiusMeters(input);

  if (!nearby && !priceRequested && !navigationRequested) return null;

  const constraints = {};
  const remaining = [];
  if (nearby) {
    constraints.locationMode = "current";
    remaining.push("取得当前位置并搜索候选地点");
  }
  if (radiusMeters) constraints.radiusMeters = radiusMeters;
  if (priceRequested) {
    constraints.priceRequested = true;
    remaining.push("取得可核对的价格来源");
  }
  if (navigationRequested) {
    constraints.navigationRequested = true;
    remaining.push("把选定地点交给系统地图");
  }

  return {
    goal: input.slice(0, 160),
    constraints,
    observations: [],
    remaining,
    state: "running"
  };
}

export function updateTaskFromToolResult(task, toolName, result) {
  if (!task) return task;
  const status = result?.status ?? "unknown";
  const data = result?.data ?? null;

  if (toolName === "search_places") {
    if (status === "success" && data && typeof data === "object") {
      task.remaining = task.remaining.filter((item) => item !== "取得当前位置并搜索候选地点");
      if (data.locationMode) task.constraints.locationMode = data.locationMode;
      if (Number.isFinite(data.radiusMeters)) task.constraints.radiusMeters = data.radiusMeters;
      if (data.radiusMeters && data.radiusApplied !== true) {
        const label = "按半径核对候选";
        if (!task.remaining.includes(label)) task.remaining.push(label);
      }
      task.observations.push({
        tool: toolName,
        status,
        count: Number.isFinite(data.count) ? data.count : null,
        locationMode: data.locationMode ?? null,
        radiusMeters: Number.isFinite(data.radiusMeters) ? data.radiusMeters : null,
        radiusApplied: data.radiusApplied === true,
        distanceType: data.distanceType ?? null
      });
    }
  }

  if (toolName === "open_navigation" && (status === "success" || status === "opened_external_app")) {
    task.remaining = task.remaining.filter((item) => item !== "把选定地点交给系统地图");
    task.observations.push({ tool: toolName, status, handoff: data?.handoff ?? null });
  }

  return task;
}

export function finalizeTask(task, status = "completed") {
  if (!task) return null;
  task.state = task.remaining.length ? "completed_with_limits" : status;
  return task;
}

export function describeTaskGaps(task) {
  if (!task?.remaining?.length) return "";
  return `本轮仍未完成：${task.remaining.join("、")}。最终回复必须如实说明这些缺口，不能声称已完成，也不能用导航、预算推测或常识替代。`;
}

export function publicTask(task) {
  if (!task) return null;
  return {
    goal: task.goal,
    constraints: { ...task.constraints },
    observations: task.observations.map((item) => ({ ...item })),
    remaining: [...task.remaining],
    state: task.state
  };
}
