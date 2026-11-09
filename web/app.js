const FIXED_NOW = "2026-11-09T10:00:00+08:00";
const BOOT = Date.now();
const STORAGE_SCENARIO = "whale01.scenario.v1";
const STORAGE_REMINDERS = "whale01.reminders.v1";

const DEFAULTS = {
  clock: "fixed",
  timezone: "Asia/Shanghai",
  permission: "granted",
  network: "online",
  health: "none",
  autoConfirm: false
};

const state = {
  scenario: loadJson(STORAGE_SCENARIO, DEFAULTS),
  reminders: loadJson(STORAGE_REMINDERS, []),
  operations: new Map(),
  seqByTurn: new Map(),
  turnCounter: 0,
  opCounter: 0,
  lastWriteOp: null,
  selectedPlace: null,
  busy: false,
  listening: false
};

const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
const chat = $("#chat");
const input = $("#input");
const eventLog = $("#eventLog");
const statebar = $(".statebar");
const stateLabel = $("#stateLabel");
const stateMeta = $("#stateMeta");

init();

function init() {
  renderWelcome();
  syncScenario();
  bindComposer();
  bindChatActions();
  bindScenarioSheet();
  bindSidePanel();
  updateClock();
  setInterval(updateClock, 15000);
  if (state.reminders.length) {
    setTimeout(() => toast(`本地已有 ${state.reminders.length} 条模拟提醒`), 900);
  }
}

function renderWelcome() {
  const whale = avatarMarkup();
  chat.insertAdjacentHTML(
    "beforeend",
    `<div class="msg assistant">
      <span class="msg-avatar">${whale}</span>
      <div class="bubble">
        <p>我是鲸鱼。当前是 <strong>HTML 模拟环境</strong>，不会写入你的真实提醒、日历或健康数据。</p>
        <p class="hint">试试「明天下午三点提醒我取快递」：我会解析时间、请求确认，再展示写入结果。</p>
      </div>
    </div>`
  );
}

function bindComposer() {
  $("#composerForm").addEventListener("submit", (event) => {
    event.preventDefault();
    const text = input.value.trim();
    if (!text) return;
    input.value = "";
    runTurn(text);
  });

  $("#chips").addEventListener("click", (event) => {
    const button = event.target.closest("button[data-prompt]");
    if (!button) return;
    runTurn(button.dataset.prompt);
  });

  $("#micBtn").addEventListener("click", () => {
    if (state.listening || state.busy) return;
    state.listening = true;
    $("#voiceOverlay").hidden = false;
    setCharacter("listening", "正在听");
    const samples = [
      "明天下午三点提醒我取快递",
      "查明天下午的安排",
      "附近咖啡店，带我去第二家",
      "给张三准备一条短信"
    ];
    const sample = samples[Math.floor(Math.random() * samples.length)];
    setTimeout(() => {
      $("#voiceOverlay").hidden = true;
      state.listening = false;
      input.value = sample;
      setCharacter("idle", "待命");
      runTurn(sample);
    }, 1900);
  });
}

function bindChatActions() {
  chat.addEventListener("click", (event) => {
    const button = event.target.closest("[data-action]");
    if (!button) return;
    const action = button.dataset.action;

    if (action === "confirm-tool") {
      const op = state.operations.get(button.dataset.op);
      if (op) executeOperation(op);
      return;
    }
    if (action === "cancel-tool") {
      const op = state.operations.get(button.dataset.op);
      if (op) cancelOperation(op);
      return;
    }
    if (action === "grant-permission") {
      state.scenario.permission = "granted";
      saveScenario();
      syncScenario();
      toast("已模拟开启提醒权限，请再试一次");
      return;
    }
    if (action === "calendar-create") return startCalendarCreate();
    if (action === "dismiss") {
      assistantSay("好，这次不安排。已有日程没有被修改。");
      setCharacter("idle", "待命");
      return;
    }
    if (action === "health-toggle") {
      state.scenario.health = state.scenario.health === "has" ? "none" : "has";
      saveScenario();
      syncScenario();
      runTurn("今天运动了多少");
      return;
    }
    if (action === "weather-region") return weatherCard(button.dataset.region);
    if (action === "choose-place") return choosePlace(button.dataset.place);
    if (action === "open-nav") return startNavigation();
    if (action === "retry") return runTurn(button.dataset.text || input.value || "明天下午三点提醒我取快递");
  });
}

function bindScenarioSheet() {
  $("#scenarioBtn").addEventListener("click", openSheet);
  $("#closeSheet").addEventListener("click", closeSheet);
  $("#sheetBackdrop").addEventListener("click", closeSheet);

  $$(".segmented").forEach((group) => {
    group.addEventListener("click", (event) => {
      const button = event.target.closest("button[data-value]");
      if (!button) return;
      const field = group.dataset.field;
      state.scenario[field] = button.dataset.value;
      saveScenario();
      syncScenario();
      if (field === "network" && button.dataset.value === "online") flushPendingResults();
    });
  });

  $("#timezoneSelect").addEventListener("change", (event) => {
    state.scenario.timezone = event.target.value;
    saveScenario();
    syncScenario();
  });

  $("#autoConfirmToggle").addEventListener("change", (event) => {
    state.scenario.autoConfirm = event.target.checked;
    saveScenario();
    syncScenario();
  });

  $("#duplicateBtn").addEventListener("click", () => {
    if (!state.lastWriteOp) {
      toast("还没有可重复提交的写操作");
      return;
    }
    executeOperation(state.lastWriteOp, { duplicateTest: true });
  });

  $("#loopBtn").addEventListener("click", simulateLoopLimit);

  $("#resetBtn").addEventListener("click", () => {
    localStorage.removeItem(STORAGE_SCENARIO);
    localStorage.removeItem(STORAGE_REMINDERS);
    location.reload();
  });
}

