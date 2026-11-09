import { randomUUID } from "node:crypto";

const COMPLETED = new Set(["completed", "completed_with_limits", "failed"]);

export class Agent {
  constructor({ adapter, registry, executor, operationLog, caps, contractVersion = "1.0" }) {
    this.adapter = adapter;
    this.registry = registry;
    this.executor = executor;
    this.operationLog = operationLog;
    this.caps = caps;
    this.contractVersion = contractVersion;
    this.turns = new Map();
  }

  async start({ text, now, timezone, autoConfirm = false, deferExecution = false }, { onEvent } = {}) {
    if (typeof text !== "string" || !text.trim()) throw new AgentError("text 不能为空", "invalid_input");
    if (!isValidTimeZone(timezone)) throw new AgentError(`无效时区 ${timezone}`, "invalid_input");
    const nowIso = now ?? new Date().toISOString();
    if (Number.isNaN(Date.parse(nowIso))) throw new AgentError("now 必须是 ISO 8601 时间", "invalid_input");

    const turnId = `turn_${randomUUID()}`;
    const state = {
      turnId,
      text: text.trim(),
      now: nowIso,
      timezone,
      status: "running",
      messages: [
        {
          role: "system",
          content: [
            "你是代号鲸鱼01的助手，只能通过已注册工具操作设备。",
            `当前设备时间：${nowIso}`,
            `设备时区：${timezone}`,
            "相对日期必须解析成带时区偏移的明确时间。缺少关键参数时追问，不得猜测。",
            "只有工具返回成功结果时才能声称操作已完成。"
          ].join("\n")
        },
        { role: "user", content: text.trim() }
      ],
      modelCalls: 0,
      batches: 0,
      pending: [],
      confirmed: new Set(),
      autoConfirm,
      deferExecution,
      reply: "",
      seq: 0,
      events: [],
      onEvent
    };
    this.turns.set(turnId, state);

    this.#emit(state, "turn.started", { input: state.text, timezone, now: nowIso });
    await this.#run(state).catch((error) => this.#fail(state, error));
    return this.snapshot(turnId);
  }

