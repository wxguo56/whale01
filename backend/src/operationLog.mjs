import { appendFile, mkdir, readFile } from "node:fs/promises";
import { dirname } from "node:path";

export class OperationLog {
  constructor(filePath) {
    this.filePath = filePath;
    this.entries = new Map();
  }

  static async open(filePath) {
    await mkdir(dirname(filePath), { recursive: true });
    const log = new OperationLog(filePath);
    try {
      const content = await readFile(filePath, "utf8");
      for (const line of content.split("\n")) {
        if (!line.trim()) continue;
        try {
          const entry = JSON.parse(line);
          if (entry.operationId) log.entries.set(entry.operationId, entry);
        } catch {
          // 损坏的历史行不阻塞启动；保留原文件供排查。
        }
      }
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
    return log;
  }

  get(operationId) {
    return this.entries.get(operationId) ?? null;
  }

  async begin({ operationId, turnId, tool, arguments: args }) {
    const existing = this.get(operationId);
    if (existing) return existing;
    const entry = {
      ts: new Date().toISOString(),
      operationId,
      turnId,
      tool,
      arguments: args,
      status: "started",
      result: null
    };
    await this.#append(entry);
    this.entries.set(operationId, entry);
    return entry;
  }

  async complete(operationId, result) {
    const existing = this.get(operationId);
    const entry = {
      ts: new Date().toISOString(),
      operationId,
      turnId: existing?.turnId ?? null,
      tool: existing?.tool ?? null,
      arguments: existing?.arguments ?? null,
      status: result.status,
      result
    };
    await this.#append(entry);
    this.entries.set(operationId, entry);
    return entry;
  }

  async #append(entry) {
    await appendFile(this.filePath, `${JSON.stringify(entry)}\n`, "utf8");
  }
}