function bindSidePanel() {
  $("#logBtn").addEventListener("click", () => $("#sidePanel").classList.add("open"));
  $("#sideClose").addEventListener("click", () => $("#sidePanel").classList.remove("open"));
  $("#clearLog").addEventListener("click", () => {
    eventLog.innerHTML = "";
  });
}

async function runTurn(text) {
  if (state.busy) {
    toast("上一条还在处理中");
    return;
  }
  state.busy = true;
  addUserMessage(text);
  const turnId = createTurn(text);

  if (state.scenario.network === "offline") {
    setCharacter("error", "网络不可用");
    const bubble = await say("网络不可用，无法调用模型。你的输入已保留，恢复网络后可以重试。", 380);
    bubble.insertAdjacentHTML(
      "beforeend",
      `<div class="quick-replies"><button data-action="retry" data-text="${escapeAttr(text)}">恢复后重试</button></div>`
    );
    emit(turnId, "turn.failed", { code: "network_offline", message: "网络不可用" });
    state.busy = false;
    return;
  }

  setCharacter("thinking", "正在理解");
  await sleep(420);
  try {
    if (/提醒|待办|记得/.test(text)) await reminderFlow(text, turnId);
    else if (/安排|日程|空闲|日历/.test(text)) await calendarFlow(turnId);
    else if (/运动|步数|走了|消耗/.test(text)) await activityFlow(turnId);
    else if (/天气|气温|下雨|预报/.test(text)) await weatherFlow(text, turnId);
    else if (/咖啡|附近|导航|带我去|地点/.test(text)) await placesFlow(turnId);
    else if (/总结|摘要|文章/.test(text)) await summaryFlow(text, turnId);
    else if (/短信|邮件|草稿|发给/.test(text)) await messageFlow(turnId);
    else await genericFlow(turnId);
  } catch (error) {
    emit(turnId, "turn.failed", { code: "demo_error", message: error.message });
    await say("模拟流程出错，本轮没有执行任何系统操作。");
    setCharacter("error", "出现错误");
  } finally {
    state.busy = false;
  }
}

async function reminderFlow(text, turnId) {
  if (state.scenario.permission !== "granted") {
    const label = state.scenario.permission === "denied" ? "已拒绝" : "已撤回";
    await say(`提醒事项权限当前为「${label}」，无法创建提醒。我不会反复弹授权，请到系统设置开启后重试。`);
    emit(turnId, "tool.result", {
      tool: "create_reminder",
      status: "needs_authorization",
      data: null,
      error: { code: "permission_denied", message: label }
    });
    renderAuthorizationCard("create_reminder", label);
    setCharacter("waiting", "等待授权");
    completeTurn(turnId);
    return;
  }

  const intent = parseReminder(text, nowDate(), state.scenario.timezone);
  if (intent.needsTime) {
    await say("这条提醒要定在几点？请补充具体时间。我不会把未声明的时间默认成确定安排。");
    completeTurn(turnId);
    setCharacter("idle", "待命");
    return;
  }
  if (intent.needsPeriod) {
    await say(`你指的是上午 ${intent.parsedHour} 点还是下午 ${intent.parsedHour} 点？`);
    completeTurn(turnId);
    setCharacter("idle", "待命");
    return;
  }

  const args = { title: intent.title, timezone: state.scenario.timezone };
  if (intent.dueAt) args.dueAt = intent.dueAt;
  const op = makeOperation(turnId, "create_reminder", args);
  emit(turnId, "tool.requested", {
    tool: "create_reminder",
    toolCallId: op.toolCallId,
    operationId: op.id,
    arguments: args,
    requiresConfirmation: true,
    requiresAuthorization: ["eventkit"]
  });

  const when = args.dueAt ? formatDue(args.dueAt) : "无日期待办";
  await say(
    `我理解为：<strong>${escapeHtml(args.title)}</strong> · ${escapeHtml(when)}。` +
      (state.scenario.autoConfirm ? "已开启自动确认，正在写入。" : "请确认后我再写入系统。")
  );
  appendToolCard(op);

  if (state.scenario.autoConfirm) {
    setTimeout(() => executeOperation(op), 480);
  } else {
    emit(turnId, "tool.confirmation_required", {
      tool: "create_reminder",
      toolCallId: op.toolCallId,
      operationId: op.id,
      arguments: args
    });
    setCharacter("waiting", "等待确认");
  }
}

async function calendarFlow(turnId) {
  await say("明天（11月10日）的安排如下，数据为模拟：");
  appendCalendarCard();
  const bubble = await say("15:00–16:00 是空档。需要安排 1 小时健身吗？");
  bubble.insertAdjacentHTML(
    "beforeend",
    `<div class="quick-replies">
      <button data-action="calendar-create">安排 16:00 健身</button>
      <button data-action="dismiss">先不安排</button>
    </div>`
  );
  completeTurn(turnId);
  setCharacter("idle", "待命");
}

async function startCalendarCreate() {
  if (state.busy) return;
  state.busy = true;
  const text = "安排明天 16:00 健身";
  addUserMessage(text);
  const turnId = createTurn(text);
  setCharacter("thinking", "正在准备");
  await sleep(360);

  const { start, end } = tomorrowRange(16, 17);
  const args = {
    title: "健身",
    startAt: start,
    endAt: end,
    timezone: state.scenario.timezone,
    calendarId: "个人"
  };
  const op = makeOperation(turnId, "create_calendar_event", args);
  emit(turnId, "tool.requested", {
    tool: "create_calendar_event",
    toolCallId: op.toolCallId,
    operationId: op.id,
    arguments: args,
    requiresConfirmation: true,
    requiresAuthorization: ["eventkit"]
  });
  await say("将创建日程：<strong>健身</strong> · 11月10日 16:00–17:00。请确认后写入。");
  appendToolCard(op);

  if (state.scenario.autoConfirm) {
    setTimeout(() => executeOperation(op), 480);
  } else {
    emit(turnId, "tool.confirmation_required", {
      tool: "create_calendar_event",
      toolCallId: op.toolCallId,
      operationId: op.id,
      arguments: args
    });
    setCharacter("waiting", "等待确认");
  }
  state.busy = false;
}

