import { randomUUID } from "node:crypto";
import {
  allowedToolNames,
  buildCapabilityManifest,
  implementedToolNames,
  isDeviceTool
} from "./capabilities.mjs";
import { ConversationStore } from "./conversation.mjs";
import { buildSystemPrompt } from "./prompt.mjs";
import {
  buildTaskPlan,
  describeTaskGaps,
  finalizeTask,
  publicTask,
  updateTaskFromToolResult
} from "./taskPlan.mjs";
import { parseReminderIntent, zonedParts } from "./time.mjs";
import { isDiscussionRequest } from "./requestIntent.mjs";

const COMPLETED = new Set(["completed", "completed_with_limits", "failed", "superseded", "cancelled"]);

const SINGLE_ACTION_TOOLS = new Set([
  "create_reminder",
  "create_calendar_event",
  "open_navigation",
  "prepare_message",
  "play_music",
  "pause_music",
  "resume_music",
  "skip_music_track"
]);

const CANCEL_TASK_TOOL = {
  type: "function",
  function: {
    name: "cancel_active_task",
    description:
      "取消当前对话中尚未执行的待补或待确认任务。只取消未执行任务，不删除已保存的记录；有多个任务且指代不明时先询问。",
    parameters: {
      type: "object",
      additionalProperties: false,
      properties: {
        taskId: { type: "string", minLength: 1, maxLength: 120 },
        kind: { type: "string", enum: ["create_reminder", "create_calendar_event"] }
      }
    }
  }
};

export class Agent {
  constructor({
    adapter,
    registry,
    executor,
    serverExecutor = null,
    operationLog,
    caps,
    contractVersion = "1.0",
    conversations = new ConversationStore(),
    systemPrompt = "",
    modelMode = "mock",
    executionMode = "mock",
    turnStore = null
  }) {
    this.adapter = adapter;
    this.registry = registry;
    this.executor = executor;
    this.serverExecutor = serverExecutor;
    this.operationLog = operationLog;
    this.caps = caps;
    this.contractVersion = contractVersion;
    this.conversations = conversations;
    this.systemPrompt = systemPrompt;
    this.modelMode = modelMode;
    this.executionMode = executionMode;
    this.turnStore = turnStore;
    this.turns = new Map();
  }

