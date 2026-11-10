const SKILL_LABELS = {
  schedule: "日程与提醒",
  travel: "天气与出行",
  health: "健康摘要",
  content: "分享内容",
  communication: "短信草稿",
  music: "音乐",
  memory: "记忆偏好",
  research: "公开信息"
};

const TOOL_PERMISSIONS = {
  create_reminder: ["reminder"],
  list_reminders: ["reminder"],
  update_reminder: ["reminder"],
  delete_reminder: ["reminder"],
  list_calendar_events: ["calendarRead"],
  create_calendar_event: ["calendarWrite"],
  update_calendar_event: ["calendarWrite"],
  delete_calendar_event: ["calendarWrite"],
  get_weather: ["location"],
  search_places: ["location"],
  open_navigation: ["location"],
  get_activity_summary: ["activityRead"],
  search_music_library: ["music"],
  play_music: ["music"],
  pause_music: ["music"],
  resume_music: ["music"],
  skip_music_track: ["music"],
  get_playback_state: ["music"],
  prepare_message: ["contacts", "messages"],
  list_memory: [],
  set_memory: [],
  delete_memory: [],
  search_web: [],
  fetch_web_content: []
};

export const DEVICE_TOOLS = new Set([
  "create_reminder",
  "list_reminders",
  "update_reminder",
  "delete_reminder",
  "list_calendar_events",
  "create_calendar_event",
  "update_calendar_event",
  "delete_calendar_event",
  "get_weather",
  "get_activity_summary",
  "search_places",
  "open_navigation",
  "prepare_message",
  "search_music_library",
  "play_music",
  "pause_music",
  "resume_music",
  "skip_music_track",
  "get_playback_state",
  "list_memory",
  "set_memory",
  "delete_memory",
  "search_web",
  "fetch_web_content"
]);

export function isDeviceTool(name) {
  return DEVICE_TOOLS.has(name);
}

export function executionLocationFor(name, executionMode = "mock") {
  if (executionMode === "mock") return "backend-mock";
  return isDeviceTool(name) ? "phone" : "backend";
}

const PERMISSION_LABELS = {
  reminder: "提醒事项",
  calendarRead: "日历读取",
  calendarWrite: "日历写入",
  music: "音乐库",
  location: "定位",
  activityRead: "运动数据",
  contacts: "通讯录",
  messages: "信息"
};

export function permissionLabel(key) {
  return PERMISSION_LABELS[key] ?? key;
}

export function permissionKeysForTool(name) {
  return TOOL_PERMISSIONS[name] ?? [];
}

export function buildCapabilityManifest({
  registry,
  implemented = [],
  permissions = {},
  executionMode = "mock",
  executionLocation = "backend",
  locationFor = null
}) {
  const implementedSet = new Set(implemented);
  return registry.names().map((name) => {
    const tool = registry.get(name);
    const keys = permissionKeysForTool(name);
    const denied = keys.find((key) => permissions[key] === "denied");
    const unknown = keys.find((key) => permissions[key] === undefined || permissions[key] === "unknown");
    const isImplemented = implementedSet.has(name);

    let availability = "available";
    let authorization = "granted";
    let reason = "";

    if (!isImplemented) {
      availability = "not_implemented";
      authorization = "unknown";
      reason = "当前执行器没有该工具的真实或模拟实现";
    } else if (denied) {
      availability = "needs_authorization";
      authorization = "denied";
      reason = `需要先授权${permissionLabel(denied)}；用户可以拒绝并继续使用其他能力`;
    } else if (unknown) {
      authorization = "unknown";
      reason = `${permissionLabel(unknown)}权限状态未知；调用时由系统请求，不能预先视为已授权`;
    }

    return {
      name,
      skill: tool.skill,
      skillLabel: SKILL_LABELS[tool.skill] ?? tool.skill,
      implemented: isImplemented,
      executionLocation: typeof locationFor === "function" ? locationFor(name) : executionLocation,
      executionMode,
      availability,
      authorization,
      requiresConfirmation: tool.requiresConfirmation,
      reason
    };
  });
}

export function allowedToolNames(manifest) {
  return manifest
    .filter((item) => item.availability === "available")
    .map((item) => item.name);
}

export function describeCapabilities(manifest) {
  const bySkill = new Map();
  for (const item of manifest) {
    const list = bySkill.get(item.skillLabel) ?? [];
    list.push(item);
    bySkill.set(item.skillLabel, list);
  }

  const lines = [];
  for (const [skill, items] of bySkill) {
    const usable = items.filter((item) => item.availability === "available");
    const blocked = items.filter((item) => item.availability === "needs_authorization");
    const missing = items.filter((item) => item.availability === "not_implemented");
    const parts = [];
    if (usable.length) {
      const simulated = usable.every((item) => item.executionMode === "mock");
      parts.push(`${usable.map((item) => item.name).join("、")}${simulated ? "（模拟执行）" : ""}`);
    }
    if (blocked.length) parts.push(`${blocked.map((item) => item.name).join("、")}（需要授权）`);
    if (missing.length) parts.push(`${missing.map((item) => item.name).join("、")}（尚未实现）`);
    lines.push(`- ${skill}：${parts.join("；")}`);
  }
  return lines.join("\n");
}

export function permissionSummary(permissions = {}) {
  return Object.entries(permissions)
    .map(([key, value]) => `${key}=${value}`)
    .join(" ");
}
