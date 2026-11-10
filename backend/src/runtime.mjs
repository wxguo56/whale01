import { loadConfig } from "./config.mjs";
import { ToolRegistry } from "./registry.mjs";
import { OperationLog } from "./operationLog.mjs";
import { TurnStore } from "./turnStore.mjs";
import { MockDeviceExecutor } from "./mockDevice.mjs";
import { DeepSeekAdapter, MockModelAdapter } from "./adapters.mjs";
import { Agent } from "./agent.mjs";
import { ConversationStore } from "./conversation.mjs";
import { loadSystemPrompt } from "./prompt.mjs";

export async function createRuntime(env = process.env, overrides = {}) {
  const config = loadConfig(env);
  const registry = overrides.registry ?? ToolRegistry.fromFile(config.paths.tools, config.paths.toolDefinition);
  const operationLog = overrides.operationLog ?? (await OperationLog.open(config.paths.operationLog));
  const executor =
    overrides.executor ??
    (config.executionMode === "mock"
      ? new MockDeviceExecutor({ remindersPath: config.paths.reminders, calendarPath: config.paths.calendar })
      : {
          capabilities: () => [],
          async execute({ tool }) {
            return {
              status: "unsupported",
              data: null,
              error: {
                code: "server_side_not_implemented",
                message: `真实执行模式下后端不执行 ${tool}；请由手机执行或直接基于本轮资料回答`
              }
            };
          }
        });
  const adapter =
    overrides.adapter ??
    (config.modelMode === "deepseek" ? new DeepSeekAdapter(config.deepseek) : new MockModelAdapter());
  const conversations =
    overrides.conversations ??
    new ConversationStore({ maxConversations: config.caps.maxConversations });
  const turnStore = overrides.turnStore ?? (await TurnStore.open(config.paths.turns));
  const systemPrompt = overrides.systemPrompt ?? loadSystemPrompt(config.paths.prompt);
  const agent = new Agent({
    adapter,
    registry,
    executor,
    operationLog,
    caps: config.caps,
    contractVersion: config.contractVersion,
    turnStore,
    conversations,
    systemPrompt,
    modelMode: config.modelMode,
    executionMode: config.executionMode
  });
  return { config, registry, operationLog, executor, adapter, conversations, turnStore, agent };
}
