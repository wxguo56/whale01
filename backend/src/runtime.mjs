import { loadConfig } from "./config.mjs";
import { ToolRegistry } from "./registry.mjs";
import { OperationLog } from "./operationLog.mjs";
import { MockDeviceExecutor } from "./mockDevice.mjs";
import { DeepSeekAdapter, MockModelAdapter } from "./adapters.mjs";
import { Agent } from "./agent.mjs";

export async function createRuntime(env = process.env, overrides = {}) {
  const config = loadConfig(env);
  const registry = overrides.registry ?? ToolRegistry.fromFile(config.paths.tools, config.paths.toolDefinition);
  const operationLog = overrides.operationLog ?? (await OperationLog.open(config.paths.operationLog));
  const executor = overrides.executor ?? new MockDeviceExecutor({ remindersPath: config.paths.reminders });
  const adapter =
    overrides.adapter ??
    (config.modelMode === "deepseek" ? new DeepSeekAdapter(config.deepseek) : new MockModelAdapter());
  const agent = new Agent({
    adapter,
    registry,
    executor,
    operationLog,
    caps: config.caps,
    contractVersion: config.contractVersion
  });
  return { config, registry, operationLog, executor, adapter, agent };
}
