import { readFileSync } from "node:fs";
import { validateSchema } from "./validate.mjs";

export class ToolRegistry {
  constructor(catalog) {
    this.contractVersion = catalog.contractVersion;
    this.tools = new Map(catalog.tools.map((tool) => [tool.name, tool]));
  }

  static fromFile(catalogPath, definitionSchemaPath) {
    const catalog = JSON.parse(readFileSync(catalogPath, "utf8"));
    const definitionSchema = JSON.parse(readFileSync(definitionSchemaPath, "utf8"));
    if (catalog.contractVersion !== "1.0") {
      throw new Error(`不支持的工具契约版本 ${catalog.contractVersion}`);
    }
    for (const tool of catalog.tools) {
      const result = validateSchema(definitionSchema, tool);
      if (!result.ok) {
        throw new Error(`工具定义 ${tool.name} 非法：${result.errors.join("; ")}`);
      }
    }
    return new ToolRegistry(catalog);
  }

  get(name) {
    return this.tools.get(name) ?? null;
  }

  names() {
    return [...this.tools.keys()];
  }

  listForModel({ allowed = null } = {}) {
    const allowedSet = allowed ? new Set(allowed) : null;
    return [...this.tools.values()]
      .filter((tool) => !allowedSet || allowedSet.has(tool.name))
      .map((tool) => ({
      type: "function",
      function: {
        name: tool.name,
        description: `${tool.description}（需要用户确认：${tool.requiresConfirmation ? "是" : "否"}）`,
        parameters: tool.inputSchema
      }
      }));
  }

  validateArguments(name, args) {
    const tool = this.get(name);
    if (!tool) return { ok: false, errors: [`未知工具 ${name}`] };
    return validateSchema(tool.inputSchema, args);
  }
}