async function activityFlow(turnId) {
  if (state.scenario.health !== "has") {
    const bubble = await say(
      "没有取得今天（11月9日 00:00 至现在）的运动数据。可能是设备未记录，也可能是未授予读取权限；不能据此说成 0 步。"
    );
    bubble.insertAdjacentHTML(
      "beforeend",
      `<div class="quick-replies"><button data-action="health-toggle">切换为有数据</button></div>`
    );
    setCharacter("waiting", "数据缺失");
    completeTurn(turnId);
    return;
  }
  await say(
    `今天（11月9日 00:00 至 10:00）的模拟摘要：
     <div class="weather-grid">
       <div><small>步数</small><strong>6,482</strong></div>
       <div><small>锻炼</small><strong>32 分钟</strong></div>
       <div><small>活动能量</small><strong>412 千卡</strong></div>
     </div>
     <p class="hint">统计范围来自模拟 HealthKit，仅包含本次请求的指标。</p>`
  );
  completeTurn(turnId);
  setCharacter("done", "已完成");
}

async function weatherFlow(text, turnId) {
  if (/下周|未来一周|一周后/.test(text)) {
    await say("所选日期超出天气预报供应商的 7 天范围，无法给出可靠预报。我不会生成伪造数据。");
    completeTurn(turnId);
    setCharacter("waiting", "预报不可用");
    return;
  }
  if (/朝阳/.test(text)) {
    const bubble = await say("「朝阳」有多个同名地区，请选择后再查询：");
    bubble.insertAdjacentHTML(
      "beforeend",
      `<div class="quick-replies">
        <button data-action="weather-region" data-region="北京·朝阳">北京·朝阳</button>
        <button data-action="weather-region" data-region="长春·朝阳">长春·朝阳</button>
      </div>`
    );
    completeTurn(turnId);
    setCharacter("waiting", "等待选择");
    return;
  }
  await weatherCard("上海·静安");
  completeTurn(turnId);
  setCharacter("done", "已完成");
}

async function weatherCard(region) {
  await say(
    `${escapeHtml(region)} 明天（11月10日）的模拟预报：
     <div class="weather-grid">
       <div><small>气温</small><strong>18–24°C</strong></div>
       <div><small>天气</small><strong>多云</strong></div>
       <div><small>降水</small><strong>10%</strong></div>
     </div>
     <p class="hint">来源：模拟天气服务 · 更新时间 10:00</p>`
  );
}

async function placesFlow(turnId) {
  await say("找到 3 个候选地点（模拟数据）。请选择一家：");
  appendPlacesCard();
  completeTurn(turnId);
  setCharacter("waiting", "等待选择");
}

async function choosePlace(placeId) {
  const places = placeCatalog();
  const place = places.find((item) => item.id === placeId);
  if (!place) return;
  state.selectedPlace = place;
  addUserMessage(`选第 ${place.rank} 家`);
  const turnId = createTurn(`选择地点 ${place.name}`);
  setCharacter("thinking", "正在确认");
  await sleep(300);
  const bubble = await say(`已选择：<strong>${escapeHtml(place.name)}</strong> · ${escapeHtml(place.note)}。`);
  bubble.insertAdjacentHTML(
    "beforeend",
    `<div class="quick-replies">
      <button data-action="open-nav" data-place="${place.id}">带我去（驾车）</button>
    </div>`
  );
  completeTurn(turnId);
  setCharacter("waiting", "等待确认");
}

async function startNavigation() {
  if (!state.selectedPlace) {
    toast("请先选择地点");
    return;
  }
  if (state.busy) return;
  state.busy = true;
  const text = `导航到 ${state.selectedPlace.name}`;
  addUserMessage(text);
  const turnId = createTurn(text);
  const args = { placeId: state.selectedPlace.id, mode: "driving" };
  const op = makeOperation(turnId, "open_navigation", args);
  emit(turnId, "tool.requested", {
    tool: "open_navigation",
    toolCallId: op.toolCallId,
    operationId: op.id,
    arguments: args,
    requiresConfirmation: true,
    requiresAuthorization: []
  });
  await say("将把已选地点交给地图 App。只会反馈「已打开」，不能声称已出发或抵达。");
  appendToolCard(op);
  if (state.scenario.autoConfirm) setTimeout(() => executeOperation(op), 480);
  else {
    emit(turnId, "tool.confirmation_required", {
      tool: "open_navigation",
      toolCallId: op.toolCallId,
      operationId: op.id,
      arguments: args
    });
    setCharacter("waiting", "等待确认");
  }
  state.busy = false;
}

async function summaryFlow(text, turnId) {
  if (/https?:\/\//.test(text)) {
    await say("我只拿到了链接，还没有取得正文，不能假装读过全文。请把正文分享给我，再做总结。");
    completeTurn(turnId);
    setCharacter("waiting", "缺少正文");
    return;
  }
  await say(
    `基于本次分享正文（模拟，约 1,280 字），总结为三点：
     <ol class="summary-points">
       <li>统一工具契约是本期最关键的工程前置。</li>
       <li>提醒闭环应优先验证权限、确认与幂等。</li>
       <li>语音链路只播报执行确认后的最终文本。</li>
     </ol>
     <p class="hint">分享内容中的指令不会改变工具权限。</p>`
  );
  completeTurn(turnId);
  setCharacter("done", "已完成");
}

