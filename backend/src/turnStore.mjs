import { mkdir, readdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

const UNFINISHED = new Set(["running", "awaiting_confirmation", "awaiting_tool_results"]);
const TERMINAL = new Set(["completed", "completed_with_limits", "failed", "cancelled", "superseded"]);

export class TurnStore {
  constructor(directory) {
    this.directory = directory;
    this.cache = new Map();
    this.timers = new Map();
  }

  static async open(directory) {
    const store = new TurnStore(directory);
    await store.init();
    return store;
  }

  async init() {
    await mkdir(this.directory, { recursive: true });
    const files = await readdir(this.directory).catch(() => []);
    for (const file of files) {
      if (!file.endsWith(".json")) continue;
      try {
        const record = JSON.parse(await readFile(join(this.directory, file), "utf8"));
        if (record?.turnId) this.cache.set(record.turnId, record);
      } catch {
        // 损坏的快照不阻塞启动。
      }
    }
    await this.markInterrupted();
  }

  async markInterrupted() {
    for (const [turnId, record] of this.cache) {
      if (!UNFINISHED.has(record.status)) continue;
      const interrupted = {
        ...record,
        status: "interrupted",
        interruptedAt: new Date().toISOString(),
        interruptionNote: "服务重启时该轮尚未结束；已保留当时的待办和回复，需要重新发起或用快照核对。"
      };
      this.cache.set(turnId, interrupted);
      await this.#write(interrupted);
    }
  }

  get(turnId) {
    return this.cache.get(turnId) ?? null;
  }

  schedule(record) {
    if (!record?.turnId) return;
    this.cache.set(record.turnId, record);
    if (this.timers.has(record.turnId)) return;
    const timer = setTimeout(() => {
      this.timers.delete(record.turnId);
      const latest = this.cache.get(record.turnId);
      if (latest) void this.#write(latest);
    }, 300);
    timer.unref?.();
    this.timers.set(record.turnId, timer);
  }

  async flush(record) {
    if (!record?.turnId) return;
    this.cache.set(record.turnId, record);
    const timer = this.timers.get(record.turnId);
    if (timer) clearTimeout(timer);
    this.timers.delete(record.turnId);
    await this.#write(record);
  }

  async #write(record) {
    const path = join(this.directory, `${record.turnId.replace(/[^a-zA-Z0-9_-]/g, "_")}.json`);
    try {
      await writeFile(path, JSON.stringify(record), "utf8");
    } catch {
      // 快照写入失败不改变业务结果；恢复能力会降级。
    }
  }

  isTerminal(status) {
    return TERMINAL.has(status);
  }
}