  async confirm(turnId, operationId, confirmed) {
    const state = this.#turn(turnId);
    if (state.status !== "awaiting_confirmation") {
      throw new AgentError(`任务当前状态为 ${state.status}，不能确认`, "invalid_state");
    }
    const target = state.pending.find((item) => item.operationId === operationId);
    if (!target) throw new AgentError("operationId 不属于当前待确认操作", "unknown_operation");

    if (!confirmed) {
      await this.operationLog.begin({
        operationId,
        turnId,
        tool: target.tool.name,
        arguments: target.args
      });
      const result = {
        status: "cancelled",
        data: null,
        error: null,
        deduplicated: false
      };
      await this.operationLog.complete(operationId, result);
      this.#emit(state, "tool.result", {
        tool: target.tool.name,
        toolCallId: target.call.id,
        operationId,
        status: "cancelled",
        data: null,
        deduplicated: false
      });
      state.messages.push({
        role: "tool",
        tool_call_id: target.call.id,
        content: JSON.stringify({ status: "cancelled", data: null, error: null })
      });
      state.pending = state.pending.filter((item) => item !== target);
      if (!state.pending.length) {
        state.status = "running";
        await this.#run(state);
      }
      return this.snapshot(turnId);
    }

    state.confirmed.add(operationId);
    const stillWaiting = state.pending.filter(
      (item) => item.tool.requiresConfirmation && !state.confirmed.has(item.operationId)
    );
    if (stillWaiting.length) return this.snapshot(turnId);

    const batch = state.pending;
    state.pending = [];
    state.status = "running";
    if (!(await this.#takeBatch(state))) return this.snapshot(turnId);
    await this.#execute(state, batch);
    await this.#run(state);
    return this.snapshot(turnId);
  }

  async submitToolResults(turnId, results) {
    const state = this.#turn(turnId);
    if (state.status !== "awaiting_tool_results") {
      throw new AgentError(`任务当前状态为 ${state.status}，不等待工具结果`, "invalid_state");
    }
    const pendingByCall = new Map(state.pending.map((item) => [item.call.id, item]));
    for (const result of results ?? []) {
      const pending = pendingByCall.get(result.toolCallId);
      if (!pending) throw new AgentError(`未知 toolCallId ${result.toolCallId}`, "unknown_tool_call");
      const normalized = {
        status: result.status,
        data: result.data ?? null,
        error: result.error ?? null,
        deduplicated: Boolean(result.deduplicated)
      };
      await this.operationLog.begin({
        operationId: pending.operationId,
        turnId,
        tool: pending.tool.name,
        arguments: pending.args
      });
      await this.operationLog.complete(pending.operationId, normalized);
      this.#emit(state, "tool.result", {
        tool: pending.tool.name,
        toolCallId: result.toolCallId,
        operationId: pending.operationId,
        status: normalized.status,
        data: normalized.data,
        deduplicated: normalized.deduplicated
      });
      state.messages.push({
        role: "tool",
        tool_call_id: result.toolCallId,
        content: JSON.stringify(normalized)
      });
      pendingByCall.delete(result.toolCallId);
    }
    if (pendingByCall.size) {
      throw new AgentError(`仍有 ${pendingByCall.size} 个工具结果未回传`, "missing_tool_results");
    }
    state.pending = [];
    state.status = "running";
    await this.#run(state);
    return this.snapshot(turnId);
  }

  snapshot(turnId) {
    const state = this.#turn(turnId);
    return {
      contractVersion: this.contractVersion,
      turnId,
      status: state.status,
      reply: state.reply,
      events: state.events.map((event) => ({ ...event })),
      pending: state.pending.map((item) => ({
        tool: item.tool.name,
        toolCallId: item.call.id,
        operationId: item.operationId,
        arguments: item.args,
        requiresConfirmation: item.tool.requiresConfirmation
      }))
    };
  }

  async #run(state) {
    while (!COMPLETED.has(state.status)) {
      if (state.modelCalls >= this.caps.maxModelCalls) {
        this.#limit(state, "model_calls");
        return;
      }
      state.modelCalls += 1;

      let response;
      try {
        response = await this.adapter.chat({
          messages: state.messages,
          tools: this.registry.listForModel(),
          context: { now: state.now, timezone: state.timezone }
        });
      } catch (error) {
        this.#fail(state, error);
        return;
      }

      if (response.content) {
        state.reply += response.content;
        this.#emit(state, "assistant.delta", { text: response.content });
      }

      const calls = response.toolCalls ?? [];
      if (!calls.length) {
        state.messages.push({ role: "assistant", content: response.content ?? "" });
        state.status = "completed";
        this.#emit(state, "turn.completed", { status: "completed" });
        return;
      }

      state.messages.push({
        role: "assistant",
        content: response.content ?? "",
        tool_calls: calls.map((call) => ({
          id: call.id,
          type: "function",
          function: { name: call.name, arguments: call.arguments }
        }))
      });

      const prepared = [];
      for (const call of calls) {
        const tool = this.registry.get(call.name);
        if (!tool) {
          this.#reject(state, call, "unsupported", "unknown_tool", `未注册工具 ${call.name}`);
          continue;
        }
        let args;
        try {
          args = typeof call.arguments === "string" ? JSON.parse(call.arguments) : call.arguments;
        } catch {
          this.#reject(state, call, "failed", "invalid_arguments_json", "工具参数不是合法 JSON");
          continue;
        }
        const validation = this.registry.validateArguments(call.name, args);
        if (!validation.ok) {
          this.#reject(state, call, "failed", "invalid_arguments", validation.errors.join("; "));
          continue;
        }
        const operationId = `op_${state.turnId}_${call.id}`;
        const item = { call, tool, args, operationId };
        prepared.push(item);
        this.#emit(state, "tool.requested", {
          tool: tool.name,
          toolCallId: call.id,
          operationId,
          arguments: args,
          requiresConfirmation: tool.requiresConfirmation,
          requiresAuthorization: tool.requiresAuthorization
        });
      }

      if (!prepared.length) continue;

      if (state.deferExecution) {
        state.pending = prepared;
        state.status = "awaiting_tool_results";
        return;
      }

      const needConfirm = prepared.filter(
        (item) => item.tool.requiresConfirmation && !state.confirmed.has(item.operationId) && !state.autoConfirm
      );
      if (needConfirm.length) {
        state.pending = prepared;
        state.status = "awaiting_confirmation";
        for (const item of needConfirm) {
          this.#emit(state, "tool.confirmation_required", {
            tool: item.tool.name,
            toolCallId: item.call.id,
            operationId: item.operationId,
            arguments: item.args
          });
        }
        return;
      }

      if (!(await this.#takeBatch(state))) return;
      await this.#execute(state, prepared);
    }
  }

  async #takeBatch(state) {
    if (state.batches >= this.caps.maxToolBatches) {
      this.#limit(state, "tool_batches");
      return false;
    }
    state.batches += 1;
    return true;
  }

  async #execute(state, batch) {
    for (const item of batch) {
      const previous = this.operationLog.get(item.operationId);
      let result;

      if (previous?.status === "success" && previous.result) {
        result = { ...previous.result, deduplicated: true };
      } else if (previous?.status === "started") {
        result = {
          status: "execution_unknown",
          data: null,
          error: { code: "execution_unknown", message: "存在未完成的操作记录，需先核对系统状态" },
          deduplicated: false
        };
      } else {
        await this.operationLog.begin({
          operationId: item.operationId,
          turnId: state.turnId,
          tool: item.tool.name,
          arguments: item.args
        });
        try {
          result = await this.executor.execute({
            tool: item.tool.name,
            arguments: item.args,
            operationId: item.operationId,
            turnId: state.turnId
          });
        } catch (error) {
          result = {
            status: "failed",
            data: null,
            error: { code: "executor_error", message: error.message },
            deduplicated: false
          };
        }
        await this.operationLog.complete(item.operationId, result);
      }

      this.#emit(state, "tool.result", {
        tool: item.tool.name,
        toolCallId: item.call.id,
        operationId: item.operationId,
        status: result.status,
        data: result.data ?? null,
        error: result.error ?? null,
        deduplicated: result.deduplicated
      });
      state.messages.push({
        role: "tool",
        tool_call_id: item.call.id,
        content: JSON.stringify({
          status: result.status,
          data: result.data ?? null,
          error: result.error ?? null
        })
      });
    }
  }

  #reject(state, call, status, code, message) {
    this.#emit(state, "tool.rejected", {
      tool: call.name,
      toolCallId: call.id,
      status,
      error: { code, message }
    });
    state.messages.push({
      role: "tool",
      tool_call_id: call.id,
      content: JSON.stringify({ status, data: null, error: { code, message } })
    });
  }

  #limit(state, reason) {
    state.status = "completed_with_limits";
    const pendingTools = [...new Set(state.pending.map((item) => item.tool.name))];
    const message =
      reason === "model_calls"
        ? `已达到本轮 ${this.caps.maxModelCalls} 次模型调用上限，任务尚未完成。`
        : `已达到本轮 ${this.caps.maxToolBatches} 批工具执行上限，任务尚未完成。`;
    this.#emit(state, "turn.limit_reached", { reason, message, pendingTools });
  }

  #fail(state, error) {
    state.status = "failed";
    this.#emit(state, "turn.failed", {
      code: error.code ?? "internal_error",
      message: error.message
    });
  }

  #emit(state, type, payload) {
    state.seq += 1;
    const event = {
      contractVersion: this.contractVersion,
      eventId: `evt_${randomUUID()}`,
      turnId: state.turnId,
      seq: state.seq,
      type,
      at: new Date().toISOString(),
      payload
    };
    state.events.push(event);
    if (state.onEvent) {
      try {
        state.onEvent(event);
      } catch {
        // 客户端断流不应中断服务端任务。
      }
    }
  }

  #turn(turnId) {
    const state = this.turns.get(turnId);
    if (!state) throw new AgentError(`未知 turnId ${turnId}`, "unknown_turn");
    return state;
  }
}

export class AgentError extends Error {
  constructor(message, code) {
    super(message);
    this.name = "AgentError";
    this.code = code;
  }
}

function isValidTimeZone(timeZone) {
  if (typeof timeZone !== "string" || !timeZone) return false;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone });
    return true;
  } catch {
    return false;
  }
}
