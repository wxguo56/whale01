import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname } from "node:path";

export class MockDeviceExecutor {
  constructor({ remindersPath }) {
    this.remindersPath = remindersPath;
  }

  async execute({ tool, arguments: args, operationId, turnId }) {
    if (tool === "create_reminder") {
      return this.#createReminder({ args, operationId, turnId });
    }
    return {
      status: "unsupported",
      data: null,
      error: { code: "mock_tool_not_implemented", message: `Mock 设备未实现 ${tool}` },
      deduplicated: false
    };
  }

  async #createReminder({ args, operationId, turnId }) {
    if (args.dueAt && Number.isNaN(Date.parse(args.dueAt))) {
      return {
        status: "failed",
        data: null,
        error: { code: "invalid_due_at", message: "dueAt 无法解析" },
        deduplicated: false
      };
    }

    const records = await this.#read();
    const existing = records.find((record) => record.operationId === operationId);
    if (existing) {
      return {
        status: "success",
        data: {
          recordId: existing.recordId,
          title: existing.title,
          dueAt: existing.dueAt,
          timezone: existing.timezone,
          listName: existing.listName
        },
        error: null,
        deduplicated: true
      };
    }

    const record = {
      operationId,
      turnId,
      recordId: `REM-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`,
      title: args.title,
      dueAt: args.dueAt ?? null,
      timezone: args.timezone,
      listName: args.listId ?? "提醒事项",
      notes: args.notes ?? null,
      createdAt: new Date().toISOString()
    };
    records.push(record);
    await this.#write(records);

    return {
      status: "success",
      data: {
        recordId: record.recordId,
        title: record.title,
        dueAt: record.dueAt,
        timezone: record.timezone,
        listName: record.listName
      },
      error: null,
      deduplicated: false
    };
  }

  async #read() {
    try {
      const content = await readFile(this.remindersPath, "utf8");
      const parsed = JSON.parse(content);
      return Array.isArray(parsed) ? parsed : [];
    } catch (error) {
      if (error.code === "ENOENT") return [];
      throw error;
    }
  }

  async #write(records) {
    await mkdir(dirname(this.remindersPath), { recursive: true });
    const tempPath = `${this.remindersPath}.tmp`;
    await writeFile(tempPath, JSON.stringify(records, null, 2), "utf8");
    await rename(tempPath, this.remindersPath);
  }
}
