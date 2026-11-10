import { fileURLToPath } from "node:url";
import { join } from "node:path";
import { createRuntime } from "../src/runtime.mjs";

const dataDir = fileURLToPath(new URL("../data/demo/", import.meta.url));
const env = {
  ...process.env,
  MODEL_MODE: "mock",
  EXECUTION_MODE: "mock",
  OPERATION_LOG_PATH: join(dataDir, "operations.jsonl"),
  REMINDERS_PATH: join(dataDir, "reminders.json")
};

const runtime = await createRuntime(env);
const now = "2026-11-09T10:00:00+08:00";
const timezone = "Asia/Shanghai";

console.log("=== 场景 1：自动确认的提醒闭环 ===");
const first = await runtime.agent.start({
  text: "明天下午三点提醒我取快递",
  now,
  timezone,
  autoConfirm: true
});
printTurn(first);

console.log("\n=== 场景 2：先确认再写入 ===");
const second = await runtime.agent.start({
  text: "明天下午三点提醒我取快递",
  now,
  timezone,
  autoConfirm: false
});
printTurn(second);
const pending = second.pending[0];
if (pending) {
  const confirmed = await runtime.agent.confirm(second.turnId, pending.operationId, true);
  console.log(`确认 ${pending.operationId}`);
  printTurn(confirmed, second.events.length);
}

console.log("\n=== 场景 3：缺少具体时间时追问 ===");
const third = await runtime.agent.start({
  text: "明天提醒我取快递",
  now,
  timezone,
  autoConfirm: true
});
printTurn(third);

function printTurn(result, fromIndex = 0) {
  console.log(`turnId: ${result.turnId}`);
  for (const event of result.events.slice(fromIndex)) {
    if (event.type === "turn.started" || event.type === "turn.completed") continue;
    if (event.type === "assistant.delta") {
      console.log(`  assistant: ${event.payload.text}`);
    } else if (event.type === "tool.result") {
      console.log(`  tool.result: ${event.payload.status} ${JSON.stringify(event.payload.data ?? {})}`);
    } else if (event.type === "tool.confirmation_required") {
      console.log(`  confirmation: ${event.payload.tool} ${event.payload.operationId}`);
    } else {
      console.log(`  ${event.type}`);
    }
  }
  console.log(`  status: ${result.status}`);
}