async function messageFlow(turnId) {
  await say("给张三准备短信草稿。收件人来自本地联系人候选（模拟），不会上传整个通讯录。");
  const args = {
    channel: "sms",
    recipientId: "contact_zhangsan",
    body: "明天下午三点见，地点我稍后发你。"
  };
  const op = makeOperation(turnId, "prepare_message", args);
  emit(turnId, "tool.requested", {
    tool: "prepare_message",
    toolCallId: op.toolCallId,
    operationId: op.id,
    arguments: args,
    requiresConfirmation: true,
    requiresAuthorization: ["contacts", "messages"]
  });
  appendToolCard(op);
  if (state.scenario.autoConfirm) setTimeout(() => executeOperation(op), 480);
  else {
    emit(turnId, "tool.confirmation_required", {
      tool: "prepare_message",
      toolCallId: op.toolCallId,
      operationId: op.id,
      arguments: args
    });
    setCharacter("waiting", "等待确认");
  }
}

async function genericFlow(turnId) {
  const bubble = await say(
    "这个请求暂未接入模拟。当前可演示：提醒创建、日历查询与创建、天气、运动摘要、地点导航、内容总结、短信草稿。"
  );
  bubble.insertAdjacentHTML(
    "beforeend",
    `<div class="quick-replies">
      <button data-action="retry" data-text="明天下午三点提醒我取快递">创建提醒</button>
      <button data-action="retry" data-text="查明天下午的安排">查日程</button>
      <button data-action="retry" data-text="附近咖啡店">找咖啡店</button>
    </div>`
  );
  completeTurn(turnId);
  setCharacter("idle", "待命");
}

function makeOperation(turnId, tool, args) {
  state.opCounter += 1;
  const op = {
    id: `op_${turnId}_${state.opCounter}`,
    toolCallId: `call_${uuid().slice(0, 8)}`,
    turnId,
    tool,
    args,
    status: "requested",
    card: null,
    result: null,
    localResult: null
  };
  state.operations.set(op.id, op);
  state.lastWriteOp = op;
  return op;
}

function appendToolCard(op) {
  const card = document.createElement("article");
  card.className = "card";
  card.dataset.op = op.id;
  card.innerHTML = `
    <div class="card-head">
      <span class="tool-icon">${toolIcon(op.tool)}</span>
      <div class="card-title">
        <strong>${escapeHtml(op.tool)}</strong>
        <small>${skillName(op.tool)} · 写操作</small>
      </div>
      <span class="chip pending" data-role="chip">待确认</span>
    </div>
    <dl class="args">${argumentRows(op)}</dl>
    <div class="card-actions" data-role="actions">
      <button class="btn ghost" data-action="cancel-tool" data-op="${op.id}">取消</button>
      <button class="btn primary" data-action="confirm-tool" data-op="${op.id}">${confirmLabel(op.tool)}</button>
    </div>
    <div data-role="result"></div>`;
  op.card = card;
  appendAssistantNode(card);
}

function renderAuthorizationCard(tool, label) {
  const card = document.createElement("article");
  card.className = "card";
  card.innerHTML = `
    <div class="card-head">
      <span class="tool-icon">${toolIcon(tool)}</span>
      <div class="card-title">
        <strong>${escapeHtml(tool)}</strong>
        <small>需要「提醒事项」授权 · 当前${escapeHtml(label)}</small>
      </div>
      <span class="chip error">需要授权</span>
    </div>
    <div class="card-actions">
      <button class="btn primary" data-action="grant-permission">模拟去设置授权</button>
    </div>`;
  appendAssistantNode(card);
}

async function executeOperation(op, options = {}) {
  if (op.status === "success") {
    emit(op.turnId, "tool.result", {
      tool: op.tool,
      toolCallId: op.toolCallId,
      operationId: op.id,
      status: "success",
      data: op.result?.data ?? null,
      deduplicated: true
    });
    showResult(op, { ...op.result, deduplicated: true });
    toast("已去重，未重复写入");
    return;
  }

  if (op.tool === "create_reminder" && state.scenario.permission !== "granted") {
    const label = state.scenario.permission === "denied" ? "已拒绝" : "已撤回";
    updateStatus(op, "authorization");
    showResult(op, {
      status: "needs_authorization",
      message: `提醒权限${label}，没有写入系统。请到系统设置开启后重试。`
    });
    setCharacter("waiting", "等待授权");
    return;
  }

  if (state.scenario.network === "offline") {
    const local = createLocalRecord(op);
    op.localResult = local;
    op.status = "unknown";
    updateStatus(op, "unknown");
    showResult(op, {
      status: "execution_unknown",
      message: "已写入本地系统，但工具结果回传失败。恢复网络后会重发结果，不会重复创建。"
    });
    setCharacter("waiting", "等待回传");
    return;
  }

  updateStatus(op, "running");
  setCharacter("executing", "正在执行");
  await sleep(options.duplicateTest ? 200 : 620);

  const result = executeMock(op);
  op.status = result.status;
  op.result = result;
  emit(op.turnId, "tool.result", {
    tool: op.tool,
    toolCallId: op.toolCallId,
    operationId: op.id,
    status: result.status,
    data: result.data ?? null,
    error: result.error ?? null,
    deduplicated: Boolean(result.deduplicated)
  });
  updateStatus(op, result.status);
  showResult(op, result);

  if (result.status === "success") setCharacter("done", "已完成");
  else if (result.status === "opened_external_app") setCharacter("done", "已交接");
  else setCharacter("waiting", "需要处理");

  completeTurn(op.turnId);

  if (op.tool === "create_reminder" && result.status === "success") {
    const when = result.data?.dueAt ? formatDue(result.data.dueAt) : "无日期待办";
    await say(
      `已创建提醒：<strong>${escapeHtml(result.data.title)}</strong> · ${escapeHtml(when)}。` +
        `<p class="hint">系统记录 ${escapeHtml(result.data.recordId)}（模拟）。</p>`
    );
  } else if (op.tool === "create_calendar_event" && result.status === "success") {
    await say("已创建日程「健身」：11月10日 16:00–17:00。记录与回复指向同一任务。");
  } else if (op.tool === "open_navigation") {
    await say("已打开地图（模拟）。这只表示已交接，不代表已开始路线或抵达。");
  } else if (op.tool === "prepare_message") {
    await say("短信草稿已准备（模拟）。最终发送要在系统界面由你完成，现在还不能说已发送。");
  }
}