  async start(
    {
      text,
      now,
      timezone,
      autoConfirm = false,
      deferExecution = false,
      conversationId,
      permissions = {},
      sharedContent = null,
      ownerId = "owner_local"
    },
    { onEvent } = {}
  ) {
    if (typeof text !== "string" || !text.trim()) throw new AgentError("text 不能为空", "invalid_input");
    if (!isValidTimeZone(timezone)) throw new AgentError(`无效时区 ${timezone}`, "invalid_input");
    const nowIso = now ?? new Date().toISOString();
    if (Number.isNaN(Date.parse(nowIso))) throw new AgentError("now 必须是 ISO 8601 时间", "invalid_input");

    const { conversation } = this.conversations.ensure(conversationId, ownerId);
    if (this.executionMode !== "mock" && !deferExecution) {
      throw new AgentError(
        "真实设备执行模式必须由 App 设置 deferExecution=true，避免后端伪造系统写入",
        "device_mode_requires_defer"
      );
    }
    const capabilities = buildCapabilityManifest({
      registry: this.registry,
      implemented: implementedToolNames({
        executionMode: this.executionMode,
        registry: this.registry,
        executor: this.executor
      }),
      permissions,
      executionMode: this.executionMode,
      locationFor: (name) => (this.executionMode === "mock" ? "backend-mock" : isDeviceTool(name) ? "phone" : "backend")
    });

    const turnId = `turn_${randomUUID()}`;
    const systemContent = buildSystemPrompt({
      baseline: this.systemPrompt,
      capabilities,
      conversation,
      now: nowIso,
      timezone,
      executionMode: this.executionMode,
      sharedContent
    });
    const history = this.conversations.transcript(conversation.id, { limit: 10 });

    const state = {
      turnId,
      conversationId: conversation.id,
      ownerId,
      text: text.trim(),
      now: nowIso,
      timezone,
      permissions,
      capabilities,
      allowedTools: isDiscussionRequest(text) ? [] : allowedToolNames(capabilities),
      status: "running",
      messages: [
        { role: "system", content: systemContent },
        ...history,
        { role: "user", content: text.trim() }
      ],
      modelCalls: 0,
      batches: 0,
      actionNudges: 0,
      pending: [],
      confirmed: new Set(),
      successfulActions: new Map(),
      autoConfirm,
      deferExecution,
      reply: "",
      task: buildTaskPlan(text),
      taskNoticeFor: "",
      seq: 0,
      events: [],
      onEvent,
      persisted: false
    };
    this.turns.set(turnId, state);
    this.conversations.append(conversation.id, [{ role: "user", content: text.trim() }]);

    this.#emit(state, "turn.started", {
      input: state.text,
      timezone,
      now: nowIso,
      conversationId: state.conversationId,
      modelMode: this.modelMode,
      executionMode: this.executionMode
    });
    await this.#run(state).catch((error) => this.#fail(state, error));
    return this.snapshot(turnId);
  }

  async confirm(turnId, operationId, confirmed, ownerId) {
    const state = this.#turn(turnId, ownerId);
    if (state.status !== "awaiting_confirmation") {
      throw new AgentError(`任务当前状态为 ${state.status}，不能确认`, "invalid_state");
    }
    const target = state.pending.find((item) => item.operationId === operationId);
    if (!target) throw new AgentError("operationId 不属于当前待确认操作", "unknown_operation");
    const task = this.conversations
      .tasks(state.conversationId)
      .find((item) => item.operationId === operationId);
    if (task?.state === "superseded") {
      throw new AgentError("该操作已被新的修改取代，需要确认新的预览", "operation_superseded");
    }

    if (!confirmed) {
      await this.operationLog.begin({
        operationId,
        turnId,
        tool: target.tool.name,
        arguments: target.args
      });
      const result = { status: "cancelled", data: null, error: null, deduplicated: false };
      await this.operationLog.complete(operationId, result);
      this.#emit(state, "tool.result", {
        tool: target.tool.name,
        toolCallId: target.call.id,
        operationId,
        status: "cancelled",
        data: null,
        deduplicated: false
      });
      this.conversations.closeTask(state.conversationId, `task_${operationId}`, "cancelled");
      state.messages.push({
        role: "tool",
        tool_call_id: target.call.id,
        content: JSON.stringify({ status: "cancelled", data: null, error: null })
      });
      state.pending = state.pending.filter((item) => item !== target);
      if (!state.pending.length) {
        state.status = "completed";
        state.reply = "已取消本次操作，没有写入系统。";
        this.#emit(state, "assistant.delta", { text: state.reply });
        this.#persist(state);
        this.#emit(state, "turn.completed", { status: "completed" });
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

  async submitToolResults(turnId, results, ownerId) {
    const state = this.#turn(turnId, ownerId);
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
      this.#recordEntities(state, pending.tool.name, normalized);
      this.conversations.closeTask(
        state.conversationId,
        `task_${pending.operationId}`,
        normalized.status === "success" ? "completed" : "failed"
      );
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

  snapshot(turnId, ownerId) {
    const state = this.turns.get(turnId);
    if (state) {
      this.#assertOwner(state, ownerId);
      return this.#snapshotFromState(state);
    }
    const archived = this.turnStore?.get(turnId);
    if (archived) {
      this.#assertArchivedOwner(archived, ownerId);
      return archived;
    }
    throw new AgentError(`未知 turnId ${turnId}`, "unknown_turn");
  }

  #snapshotFromState(state) {
    return {
      contractVersion: this.contractVersion,
      turnId: state.turnId,
      conversationId: state.conversationId,
      ownerId: state.ownerId,
      status: state.status,
      reply: state.reply,
      modelMode: this.modelMode,
      executionMode: this.executionMode,
      events: state.events.map((event) => ({ ...event })),
      pending: state.pending.map((item) => ({
        tool: item.tool.name,
        toolCallId: item.call.id,
        operationId: item.operationId,
        arguments: item.args,
        requiresConfirmation: item.tool.requiresConfirmation
      })),
      task: publicTask(state.task),
      updatedAt: new Date().toISOString()
    };
  }

  capabilities() {
    return buildCapabilityManifest({
      registry: this.registry,
      implemented: implementedToolNames({
        executionMode: this.executionMode,
        registry: this.registry,
        executor: this.executor
      }),
      permissions: {},
      executionMode: this.executionMode,
      locationFor: (name) => (this.executionMode === "mock" ? "backend-mock" : isDeviceTool(name) ? "phone" : "backend")
    });
  }

  async #run(state) {
    while (!COMPLETED.has(state.status)) {
      if (state.modelCalls >= this.caps.maxModelCalls) {
        this.#limit(state, "model_calls");
        return;
      }
      state.modelCalls += 1;

      let response;
      let streamed = false;
      try {
        const tools = this.registry.listForModel({ allowed: state.allowedTools });
        if (this.#hasActiveTasks(state)) tools.push(CANCEL_TASK_TOOL);
        response = await this.adapter.chat({
          messages: state.messages,
          tools,
          context: { now: state.now, timezone: state.timezone, conversationId: state.conversationId },
          onDelta: (text) => {
            if (!text) return;
            streamed = true;
            state.reply += text;
            this.#emit(state, "assistant.delta", { text });
          }
        });
      } catch (error) {
        this.#fail(state, error);
        return;
      }

      const calls = response.toolCalls ?? [];
      if (!calls.length && this.#needsActionNudge(state, response.content)) {
        state.actionNudges += 1;
        state.messages.push({ role: "assistant", content: response.content ?? "" });
        state.messages.push({
          role: "system",
          content:
            "用户明确要求执行设备动作。必须调用对应工具并以 tool.result 为准，不能只输出文字声称已经完成。请现在调用工具。"
        });
        continue;
      }

      if (response.content && !streamed) {
        state.reply += response.content;
        this.#emit(state, "assistant.delta", { text: response.content });
      }

      if (!calls.length) {
        state.messages.push({ role: "assistant", content: response.content ?? "" });
        this.#finish(state);
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
        if (call.name === "cancel_active_task") {
          let args = {};
          try {
            args = typeof call.arguments === "string" ? JSON.parse(call.arguments) : call.arguments ?? {};
          } catch {
            this.#reject(state, call, "failed", "invalid_arguments_json", "工具参数不是合法 JSON");
            continue;
          }
          this.#emit(state, "tool.requested", {
            tool: "cancel_active_task",
            toolCallId: call.id,
            arguments: args,
            requiresConfirmation: false
          });
          const result = this.#cancelActiveTask(state, args);
          this.#emit(state, "tool.result", {
            tool: "cancel_active_task",
            toolCallId: call.id,
            status: result.status,
            data: result.data,
            error: result.error,
            deduplicated: false
          });
          state.messages.push({
            role: "tool",
            tool_call_id: call.id,
            content: JSON.stringify(result)
          });
          continue;
        }
        const tool = this.registry.get(call.name);
        if (!tool) {
          this.#reject(state, call, "unsupported", "unknown_tool", `未注册工具 ${call.name}`);
          continue;
        }
        if (!state.allowedTools.includes(call.name)) {
          const capability = state.capabilities.find((item) => item.name === call.name);
          if (capability?.availability === "needs_authorization") {
            this.#reject(
              state,
              call,
              "needs_authorization",
              "permission_required",
              `${call.name} 需要先授权后才能使用：${capability.reason}`
            );
          } else {
            this.#reject(state, call, "unsupported", "tool_not_available", `${call.name} 当前不可用或未实现`);
          }
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
        const signature = toolSignature(call.name, args);
        if (SINGLE_ACTION_TOOLS.has(call.name) && state.successfulActions.has(signature)) {
          const previous = state.successfulActions.get(signature);
          state.messages.push({
            role: "tool",
            tool_call_id: call.id,
            content: JSON.stringify({
              status: previous.status,
              data: previous.data ?? null,
              error: null,
              deduplicated: true,
              note: "同一轮相同动作已成功执行，本次重复调用已忽略；不要报告失败，也不要再次执行。"
            })
          });
          continue;
        }
        if (call.name === "create_reminder") {
          const intent = parseReminderIntent(state.text, state.now, state.timezone);
          const hasClock = /(\d{1,2}[:：]\d{2})|((\d{1,2}|[零一二两三四五六七八九十]{1,3})\s*[点时])/.test(
            state.text
          );
          const activeReminder = this.conversations
            .tasks(state.conversationId)
            .filter(
              (task) =>
                task.kind === "create_reminder" && ["waiting_user", "waiting_confirmation"].includes(task.state)
            )
            .at(-1);
          const activeDueAt = activeReminder?.knownArguments?.dueAt;
          const sameTime = /同一时间|原时间|时间不变|其他不变|照旧/.test(state.text);
          const activeHour =
            activeDueAt && !Number.isNaN(Date.parse(activeDueAt))
              ? zonedParts(new Date(activeDueAt), state.timezone).hour
              : null;
          const inheritPeriod = activeHour !== null && intent.parsedHour >= 1 && intent.parsedHour <= 11;
          const missingPeriod = intent.needsPeriod && !inheritPeriod;
          const missingTime = intent.needsTime && !hasClock && !sameTime;
          if (missingPeriod || missingTime) {
            const taskId = activeReminder?.taskId ?? `task_${state.turnId}`;
            this.conversations.upsertTask(state.conversationId, {
              taskId,
              kind: "create_reminder",
              state: "waiting_user",
              operationId: activeReminder?.operationId ?? `op_${state.turnId}_partial`,
              turnId: state.turnId,
              knownArguments: {
                ...(activeReminder?.knownArguments ?? {}),
                title: activeReminder?.knownArguments?.title ?? intent.title,
                timezone: state.timezone,
                ...((intent.date ?? activeReminder?.knownArguments?.date)
                  ? { date: intent.date ?? activeReminder?.knownArguments?.date }
                  : {})
              },
              missingFields: missingPeriod ? ["period"] : ["time"]
            });
            this.#reject(
              state,
              call,
              "needs_input",
              missingPeriod ? "missing_period" : "missing_time",
              missingPeriod
                ? "时间缺少上午或下午，先向用户确认，不要自行补成下午"
                : "只有日期没有具体时刻，先向用户追问时间，不要自行补造默认时间"
            );
            continue;
          }
        }
        if (call.name === "search_places" && state.task?.constraints?.homeNavigation) {
          const query = String(args.query ?? "").trim();
          const addressGiven = /(?:省|市|区|县|镇|乡|街|路|道|号|巷|弄|村|小区|大厦|楼)/.test(state.text);
          if (/^(?:我?家|回家|家庭)$/.test(query) && !addressGiven) {
            this.#reject(
              state,
              call,
              "needs_input",
              "missing_home_address",
              "用户没有提供详细家庭地址，先追问；不要把“家”当成地图关键词搜索"
            );
            continue;
          }
        }
        const operationId = `op_${state.turnId}_${call.id}`;
        prepared.push({ call, tool, args, operationId });
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
        if (this.executionMode === "mock") {
          state.pending = prepared;
          state.status = "awaiting_tool_results";
          this.#trackPendingTasks(state, "waiting_tool_results");
          return;
        }

        const deferred = prepared.filter((item) => isDeviceTool(item.tool.name));
        const serverSide = prepared.filter((item) => !isDeviceTool(item.tool.name));
        if (serverSide.length) {
          if (!(await this.#takeBatch(state))) return;
          await this.#execute(state, serverSide);
        }
        if (deferred.length) {
          state.pending = deferred;
          state.status = "awaiting_tool_results";
          this.#trackPendingTasks(state, "waiting_tool_results");
          return;
        }
        continue;
      }

      const needConfirm = prepared.filter(
        (item) => item.tool.requiresConfirmation && !state.confirmed.has(item.operationId) && !state.autoConfirm
      );
      if (needConfirm.length) {
        state.pending = prepared;
        state.status = "awaiting_confirmation";
        this.#trackPendingTasks(state, "waiting_confirmation");
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

  #needsActionNudge(state, content = "") {
    if (isDiscussionRequest(state.text)) return false;
    if (state.actionNudges >= 1) return false;
    if (state.task) {
      const hasSearch = state.task.observations.some((item) => item.tool === "search_places");
      const hasNavigation = state.task.observations.some((item) => item.tool === "open_navigation");
      if (state.task.constraints.locationMode === "current" && !hasSearch) return true;
      if (state.task.constraints.navigationRequested && !hasNavigation) return true;
    }
    const text = state.text.trim();
    if (!/^(暂停|继续|播放|下一首|上一首|换一首|切歌|停止|带我去|导航|打开地图)/.test(text)) return false;
    return /(已经|已|正在|好的|好了|开始|暂停|播放|切换|打开)/.test(content);
  }

  async #execute(state, batch) {
    for (const item of batch) {
      const previous = this.operationLog.get(item.operationId);
      let result;

      const runsOnServer = this.executionMode !== "mock" && !isDeviceTool(item.tool.name);
      if (runsOnServer && !this.serverExecutor) {
        result = {
          status: "unsupported",
          data: null,
          error: {
            code: "server_side_not_implemented",
            message: `真实执行模式下后端不执行 ${item.tool.name}；该能力应由手机执行，或直接基于本轮真实资料回答`
          },
          deduplicated: false
        };
      } else if (previous?.status === "success" && previous.result) {
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
          const executor = runsOnServer ? this.serverExecutor : this.executor;
          result = await executor.execute({
            tool: item.tool.name,
            arguments: item.args,
            operationId: item.operationId,
            turnId: state.turnId,
            conversationId: state.conversationId,
            permissions: state.permissions
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
      this.#recordEntities(state, item.tool.name, result);
      if (state.task) {
        updateTaskFromToolResult(state.task, item.tool.name, result);
        const notice = describeTaskGaps(state.task);
        if (notice && notice !== state.taskNoticeFor) {
          state.taskNoticeFor = notice;
          state.messages.push({ role: "system", content: notice });
        }
      }
      if (["success", "opened_external_app"].includes(result.status)) {
        state.successfulActions.set(toolSignature(item.tool.name, item.args), {
          status: result.status,
          data: result.data ?? null
        });
      }
      if (item.tool.requiresConfirmation) {
        this.conversations.closeTask(
          state.conversationId,
          `task_${item.operationId}`,
          result.status === "success" ? "completed" : "failed"
        );
      }
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

  #trackPendingTasks(state, taskState) {
    for (const item of state.pending) {
      if (!item.tool.requiresConfirmation && taskState === "waiting_confirmation") continue;
      const previous = this.conversations
        .tasks(state.conversationId)
        .filter(
          (task) =>
            task.state === "waiting_confirmation" &&
            task.kind === item.tool.name &&
            task.operationId !== item.operationId &&
            sameTaskIdentity(task.knownArguments, item.args)
        );
      for (const task of previous) {
        this.conversations.closeTask(state.conversationId, task.taskId, "superseded");
        const oldTurn = this.turns.get(task.turnId);
        if (oldTurn && oldTurn.status === "awaiting_confirmation") {
          oldTurn.pending = oldTurn.pending.filter((pending) => pending.operationId !== task.operationId);
          if (!oldTurn.pending.length) oldTurn.status = "superseded";
          this.#emit(oldTurn, "tool.superseded", {
            tool: task.kind,
            operationId: task.operationId,
            replacedBy: item.operationId
          });
        }
      }
      this.conversations.upsertTask(state.conversationId, {
        taskId: `task_${item.operationId}`,
        kind: item.tool.name,
        state: taskState,
        operationId: item.operationId,
        turnId: state.turnId,
        knownArguments: item.args,
        missingFields: []
      });
    }
  }

  #hasActiveTasks(state) {
    return this.#activeTasks(state).length > 0;
  }

  #activeTasks(state) {
    return this.conversations
      .tasks(state.conversationId)
      .filter((task) => ["waiting_confirmation", "waiting_tool_results", "waiting_user"].includes(task.state));
  }

  #cancelActiveTask(state, args = {}) {
    const tasks = this.#activeTasks(state);
    if (!tasks.length) {
      return {
        status: "failed",
        data: null,
        error: { code: "no_active_task", message: "当前没有可取消的未执行任务" },
        deduplicated: false
      };
    }

    let target = null;
    if (args.taskId) {
      target = tasks.find((task) => task.taskId === args.taskId) ?? null;
    } else if (args.kind) {
      const matches = tasks.filter((task) => task.kind === args.kind);
      if (matches.length === 1) target = matches[0];
      else if (matches.length > 1) return this.#ambiguousTask(tasks);
    } else if (tasks.length === 1) {
      target = tasks[0];
    } else {
      return this.#ambiguousTask(tasks);
    }

    if (!target) {
      return {
        status: "failed",
        data: { candidates: tasks.map((task) => ({ taskId: task.taskId, kind: task.kind })) },
        error: { code: "unknown_task", message: "没有找到指定的未执行任务" },
        deduplicated: false
      };
    }

    this.conversations.closeTask(state.conversationId, target.taskId, "cancelled");
    const oldTurn = this.turns.get(target.turnId);
    if (oldTurn) {
      oldTurn.pending = oldTurn.pending.filter((item) => item.operationId !== target.operationId);
      if (
        !oldTurn.pending.length &&
        ["awaiting_confirmation", "awaiting_tool_results"].includes(oldTurn.status)
      ) {
        oldTurn.status = "cancelled";
      }
      this.#emit(oldTurn, "tool.superseded", {
        tool: target.kind,
        operationId: target.operationId,
        reason: "user_cancelled"
      });
    }
    return {
      status: "success",
      data: { taskId: target.taskId, kind: target.kind, state: "cancelled" },
      error: null,
      deduplicated: false
    };
  }

  #ambiguousTask(tasks) {
    return {
      status: "failed",
      data: { candidates: tasks.map((task) => ({ taskId: task.taskId, kind: task.kind })) },
      error: { code: "ambiguous_task", message: "有多个未执行任务，需要说明取消哪一个" },
      deduplicated: false
    };
  }

  #recordEntities(state, toolName, result) {
    if (result.status !== "success" || !result.data) return;
    const data = result.data;
    if (toolName === "search_music_library") {
      this.conversations.setEntities(state.conversationId, { musicCandidates: data.tracks ?? [] });
    } else if (
      ["play_music", "pause_music", "resume_music", "skip_music_track", "get_playback_state"].includes(toolName)
    ) {
      this.conversations.setEntities(state.conversationId, { playback: data });
    } else if (toolName === "search_places") {
      this.conversations.setEntities(state.conversationId, { lastPlaces: data.places ?? [] });
    } else if (toolName === "list_calendar_events") {
      this.conversations.setEntities(state.conversationId, { lastCalendarEvents: data.events ?? [] });
    } else if (toolName === "get_weather") {
      this.conversations.setEntities(state.conversationId, { lastWeather: data });
    }
  }

  #finish(state) {
    const task = finalizeTask(state.task, "completed");
    const status = task?.remaining?.length ? "completed_with_limits" : "completed";
    state.status = status;
    this.#persist(state);
    this.#emit(state, "turn.completed", { status, task: publicTask(task) });
  }

  #persist(state) {
    if (state.persisted) return;
    state.persisted = true;
    if (state.reply.trim()) {
      this.conversations.append(state.conversationId, [{ role: "assistant", content: state.reply.trim() }]);
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
    if (state.task) {
      state.task.state = "completed_with_limits";
      const label = reason === "model_calls" ? "模型调用次数达到上限" : "工具执行批次达到上限";
      if (!state.task.remaining.includes(label)) state.task.remaining.push(label);
    }
    const pendingTools = [...new Set(state.pending.map((item) => item.tool.name))];
    const message =
      reason === "model_calls"
        ? `已达到本轮 ${this.caps.maxModelCalls} 次模型调用上限，任务尚未完成。`
        : `已达到本轮 ${this.caps.maxToolBatches} 批工具执行上限，任务尚未完成。`;
    this.#emit(state, "turn.limit_reached", { reason, message, pendingTools });
    this.#persist(state);
  }

  #fail(state, error) {
    state.status = "failed";
    if (state.task) state.task.state = "failed";
    const retryable = !["missing_api_key", "invalid_input"].includes(error.code);
    this.#emit(state, "turn.failed", {
      code: error.code ?? "internal_error",
      message: error.message,
      retryable
    });
    this.#persist(state);
  }

  #emit(state, type, payload) {
    state.seq += 1;
    const event = {
      contractVersion: this.contractVersion,
      eventId: `evt_${randomUUID()}`,
      turnId: state.turnId,
      conversationId: state.conversationId,
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
    if (this.turnStore) {
      const record = this.#snapshotFromState(state);
      if (["turn.completed", "turn.failed", "turn.limit_reached"].includes(type)) {
        this.turnStore.flush(record);
      } else {
        this.turnStore.schedule(record);
      }
    }
  }

  #turn(turnId, ownerId) {
    const state = this.turns.get(turnId);
    if (!state) throw new AgentError(`未知 turnId ${turnId}`, "unknown_turn");
    this.#assertOwner(state, ownerId);
    return state;
  }

  #assertOwner(state, ownerId) {
    if (!ownerId) return;
    if ((state.ownerId ?? "owner_local") !== ownerId) {
      throw new AgentError("无权访问该任务", "forbidden_turn");
    }
  }

  #assertArchivedOwner(record, ownerId) {
    if (!ownerId) return;
    if ((record.ownerId ?? "owner_anonymous") !== ownerId) {
      throw new AgentError("无权访问该任务", "forbidden_turn");
    }
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

const TIME_FIELDS = new Set(["dueAt", "startAt", "endAt", "timezone"]);

function sameTaskIdentity(left = {}, right = {}) {
  const normalize = (args) =>
    JSON.stringify(
      Object.keys(args)
        .filter((key) => !TIME_FIELDS.has(key))
        .sort()
        .map((key) => [key, args[key]])
    );
  return normalize(left) === normalize(right);
}

function toolSignature(name, args = {}) {
  return `${name}:${stableStringify(args)}`;
}

function stableStringify(value) {
  if (Array.isArray(value)) return `[${value.map((item) => stableStringify(item)).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${stableStringify(value[key])}`)
      .join(",")}}`;
  }
  return JSON.stringify(value ?? null);
}
