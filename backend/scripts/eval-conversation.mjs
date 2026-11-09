import { mkdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { loadLocalEnv } from "../src/env.mjs";

loadLocalEnv();
const { loadConfig } = await import("../src/config.mjs");
const { ToolRegistry } = await import("../src/registry.mjs");
const { OperationLog } = await import("../src/operationLog.mjs");
const { MockDeviceExecutor } = await import("../src/mockDevice.mjs");
const { DeepSeekAdapter, MockModelAdapter } = await import("../src/adapters.mjs");
const { Agent } = await import("../src/agent.mjs");
const { ConversationStore } = await import("../src/conversation.mjs");
const { loadSystemPrompt } = await import("../src/prompt.mjs");

const root = fileURLToPath(new URL("../../", import.meta.url));
const casesPath = join(root, "quality/conversation-cases.v1.json");
const reportDir = join(root, "quality/reports");
const config = loadConfig(process.env);
const registry = ToolRegistry.fromFile(config.paths.tools, config.paths.toolDefinition);
const operationLog = await OperationLog.open(join(root, "backend/data/eval-operations.jsonl"));
const executor = new MockDeviceExecutor({ remindersPath: join(root, "backend/data/eval-reminders.json") });
const adapter =
  config.modelMode === "deepseek" ? new DeepSeekAdapter(config.deepseek) : new MockModelAdapter();
const systemPrompt = loadSystemPrompt(config.paths.prompt);

const corpus = JSON.parse(await readFile(casesPath, "utf8"));
const results = [];
const startedAt = new Date().toISOString();

for (const testCase of corpus.cases) {
  const fixture = resolveFixture(testCase.fixture);
  const conversationId = `conv_eval_${testCase.id.toLowerCase().replaceAll("-", "_")}`;
  const conversations = new ConversationStore();
  const { conversation } = conversations.ensure(conversationId);
  seedFixture(conversations, conversationId, fixture);
  if (fixture.lastEntities?.musicCandidates) executor.seedTracks(fixture.lastEntities.musicCandidates);
  if (fixture.playback) {
    const playback = executor.seedPlayback(conversationId, fixture.playback);
    conversations.setEntities(conversationId, { playback });
  }
  const scopedExecutor = capabilityScopedExecutor(executor, fixture, registry);

  const agent = new Agent({
    adapter,
    registry,
    executor: scopedExecutor,
    operationLog,
    caps: config.caps,
    contractVersion: config.contractVersion,
    conversations,
    systemPrompt,
    modelMode: config.modelMode,
    executionMode: config.executionMode
  });

  const turns = [];
  const toolCalls = [];
  for (const text of testCase.userTurns) {
    const snapshot = await agent.start({
      text,
      now: fixture.now,
      timezone: fixture.timezone,
      autoConfirm: false,
      conversationId,
      permissions: fixture.permissions,
      sharedContent: fixture.sharedContent ?? null
    });
    turns.push({ text, status: snapshot.status, reply: snapshot.reply, pending: snapshot.pending });
    for (const event of snapshot.events) {
      if (event.type === "tool.requested") {
        toolCalls.push({ tool: event.payload.tool, arguments: event.payload.arguments });
      }
    }
  }

  const checks = evaluate(testCase.expect ?? {}, toolCalls, turns);
  results.push({
    id: testCase.id,
    category: testCase.category,
    fixture: testCase.fixture,
    userTurns: testCase.userTurns,
    replies: turns.map((turn) => turn.reply),
    statuses: turns.map((turn) => turn.status),
    toolCalls,
    pending: turns.at(-1)?.pending ?? [],
    checks,
    passed: checks.every((check) => check.ok),
    manualNotes: (testCase.expect?.must ?? []).concat(
      (testCase.expect?.mustNot ?? []).map((item) => `不得：${item}`)
    )
  });
  console.log(`${testCase.id} ${results.at(-1).passed ? "PASS" : "CHECK"} ${toolCalls.map((c) => c.tool).join(",") || "chat"}`);
}

const summary = {
  specVersion: corpus.specVersion,
  project: corpus.project,
  modelMode: config.modelMode,
  executionMode: config.executionMode,
  model: config.modelMode === "deepseek" ? config.deepseek.model : "mock",
  startedAt,
  finishedAt: new Date().toISOString(),
  total: results.length,
  deterministicPassed: results.filter((result) => result.passed).length,
  results
};

await mkdir(reportDir, { recursive: true });
await writeFile(join(reportDir, "conversation-eval.latest.json"), JSON.stringify(summary, null, 2), "utf8");
await writeFile(join(reportDir, "conversation-eval.latest.md"), renderMarkdown(summary), "utf8");
console.log(`report: ${join(reportDir, "conversation-eval.latest.md")}`);

function resolveFixture(name) {
  const raw = corpus.fixtures[name];
  if (!raw) throw new Error(`未知夹具 ${name}`);
  if (!raw.extends) return structuredClone(raw);
  return deepMerge(resolveFixture(raw.extends), structuredClone(raw));
}

function deepMerge(base, overlay) {
  const result = { ...base };
  for (const [key, value] of Object.entries(overlay)) {
    if (key === "extends") continue;
    if (Array.isArray(value) || value === null || typeof value !== "object") result[key] = value;
    else result[key] = deepMerge(base?.[key] ?? {}, value);
  }
  return result;
}

function seedFixture(conversations, conversationId, fixture) {
  for (const task of fixture.openTasks ?? []) {
    conversations.upsertTask(conversationId, {
      taskId: task.taskId,
      kind: task.kind,
      state: task.state,
      operationId: task.operationId ?? `op_${task.taskId}`,
      turnId: `turn_seed_${task.taskId}`,
      knownArguments: task.knownArguments ?? {},
      missingFields: task.missingFields ?? []
    });
  }
  if (fixture.lastEntities) conversations.setEntities(conversationId, fixture.lastEntities);
  if (fixture.lastResults) conversations.setEntities(conversationId, { lastResults: fixture.lastResults });
}

function capabilityScopedExecutor(base, fixture, registry) {
  const unimplementedSkills = new Set(
    Object.entries(fixture.capabilities ?? {})
      .filter(([, value]) => value === "not_implemented")
      .map(([skill]) => skill)
  );
  if (!unimplementedSkills.size) return base;
  return {
    capabilities: () =>
      base
        .capabilities()
        .filter((name) => !unimplementedSkills.has(registry.get(name)?.skill)),
    execute: (request) => base.execute(request)
  };
}

function evaluate(expect, toolCalls, turns) {
  const checks = [];
  const names = toolCalls.map((call) => call.tool);
  const deviceNames = names.filter((name) => name !== "cancel_active_task");
  if (expect.deviceTools === "none") {
    checks.push({ name: "不调用设备工具", ok: deviceNames.length === 0, actual: deviceNames });
  }
  if (expect.deviceTools === "no_calendar_read_before_authorization") {
    checks.push({
      name: "授权前不调用任何设备工具",
      ok: deviceNames.length === 0,
      actual: deviceNames
    });
  }
  if (expect.deviceTools === "no_create_as_update") {
    checks.push({
      name: "不把新建工具当修改",
      ok: !names.includes("create_reminder") && !names.includes("create_calendar_event"),
      actual: names
    });
  }
  if (expect.deviceTools === "none_before_trusted_confirmation") {
    checks.push({
      name: "可信确认前不执行写操作",
      ok: !names.some((name) => ["create_reminder", "create_calendar_event", "prepare_message"].includes(name)),
      actual: names
    });
  }
  if (Array.isArray(expect.proposedTools)) {
    checks.push({
      name: "调用预期工具",
      ok: expect.proposedTools.every((name) => names.includes(name)),
      expected: expect.proposedTools,
      actual: names
    });
  }
  if (expect.noDuplicateTools) {
    const duplicates = [...new Set(names.filter((name, index) => names.indexOf(name) !== index))];
    checks.push({
      name: "同一工具不重复调用",
      ok: duplicates.length === 0,
      expected: [],
      actual: duplicates
    });
  }
  if (expect.arguments) {
    const actual = toolCalls.map((call) => call.arguments ?? {});
    const ok = Object.entries(expect.arguments).every(([key, value]) =>
      actual.some((args) => argumentAliases(key).some((alias) => args[alias] === value))
    );
    checks.push({ name: "参数匹配", ok, expected: expect.arguments, actual });
  }
  if (expect.state) {
    const expectedState = normalizeState(expect.state);
    checks.push({
      name: "任务状态",
      ok: turns.at(-1)?.status === expectedState,
      expected: expect.state,
      actual: turns.at(-1)?.status
    });
  }
  return checks;
}

function normalizeState(state) {
  return { waiting_confirmation: "awaiting_confirmation", waiting_user: "awaiting_user" }[state] ?? state;
}

function argumentAliases(key) {
  return { trackReference: ["trackId"], trackId: ["trackId", "trackReference"] }[key] ?? [key];
}

function renderMarkdown(summary) {
  const lines = [
    "# 自然对话基准运行报告（自动生成）",
    "",
    `- 时间：${summary.startedAt} → ${summary.finishedAt}`,
    `- 模型：${summary.modelMode}${summary.modelMode === "deepseek" ? ` / ${summary.model}` : ""}`,
    `- 执行：${summary.executionMode}（Mock）`,
    `- 总数：${summary.total}；确定性检查通过：${summary.deterministicPassed}`,
    "- 说明：确定性检查只覆盖工具轨迹与参数；must／mustNot 语义项需要人工复核，不能把本报告当作真实模型总成绩。",
    "",
    "| 用例 | 分类 | 结果 | 工具 | 实际回复 |",
    "|---|---|---|---|---|"
  ];
  for (const result of summary.results) {
    const reply = result.replies
      .filter(Boolean)
      .join(" / ")
      .replace(/\s+/g, " ")
      .replaceAll("|", "\\|")
      .slice(0, 160);
    const tools = result.toolCalls.map((call) => call.tool).join(", ") || "无";
    lines.push(`| ${result.id} | ${result.category} | ${result.passed ? "确定性通过" : "需复核"} | ${tools} | ${reply} |`);
  }
  lines.push("", "## 失败明细", "");
  const failed = summary.results.filter((result) => !result.passed);
  if (!failed.length) lines.push("无确定性检查失败。");
  for (const result of failed) {
    lines.push(`### ${result.id}`, "");
    for (const check of result.checks.filter((item) => !item.ok)) {
      lines.push(`- ${check.name}：期望 ${JSON.stringify(check.expected ?? "none")}，实际 ${JSON.stringify(check.actual)}`);
    }
    lines.push("");
  }
  return lines.join("\n");
}