function cancelOperation(op) {
  op.status = "cancelled";
  emit(op.turnId, "tool.result", {
    tool: op.tool,
    toolCallId: op.toolCallId,
    operationId: op.id,
    status: "cancelled",
    data: null,
    error: null,
    deduplicated: false
  });
  updateStatus(op, "cancelled");
  showResult(op, { status: "cancelled", message: "已取消，没有写入系统。" });
  completeTurn(op.turnId);
  setCharacter("idle", "待命");
}

function executeMock(op) {
  if (op.tool === "create_reminder") {
    const record = createLocalRecord(op);
    return {
      status: "success",
      data: {
        recordId: record.recordId,
        title: record.title,
        dueAt: record.dueAt,
        timezone: record.timezone,
        listName: "提醒事项"
      },
      deduplicated: record.deduplicated
    };
  }
  if (op.tool === "create_calendar_event") {
    return {
      status: "success",
      data: {
        recordId: `CAL-${uuid().slice(0, 8).toUpperCase()}`,
        title: op.args.title,
        startAt: op.args.startAt,
        endAt: op.args.endAt
      },
      deduplicated: false
    };
  }
  if (op.tool === "open_navigation") {
    return {
      status: "opened_external_app",
      data: { placeId: op.args.placeId, mode: op.args.mode, opened: true },
      deduplicated: false
    };
  }
  if (op.tool === "prepare_message") {
    return {
      status: "opened_external_app",
      data: { channel: op.args.channel, recipient: "张三", draftPrepared: true },
      deduplicated: false
    };
  }
  return { status: "success", data: {}, deduplicated: false };
}

function createLocalRecord(op) {
  const existing = state.reminders.find((item) => item.operationId === op.id);
  if (existing) return { ...existing, deduplicated: true };
  const record = {
    operationId: op.id,
    recordId: `REM-WEB-${uuid().slice(0, 6).toUpperCase()}`,
    title: op.args.title,
    dueAt: op.args.dueAt ?? null,
    timezone: op.args.timezone,
    createdAt: nowDate().toISOString()
  };
  state.reminders.push(record);
  localStorage.setItem(STORAGE_REMINDERS, JSON.stringify(state.reminders));
  syncStatus();
  return { ...record, deduplicated: false };
}

function flushPendingResults() {
  const pending = [...state.operations.values()].filter((op) => op.status === "unknown" && op.localResult);
  for (const op of pending) {
    op.status = "success";
    op.result = {
      status: "success",
      data: {
        recordId: op.localResult.recordId,
        title: op.localResult.title,
        dueAt: op.localResult.dueAt,
        timezone: op.localResult.timezone
      },
      deduplicated: true
    };
    emit(op.turnId, "tool.result", {
      tool: op.tool,
      toolCallId: op.toolCallId,
      operationId: op.id,
      status: "success",
      data: op.result.data,
      deduplicated: true
    });
    updateStatus(op, "success");
    showResult(op, { status: "success", message: "网络恢复，已回传本地结果；未重复创建。", deduplicated: true });
  }
  if (pending.length) toast("网络恢复，已回传待发送的结果");
}

function simulateLoopLimit() {
  if (state.busy) return;
  state.busy = true;
  const text = "连续查询三次活动数据";
  addUserMessage(text);
  const turnId = createTurn(text);
  setCharacter("executing", "正在执行");

  (async () => {
    for (let index = 1; index <= 3; index += 1) {
      emit(turnId, "tool.requested", {
        tool: "get_activity_summary",
        toolCallId: `call_loop_${index}`,
        operationId: `op_${turnId}_${index}`,
        arguments: {
          startAt: "2026-11-09T00:00:00+08:00",
          endAt: "2026-11-10T00:00:00+08:00",
          timezone: state.scenario.timezone,
          metrics: ["steps"]
        },
        requiresConfirmation: false
      });
      await sleep(240);
      emit(turnId, "tool.result", {
        tool: "get_activity_summary",
        toolCallId: `call_loop_${index}`,
        operationId: `op_${turnId}_${index}`,
        status: "success",
        data: { steps: 6482 },
        deduplicated: false
      });
    }
    emit(turnId, "turn.limit_reached", {
      reason: "tool_batches",
      message: "已达到本轮 3 批工具执行上限，任务尚未完成。",
      pendingTools: ["get_activity_summary"]
    });
    const bubble = await say(
      "已达到本轮 3 批工具执行上限，任务尚未完成。已完成的步骤保留，后续需要你确认再继续。"
    );
    bubble.insertAdjacentHTML("beforeend", `<p class="hint">这是用于验证 B09「模型循环上限」的模拟。</p>`);
    setCharacter("error", "已达上限");
    state.busy = false;
  })();
}

function createTurn(text) {
  state.turnCounter += 1;
  const turnId = `turn_demo_${String(state.turnCounter).padStart(4, "0")}_${uuid().slice(0, 4)}`;
  emit(turnId, "turn.started", {
    input: text,
    timezone: state.scenario.timezone,
    now: nowDate().toISOString()
  });
  return turnId;
}

function completeTurn(turnId) {
  emit(turnId, "turn.completed", { status: "completed" });
}

function emit(turnId, type, payload) {
  const seq = (state.seqByTurn.get(turnId) ?? 0) + 1;
  state.seqByTurn.set(turnId, seq);
  const event = {
    contractVersion: "1.0",
    eventId: `evt_${uuid()}`,
    turnId,
    seq,
    type,
    at: nowDate().toISOString(),
    payload
  };
  appendEventLog(event);
  return event;
}

function appendEventLog(event) {
  const item = document.createElement("div");
  item.className = `log-item type-${event.type.replaceAll(".", "_")}`;
  const summary = summarizeEvent(event);
  item.innerHTML = `
    <span class="log-seq">${event.seq}</span>
    <div class="log-body">
      <code>${escapeHtml(event.type)}</code>
      <p>${escapeHtml(summary)}</p>
      <details><summary>payload</summary><pre>${escapeHtml(JSON.stringify(event.payload, null, 2))}</pre></details>
    </div>`;
  eventLog.append(item);
  while (eventLog.children.length > 120) eventLog.firstElementChild.remove();
  eventLog.scrollTop = eventLog.scrollHeight;
}

