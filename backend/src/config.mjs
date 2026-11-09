import { fileURLToPath } from "node:url";

const dataPath = (name) => fileURLToPath(new URL(`../data/${name}`, import.meta.url));

export function loadConfig(env = process.env) {
  const modelMode = env.MODEL_MODE ?? (env.DEEPSEEK_API_KEY ? "deepseek" : "mock");
  if (!["mock", "deepseek"].includes(modelMode)) {
    throw new Error(`MODEL_MODE 必须是 mock 或 deepseek，当前为 ${modelMode}`);
  }
  const executionModeRaw = env.EXECUTION_MODE ?? "mock";
  if (!["mock", "device", "ios"].includes(executionModeRaw)) {
    throw new Error(`EXECUTION_MODE 必须是 mock、device 或 ios，当前为 ${executionModeRaw}`);
  }
  const executionMode = executionModeRaw === "device" ? "ios" : executionModeRaw;

  return {
    contractVersion: "1.0",
    port: Number(env.PORT ?? 8787),
    host: env.HOST ?? "127.0.0.1",
    authToken: env.WHALE_AUTH_TOKEN ?? "",
    modelMode,
    executionMode,
    deepseek: {
      baseUrl: (env.DEEPSEEK_BASE_URL ?? "https://api.deepseek.com").replace(/\/+$/, ""),
      apiKey: env.DEEPSEEK_API_KEY ?? "",
      model: env.DEEPSEEK_MODEL ?? "deepseek-chat",
      timeoutMs: Number(env.MODEL_TIMEOUT_MS ?? 30000)
    },
    caps: {
      maxModelCalls: Number(env.MAX_MODEL_CALLS ?? 5),
      maxToolBatches: Number(env.MAX_TOOL_BATCHES ?? 3),
      maxConversations: Number(env.MAX_CONVERSATIONS ?? 200)
    },
    paths: {
      tools: fileURLToPath(new URL("../../contracts/v1/tools.v1.json", import.meta.url)),
      toolDefinition: fileURLToPath(new URL("../../contracts/v1/tool-definition.schema.json", import.meta.url)),
      events: fileURLToPath(new URL("../../contracts/v1/events.v1.json", import.meta.url)),
      prompt: env.PROMPT_PATH ?? fileURLToPath(new URL("../../prompts/assistant-system.v1.txt", import.meta.url)),
      operationLog: env.OPERATION_LOG_PATH ?? dataPath("operations.jsonl"),
      reminders: env.REMINDERS_PATH ?? dataPath("reminders.json"),
      calendar: env.CALENDAR_PATH ?? dataPath("calendar.json"),
      turns: env.TURNS_PATH ?? dataPath("turns")
    }
  };
}
