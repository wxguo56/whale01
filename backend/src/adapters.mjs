import { isReminderIntent, parseReminderIntent } from "./time.mjs";

export class ModelError extends Error {
  constructor(message, { code = "model_error", status = null } = {}) {
    super(message);
    this.name = "ModelError";
    this.code = code;
    this.status = status;
  }
}

export class MockModelAdapter {
  constructor({ now = () => new Date() } = {}) {
    this.now = now;
  }

  async chat({ messages, context }) {
    const lastToolIndex = messages.findLastIndex((message) => message.role === "tool");
    if (lastToolIndex >= 0) {
      const toolMessages = messages.slice(lastToolIndex).filter((message) => message.role === "tool");
      return { content: toolMessages.map((message) => this.#finalText(message)).join("\n"), toolCalls: [] };
    }

    const lastUser = messages.findLast((message) => message.role === "user")?.content ?? "";
    if (!isReminderIntent(lastUser)) {
      return {
        content: "当前 Mock 模型只覆盖提醒场景。配置 DeepSeek 后可处理天气、日历、出行等请求。",
        toolCalls: []
      };
    }

    const intent = parseReminderIntent(lastUser, context.now, context.timezone);
    if (intent.needsTime) {
      return { content: "这条提醒要定在几点？请补充具体时间。", toolCalls: [] };
    }
    if (intent.needsPeriod) {
      return { content: `你指的是上午 ${intent.parsedHour} 点还是下午 ${intent.parsedHour} 点？`, toolCalls: [] };
    }

    const args = { title: intent.title, timezone: context.timezone };
    if (intent.dueAt) args.dueAt = intent.dueAt;
    return {
      content: "",
      toolCalls: [{ id: "call_mock_1", name: "create_reminder", arguments: JSON.stringify(args) }]
    };
  }

  #finalText(toolMessage) {
    let parsed;
    try {
      parsed = JSON.parse(toolMessage.content);
    } catch {
      return "工具返回了无法解析的结果，请重试。";
    }
    if (parsed.status === "success") {
      const due = parsed.data?.dueAt ? `，时间 ${this.#readableTime(parsed.data.dueAt)}` : "";
      return `已创建提醒：${parsed.data?.title ?? "提醒"}${due}。`;
    }
    if (parsed.status === "cancelled") return "已取消本次操作，没有写入系统。";
    if (parsed.status === "needs_confirmation") return "请确认后再执行。";
    if (parsed.status === "unsupported") return "该操作当前不受支持，未执行。";
    return `操作未完成：${parsed.error?.message ?? parsed.status}`;
  }

  #readableTime(iso) {
    const match = /^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2})/.exec(iso);
    return match ? `${match[1]} ${match[2]}` : iso;
  }
}

export class DeepSeekAdapter {
  constructor({ baseUrl, apiKey, model, timeoutMs = 30000 }) {
    this.baseUrl = baseUrl;
    this.apiKey = apiKey;
    this.model = model;
    this.timeoutMs = timeoutMs;
  }

  async chat({ messages, tools, onDelta }) {
    if (!this.apiKey) throw new ModelError("缺少 DEEPSEEK_API_KEY", { code: "missing_api_key" });

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const response = await fetch(`${this.baseUrl}/chat/completions`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${this.apiKey}`
        },
        body: JSON.stringify({
          model: this.model,
          messages,
          tools,
          tool_choice: "auto",
          stream: true
        }),
        signal: controller.signal
      });

      if (!response.ok) {
        const body = await response.text().catch(() => "");
        throw new ModelError(`DeepSeek 返回 HTTP ${response.status}`, {
          code: response.status === 429 ? "rate_limited" : "upstream_error",
          status: response.status
        });
      }

      const contentType = response.headers.get("content-type") ?? "";
      if (contentType.includes("text/event-stream")) {
        return await this.#readEventStream(response, onDelta);
      }

      const json = await response.json();
      const message = json.choices?.[0]?.message ?? {};
      return {
        content: message.content ?? "",
        toolCalls: (message.tool_calls ?? []).map((call) => ({
          id: call.id,
          name: call.function?.name,
          arguments: call.function?.arguments ?? "{}"
        }))
      };
    } catch (error) {
      if (error.name === "AbortError") {
        throw new ModelError("模型请求超时", { code: "model_timeout" });
      }
      if (error instanceof ModelError) throw error;
      throw new ModelError(`模型请求失败：${error.message}`, { code: "network_error" });
    } finally {
      clearTimeout(timer);
    }
  }

  async #readEventStream(response, onDelta) {
    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    const calls = new Map();
    let buffer = "";
    let content = "";

    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });

      let newline = buffer.indexOf("\n");
      while (newline >= 0) {
        const line = buffer.slice(0, newline).trim();
        buffer = buffer.slice(newline + 1);
        newline = buffer.indexOf("\n");

        if (!line.startsWith("data:")) continue;
        const data = line.slice(5).trim();
        if (!data || data === "[DONE]") continue;

        let chunk;
        try {
          chunk = JSON.parse(data);
        } catch {
          continue;
        }

        const delta = chunk.choices?.[0]?.delta ?? {};
        if (typeof delta.content === "string" && delta.content) {
          content += delta.content;
          if (onDelta) onDelta(delta.content);
        }

        for (const part of delta.tool_calls ?? []) {
          const key = part.index ?? 0;
          const current = calls.get(key) ?? { id: "", name: "", arguments: "" };
          if (part.id) current.id = part.id;
          if (part.function?.name) current.name = part.function.name;
          if (part.function?.arguments) current.arguments += part.function.arguments;
          calls.set(key, current);
        }
      }
    }

    return {
      content,
      toolCalls: [...calls.entries()]
        .sort((left, right) => left[0] - right[0])
        .map(([index, call]) => ({
          id: call.id || `call_${index}`,
          name: call.name,
          arguments: call.arguments || "{}"
        }))
    };
  }
}