function summarizeEvent(event) {
  const payload = event.payload ?? {};
  if (event.type === "turn.started") return `输入：${payload.input ?? ""}`;
  if (event.type === "assistant.delta") return String(payload.text ?? "").slice(0, 48);
  if (event.type === "tool.requested") return `${payload.tool} · ${payload.operationId ?? ""}`;
  if (event.type === "tool.confirmation_required") return `${payload.tool} 等待确认`;
  if (event.type === "tool.result") return `${payload.tool ?? ""} · ${payload.status}`;
  if (event.type === "tool.rejected") return `${payload.tool ?? ""} 被拒绝`;
  if (event.type === "turn.limit_reached") return payload.message ?? "达到上限";
  if (event.type === "turn.failed") return payload.message ?? "失败";
  return "completed";
}

function updateStatus(op, status) {
  const chip = op.card?.querySelector('[data-role="chip"]');
  if (!chip) return;
  const map = {
    requested: ["待确认", "pending"],
    running: ["执行中", "info"],
    success: ["已完成", "success"],
    cancelled: ["已取消", "muted"],
    unknown: ["待核对", "pending"],
    authorization: ["需要授权", "error"],
    opened_external_app: ["已交接", "info"]
  };
  const [label, className] = map[status] ?? [status, "muted"];
  chip.textContent = label;
  chip.className = `chip ${className}`;
}

function showResult(op, result) {
  const actions = op.card?.querySelector('[data-role="actions"]');
  if (actions) actions.remove();
  const target = op.card?.querySelector('[data-role="result"]');
  if (!target) return;
  const tone =
    result.status === "success" || result.status === "opened_external_app"
      ? "info"
      : result.status === "cancelled"
        ? ""
        : "warn";
  const text = result.message ?? resultMessage(op, result);
  target.innerHTML = `<div class="result-strip ${tone}">${checkIcon()} <span>${escapeHtml(text)}</span></div>`;
}

function resultMessage(op, result) {
  if (result.status === "success" && op.tool === "create_reminder") {
    return `已写入提醒（模拟）· ${result.data.recordId}${result.deduplicated ? " · 已去重" : ""}`;
  }
  if (result.status === "success" && op.tool === "create_calendar_event") {
    return `已创建日程（模拟）· ${result.data.recordId}`;
  }
  if (result.status === "opened_external_app" && op.tool === "open_navigation") {
    return "已打开地图（模拟）· 仅表示已交接";
  }
  if (result.status === "opened_external_app" && op.tool === "prepare_message") {
    return "草稿已准备（模拟）· 发送需在系统界面完成";
  }
  if (result.status === "execution_unknown") return result.message ?? "结果待核对";
  return result.status;
}

function appendCalendarCard() {
  const card = document.createElement("article");
  card.className = "card list-card";
  card.innerHTML = `
    <div class="list-row">
      <span class="list-time">09:30</span>
      <div class="list-body"><strong>站会</strong><small>09:30–10:00 · 工作</small></div>
    </div>
    <div class="list-row">
      <span class="list-time">全天</span>
      <div class="list-body"><strong>项目评审材料截止</strong><small>全天事件 · 工作</small></div>
    </div>
    <div class="list-row">
      <span class="list-time">14:00</span>
      <div class="list-body"><strong>设计评审</strong><small>14:00–15:00 · 工作</small></div>
    </div>`;
  appendAssistantNode(card);
}

function appendPlacesCard() {
  const card = document.createElement("article");
  card.className = "card list-card";
  card.innerHTML = placeCatalog()
    .map(
      (place) => `
      <div class="list-row place-row">
        <span class="rank">${place.rank}</span>
        <div class="list-body"><strong>${escapeHtml(place.name)}</strong><small>${escapeHtml(place.note)}</small></div>
        <button class="mini-action" data-action="choose-place" data-place="${place.id}">选择</button>
      </div>`
    )
    .join("");
  appendAssistantNode(card);
}

function placeCatalog() {
  return [
    { id: "p1", rank: 1, name: "Seesaw Coffee（南京西路店）", note: "步行 4 分钟 · 评分 4.7" },
    { id: "p2", rank: 2, name: "Manner Coffee（静安寺店）", note: "步行 6 分钟 · 评分 4.6" },
    { id: "p3", rank: 3, name: "星巴克臻选（愚园路店）", note: "步行 9 分钟 · 评分 4.5" }
  ];
}

function argumentRows(op) {
  const args = op.args;
  let rows = [];
  if (op.tool === "create_reminder") {
    rows = [
      ["标题", args.title],
      ["时间", args.dueAt ? formatDue(args.dueAt) : "无日期待办"],
      ["时区", args.timezone],
      ["列表", "提醒事项"]
    ];
  } else if (op.tool === "create_calendar_event") {
    rows = [
      ["标题", args.title],
      ["开始", formatDue(args.startAt)],
      ["结束", formatDue(args.endAt)],
      ["日历", args.calendarId ?? "个人"]
    ];
  } else if (op.tool === "open_navigation") {
    rows = [
      ["地点", state.selectedPlace?.name ?? args.placeId],
      ["方式", args.mode === "driving" ? "驾车" : args.mode],
      ["选择 ID", args.placeId]
    ];
  } else if (op.tool === "prepare_message") {
    rows = [
      ["渠道", "短信"],
      ["收件人", "张三（本地线索）"],
      ["正文", args.body, true]
    ];
  }
  return rows
    .map(
      ([label, value, wide]) =>
        `<div class="${wide ? "wide" : ""}"><dt>${escapeHtml(label)}</dt><dd>${escapeHtml(String(value))}</dd></div>`
    )
    .join("");
}

