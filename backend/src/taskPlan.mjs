import { executableText } from "./requestIntent.mjs";
const NEARBY_PATTERN = /附近|周边|离我|当前位置|我这|旁边/;
const MERCHANT_PATTERN = /店|餐厅|咖啡|烧烤|火锅|商场|超市|酒吧|饭店|馆|摊/;
const PRICE_PATTERN = /价格|多少钱|人均|预算|贵不贵|性价比|菜单|收费/;
const NAVIGATION_PATTERN = /导航|带我去|怎么走|路线|带我过去|送我过去/;
const HOME_NAVIGATION_PATTERN = /导航回家|带我回家|送我回家|怎么回家|回家怎么走|回家路线|回家的路线/;
const REGION_NEARBY_PATTERN = /([\u4e00-\u9fa5]{2,12})(?:附近|周边|一带|这边)/;
const REGION_SUFFIX_PATTERN = /市|区|县|镇|乡|街道|路|街|大道|广场|公园|机场|车站|大学|学院|商圈|景区|湖|山|岛|湾|港/;
const REGION_WORDS = ["我家", "家里", "公司", "单位", "学校", "这里", "这儿", "身边", "附近", "当前", "这边"];
const CITY_NAMES = [
  "北京", "上海", "广州", "深圳", "杭州", "成都", "南京", "武汉", "西安", "重庆",
  "苏州", "天津", "长沙", "青岛", "厦门", "宁波", "无锡", "合肥", "济南", "郑州",
  "福州", "昆明", "大连", "沈阳", "哈尔滨", "长春", "石家庄", "太原", "南昌", "贵阳",
  "南宁", "海口", "兰州", "银川", "西宁", "乌鲁木齐", "呼和浩特", "拉萨", "香港", "澳门", "台北"
];

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

export function isHomeNavigation(text) {
  const compact = String(text ?? "").replace(/\s+/g, "");
  if (HOME_NAVIGATION_PATTERN.test(compact)) return true;
  return ["回家", "我要回家", "我想回家", "回我家"].includes(compact);
}

export function detectRegion(text) {
  const match = REGION_NEARBY_PATTERN.exec(text);
  if (!match) return null;
  const name = match[1].replace(
    /^(?:帮我|请|想|要|查一下|查|找一下|找|搜一下|搜|看看|看一下|了解|在|去|到)+/,
    ""
  );
  if (name.length < 2) return null;
  if (REGION_WORDS.some((word) => name.includes(word))) return null;
  if (REGION_SUFFIX_PATTERN.test(name) || CITY_NAMES.some((city) => name.includes(city))) {
    return name;
  }
  return null;
}

export function buildTaskPlan(text) {
  const input = executableText(text).trim();
  if (!input) return null;

  const nearby = NEARBY_PATTERN.test(input);
  const merchant = MERCHANT_PATTERN.test(input);
  const priceRequested = PRICE_PATTERN.test(input) && (nearby || merchant);
  const homeNavigation = isHomeNavigation(input);
  const navigationRequested = NAVIGATION_PATTERN.test(input) || homeNavigation;
  const radiusMeters = parseRadiusMeters(input);
  const region = detectRegion(input);

  if (!nearby && !priceRequested && !navigationRequested) return null;

  const constraints = {};
  const remaining = [];
  if (region) {
    constraints.locationMode = "region";
    constraints.region = region;
    remaining.push("在明确地区搜索候选地点");
  } else if (nearby) {
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
    if (homeNavigation) {
      constraints.homeNavigation = true;
      remaining.push("取得家庭地址并解析真实目的地");
    }
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
      task.remaining = task.remaining.filter(
        (item) => item !== "取得当前位置并搜索候选地点" && item !== "在明确地区搜索候选地点"
      );
      if (task.constraints.homeNavigation && Number(data.count) > 0) {
        task.remaining = task.remaining.filter((item) => item !== "取得家庭地址并解析真实目的地");
      }
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

  if (toolName === "search_merchant_prices" && status === "success") {
    const evidence = Array.isArray(data?.evidence) ? data.evidence : [];
    if (data?.priceDataAvailable === true && evidence.length) {
      task.remaining = task.remaining.filter((item) => item !== "取得可核对的价格来源");
      const unmatchedBranch = evidence.some((item) => item?.branchMatch !== "matched");
      const label = "核对价格对应的分店";
      if (unmatchedBranch && !task.remaining.includes(label)) task.remaining.push(label);
    }
    task.observations.push({
      tool: toolName,
      status,
      evidenceCount: evidence.length,
      verified: data?.verified === true,
      source: data?.source ?? null
    });
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