function confirmLabel(tool) {
  if (tool === "open_navigation") return "确认并打开地图";
  if (tool === "prepare_message") return "确认并准备草稿";
  if (tool === "create_calendar_event") return "确认并创建日程";
  return "确认并创建";
}

function toolIcon(tool) {
  return { create_reminder: "⏰", create_calendar_event: "🗓", open_navigation: "🧭", prepare_message: "✉️" }[tool] ?? "🛠";
}

function skillName(tool) {
  return { create_reminder: "schedule", create_calendar_event: "schedule", open_navigation: "travel", prepare_message: "communication" }[tool] ?? "tool";
}

function addUserMessage(text) {
  const wrapper = document.createElement("div");
  wrapper.className = "msg user";
  wrapper.innerHTML = `<div class="bubble"><p>${escapeHtml(text)}</p></div>`;
  chat.append(wrapper);
  scrollChat();
}

function appendAssistantNode(node) {
  const wrapper = document.createElement("div");
  wrapper.className = "msg assistant";
  const avatar = document.createElement("span");
  avatar.className = "msg-avatar";
  avatar.innerHTML = avatarMarkup();
  wrapper.append(avatar, node);
  chat.append(wrapper);
  scrollChat();
}

async function say(html, delay = 420) {
  const wrapper = document.createElement("div");
  wrapper.className = "msg assistant";
  wrapper.innerHTML = `<span class="msg-avatar">${avatarMarkup()}</span><div class="bubble"><span class="typing"><i></i><i></i><i></i></span></div>`;
  chat.append(wrapper);
  scrollChat();
  await sleep(delay);
  const bubble = wrapper.querySelector(".bubble");
  bubble.innerHTML = html;
  scrollChat();
  return bubble;
}

function assistantSay(text) {
  const wrapper = document.createElement("div");
  wrapper.className = "msg assistant";
  wrapper.innerHTML = `<span class="msg-avatar">${avatarMarkup()}</span><div class="bubble"><p>${escapeHtml(text)}</p></div>`;
  chat.append(wrapper);
  scrollChat();
}

function avatarMarkup() {
  return `<svg viewBox="0 0 64 64" aria-hidden="true">
    <path d="M9 38c0-11 9-20 21-20 10 0 18 6 20 14 2 1 5 2 9 1-2 4-5 6-9 7-3 8-10 13-20 13-12 0-21-6-21-15Z" fill="url(#whaleBody)"/>
    <circle cx="22" cy="32" r="2.4" fill="#0b1a2a"/>
    <circle cx="22.8" cy="31.3" r=".8" fill="#fff"/>
  </svg>`;
}

function checkIcon() {
  return `<svg viewBox="0 0 16 16" width="14" height="14" aria-hidden="true"><path d="M3 8.5 6.2 12 13 4.6" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
}

function setCharacter(name, label) {
  statebar.dataset.state = name;
  stateLabel.textContent = label;
  stateMeta.textContent = `${state.scenario.clock === "fixed" ? "固定时钟" : "本机时钟"} · ${state.scenario.timezone}`;
}

function syncScenario() {
  $$(".segmented").forEach((group) => {
    const value = state.scenario[group.dataset.field];
    $$("button", group).forEach((button) => {
      button.classList.toggle("active", button.dataset.value === value);
    });
  });
  $("#timezoneSelect").value = state.scenario.timezone;
  $("#autoConfirmToggle").checked = state.scenario.autoConfirm;
  syncStatus();
  updateClock();
}

function syncStatus() {
  $("#tzValue").textContent = state.scenario.timezone;
  const permissionText = { granted: "已允许", denied: "已拒绝", revoked: "已撤回" }[state.scenario.permission];
  $("#permValue").textContent = permissionText;
  $("#permValue").style.color = state.scenario.permission === "granted" ? "" : "var(--red)";
  $("#netValue").textContent = state.scenario.network === "online" ? "在线" : "断网";
  $("#netValue").style.color = state.scenario.network === "online" ? "" : "var(--red)";
  $("#healthValue").textContent = state.scenario.health === "has" ? "有数据" : "无数据";
  $("#countValue").textContent = String(state.reminders.length);
  const pill = $("#modePill");
  pill.textContent = state.scenario.network === "online" ? "Mock" : "Offline";
  pill.className = `pill ${state.scenario.network === "online" ? "ok" : "warn"}`;
}

function openSheet() {
  $("#sheetBackdrop").hidden = false;
  $("#scenarioSheet").hidden = false;
}

function closeSheet() {
  $("#sheetBackdrop").hidden = true;
  $("#scenarioSheet").hidden = true;
}

function updateClock() {
  const parts = zonedParts(nowDate(), state.scenario.timezone);
  $("#statusTime").textContent = `${pad(parts.hour)}:${pad(parts.minute)}`;
  $("#clockValue").textContent =
    state.scenario.clock === "fixed"
      ? `2026-11-09 10:00 · 固定`
      : `${parts.year}-${pad(parts.month)}-${pad(parts.day)} ${pad(parts.hour)}:${pad(parts.minute)}`;
}

function scrollChat() {
  requestAnimationFrame(() => {
    chat.scrollTop = chat.scrollHeight;
  });
}

let toastTimer = null;
function toast(message) {
  const element = $("#toast");
  element.textContent = message;
  element.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    element.hidden = true;
  }, 2400);
}

function nowDate() {
  if (state.scenario.clock === "fixed") {
    return new Date(FIXED_NOW);
  }
  return new Date();
}

function tomorrowRange(startHour, endHour) {
  const base = zonedParts(nowDate(), state.scenario.timezone);
  const offset = offsetMinutesAt(nowDate(), state.scenario.timezone);
  const nextDay = addDaysToDate(base, 1);
  return {
    start: toLocalIso({ ...nextDay, hour: startHour, minute: 0 }, offset),
    end: toLocalIso({ ...nextDay, hour: endHour, minute: 0 }, offset)
  };
}

const CN_DIGITS = { 零: 0, 一: 1, 二: 2, 两: 2, 三: 3, 四: 4, 五: 5, 六: 6, 七: 7, 八: 8, 九: 9 };
const DATE_WORDS = { 今天: 0, 明天: 1, 后天: 2, 大后天: 3 };

function zonedParts(date, timeZone) {
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    hour12: false,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit"
  });
  const parts = Object.fromEntries(formatter.formatToParts(date).map((part) => [part.type, part.value]));
  return {
    year: Number(parts.year),
    month: Number(parts.month),
    day: Number(parts.day),
    hour: Number(parts.hour === "24" ? "0" : parts.hour),
    minute: Number(parts.minute),
    second: Number(parts.second)
  };
}

function offsetMinutesAt(date, timeZone) {
  const parts = zonedParts(date, timeZone);
  const asUtc = Date.UTC(parts.year, parts.month - 1, parts.day, parts.hour, parts.minute, parts.second);
  return Math.round((asUtc - date.getTime()) / 60000);
}

function formatOffset(minutes) {
  const sign = minutes >= 0 ? "+" : "-";
  const abs = Math.abs(minutes);
  return `${sign}${pad(Math.floor(abs / 60))}:${pad(abs % 60)}`;
}

function toLocalIso({ year, month, day, hour, minute }, offset) {
  return `${year}-${pad(month)}-${pad(day)}T${pad(hour)}:${pad(minute)}:00${formatOffset(offset)}`;
}

function addDaysToDate({ year, month, day }, days) {
  const shifted = new Date(Date.UTC(year, month - 1, day + days));
  return { year: shifted.getUTCFullYear(), month: shifted.getUTCMonth() + 1, day: shifted.getUTCDate() };
}

function chineseNumber(text) {
  if (/^\d+$/.test(text)) return Number(text);
  if (text === "十") return 10;
  if (text.startsWith("十")) return 10 + (CN_DIGITS[text[1]] ?? 0);
  if (text.includes("十")) {
    const [tens, ones] = text.split("十");
    return (CN_DIGITS[tens] ?? 1) * 10 + (CN_DIGITS[ones] ?? 0);
  }
  let value = 0;
  for (const char of text) value = value * 10 + (CN_DIGITS[char] ?? 0);
  return value;
}

function parseReminder(text, now, timeZone) {
  const base = zonedParts(now, timeZone);
  const offset = offsetMinutesAt(now, timeZone);
  const dateMatch = /(大后天|后天|明天|今天)/.exec(text);
  const timeMatch = /(凌晨|早上|上午|中午|下午|傍晚|晚上)?\s*(\d{1,2}|[零一二两三四五六七八九十]{1,3})\s*[点时](半|一刻|三刻|[零一二三四五]刻|\d{1,2}分)?/.exec(text);

  let dueAt = null;
  let needsTime = false;
  let needsPeriod = false;
  let parsedHour = null;

  if (dateMatch || timeMatch) {
    const dayShift = dateMatch ? DATE_WORDS[dateMatch[1]] : 0;
    const dateParts = addDaysToDate(base, dayShift);
    if (!timeMatch) {
      needsTime = true;
    } else {
      const period = timeMatch[1] ?? null;
      let hour = chineseNumber(timeMatch[2]);
      const minuteToken = timeMatch[3] ?? null;
      let minute = 0;
      if (minuteToken === "半") minute = 30;
      else if (minuteToken === "一刻") minute = 15;
      else if (minuteToken === "三刻") minute = 45;
      else if (minuteToken?.endsWith("分")) minute = chineseNumber(minuteToken.slice(0, -1));
      else if (minuteToken?.endsWith("刻")) minute = chineseNumber(minuteToken.slice(0, -1)) * 15;

      if (period) {
        if (["下午", "傍晚", "晚上"].includes(period) && hour < 12) hour += 12;
        if (period === "中午" && hour < 11) hour += 12;
        if (["凌晨", "早上", "上午"].includes(period) && hour === 12) hour = 0;
      } else if (hour >= 1 && hour <= 12) {
        needsPeriod = true;
      }
      parsedHour = hour;
      if (hour >= 0 && hour <= 23 && !needsPeriod) {
        dueAt = toLocalIso({ ...dateParts, hour, minute }, offset);
      }
    }
  }

  let title = text
    .replace(/(大后天|后天|明天|今天)/g, " ")
    .replace(/(凌晨|早上|上午|中午|下午|傍晚|晚上)?\s*(\d{1,2}|[零一二两三四五六七八九十]{1,3})\s*[点时](半|一刻|三刻|[零一二三四五]刻|\d{1,2}分)?/g, " ")
    .replace(/^(帮我|请|麻烦)?\s*(提醒我|提醒|叫我|记得|记一下|创建待办[:：]?|待办[:：]?|新建待办[:：]?)\s*/g, "")
    .replace(/^[，,：:\s]+|[，,。.\s]+$/g, "")
    .trim();
  if (!title) title = "提醒";
  return { title, dueAt, needsTime, needsPeriod, parsedHour };
}

function formatDue(iso) {
  if (!iso) return "无日期";
  const parts = zonedParts(new Date(iso), state.scenario.timezone);
  return `${parts.month}月${parts.day}日 ${pad(parts.hour)}:${pad(parts.minute)}`;
}

function loadJson(key, fallback) {
  try {
    const value = JSON.parse(localStorage.getItem(key));
    return value ?? fallback;
  } catch {
    return fallback;
  }
}

function saveScenario() {
  localStorage.setItem(STORAGE_SCENARIO, JSON.stringify(state.scenario));
}

function pad(value) {
  return String(value).padStart(2, "0");
}

function uuid() {
  if (globalThis.crypto?.randomUUID) return globalThis.crypto.randomUUID();
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function escapeAttr(value) {
  return escapeHtml(value).replaceAll("`", "&#96;");
}
