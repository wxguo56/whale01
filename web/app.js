const FIXED_NOW = "2026-11-09T10:00:00+08:00";
const BOOT = Date.now();
const STORAGE_SCENARIO = "whale01.scenario.v1";
const STORAGE_REMINDERS = "whale01.reminders.v1";
const STORAGE_BACKEND_OFF = "whale01.backend.off";
const STORAGE_CONVERSATION = "whale01.conversation.v1";

const DEFAULTS = {
  clock: "fixed",
  timezone: "Asia/Shanghai",
  permission: "granted",
  calendarRead: "granted",
  calendarWrite: "granted",
  musicPermission: "granted",
  network: "online",
  health: "none",
  autoConfirm: false
};

const state = {
  scenario: loadScenario(),
  reminders: loadJson(STORAGE_REMINDERS, []),
  operations: new Map(),
  seqByTurn: new Map(),
  turnCounter: 0,
  opCounter: 0,
  lastWriteOp: null,
  confirmOp: null,
  selectedPlace: null,
  pendingReminder: null,
  music: {
    currentId: null,
    status: "idle",
    queue: [],
    position: 0,
    lastResults: []
  },
  nav: {
    current: "home",
    back: [],
    forward: [],
    homeScroll: null,
    chatScroll: null,
    settingsScroll: null
  },
  view: "home",
  viewBeforeSettings: null,
  busy: false,
  listening: false,
  backend: {
    enabled: false,
    baseUrl: defaultBackendBase(),
    status: "unknown",
    modelMode: null,
    executionMode: null,
    adapterConfigured: null,
    conversationId: loadStoredConversationId(),
    activePending: null,
    lastText: ""
  }
};

const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
const chat = $("#chat");
const input = $("#input");
const eventLog = $("#eventLog");
const statebar = $(".statebar");
const stateLabel = $("#stateLabel");
const stateMeta = $("#stateMeta");

function init() {
  renderWelcome();
  syncScenario();
  setCharacter("idle", "待命");
  bindComposer();
  bindChatActions();
  bindScenarioSheet();
  bindSidePanel();
  bindHome();
  bindSettings();
  bindConfirmSheet();
  bindGestures();
  bindBackend();
  initBackend();
  renderRoute("home");
  updateNavControls();
  updateClock();
  syncMusicMini();
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
        <p class="hint">试试「明天下午三点提醒我取快递」或「我想听歌」：我会补全信息、请求确认，再展示结果。</p>
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
    if (action === "review-tool") {
      const op = state.operations.get(button.dataset.op);
      if (op) openConfirmSheet(op);
      return;
    }
    if (action === "cancel-tool") {
      const op = state.operations.get(button.dataset.op);
      if (op) cancelOperation(op);
      return;
    }
    if (action === "grant-permission") {
      const permissionKey = button.dataset.permission ?? "permission";
      state.scenario[permissionKey] = "granted";
      saveScenario();
      syncScenario();
      toast(`已模拟开启${permissionCapability(permissionKey)}，请再试一次`);
      return;
    }
    if (action === "cancel-pending") return cancelPendingReminder();
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
    if (action === "choose-music") return chooseMusicTrack(button.dataset.track);
    if (action === "music-toggle") return runMusicControl("toggle");
    if (action === "music-next") return runMusicControl("next");
    if (action === "music-prev") return runMusicControl("prev");
    if (action === "music-library") return runMusicControl("library");
    if (action === "retry") return runTurn(button.dataset.text || input.value || "明天下午三点提醒我取快递");
  });

  $("#musicMini").addEventListener("click", (event) => {
    const button = event.target.closest("[data-action]");
    if (!button) return;
    if (button.dataset.action === "music-toggle") runMusicControl("toggle");
    else if (button.dataset.action === "music-next") runMusicControl("next");
  });
}

function bindScenarioSheet() {
  $("#settingsScenario").addEventListener("click", openSheet);
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

function bindHome() {
  $$("[data-home-prompt]").forEach((button) => {
    button.addEventListener("click", () => {
      showChat();
      runTurn(button.dataset.homePrompt);
    });
  });
  const enterChat = () => {
    showChat();
    setTimeout(() => input.focus(), 60);
  };
  $("#askEntry").addEventListener("click", enterChat);
  $("#startChat").addEventListener("click", enterChat);
  $("#openSettings").addEventListener("click", showSettings);
  $("#settingsBtn").addEventListener("click", showSettings);
  $("#backBtn").addEventListener("click", goBack);
  $("#forwardBtn").addEventListener("click", goForward);
}

function bindSettings() {
  $("#settingsBack").addEventListener("click", goBack);
  $("#settingsLog").addEventListener("click", () => {
    $("#sidePanel").classList.add("open");
  });
  $("#settingsReset").addEventListener("click", () => {
    localStorage.removeItem(STORAGE_SCENARIO);
    localStorage.removeItem(STORAGE_REMINDERS);
    location.reload();
  });
  $("#settingsVoice").addEventListener("change", (event) => {
    toast(event.target.checked ? "语音播报已开启（模拟）" : "语音播报已关闭（模拟）");
  });
}

function bindGestures() {
  const screen = $(".screen");
  let start = null;
  let swallowClick = false;

  screen.addEventListener("pointerdown", (event) => {
    swallowClick = false;
    if (event.pointerType === "mouse" && event.button !== 0) return;
    if (isGestureBlocked(event.target)) return;
    start = { x: event.clientX, y: event.clientY, pointerId: event.pointerId };
  });

  screen.addEventListener("pointercancel", () => {
    start = null;
  });

  screen.addEventListener("pointerup", (event) => {
    if (!start || start.pointerId !== event.pointerId) return;
    const dx = event.clientX - start.x;
    const dy = event.clientY - start.y;
    start = null;
    if (Math.abs(dx) < 60 || Math.abs(dx) <= Math.abs(dy) * 1.5) return;
    swallowClick = true;
    setTimeout(() => {
      swallowClick = false;
    }, 600);
    if (dx < 0) goBack();
    else goForward();
  });

  screen.addEventListener(
    "click",
    (event) => {
      if (!swallowClick) return;
      swallowClick = false;
      event.preventDefault();
      event.stopPropagation();
    },
    true
  );
}

function isGestureBlocked(target) {
  if (!$("#confirmSheet").hidden || !$("#scenarioSheet").hidden || !$("#voiceOverlay").hidden) return true;
  if ($("#sidePanel").classList.contains("open")) return true;
  return Boolean(
    target.closest(
      "input, textarea, select, [contenteditable='true'], .chips, .segmented, .event-log, .confirm-sheet, .sheet, .side"
    )
  );
}

function bindConfirmSheet() {
  $("#confirmClose").addEventListener("click", closeConfirmSheet);
  $("#confirmBackdrop").addEventListener("click", closeConfirmSheet);
  $("#confirmActions").addEventListener("click", (event) => {
    const button = event.target.closest("[data-action]");
    if (!button) return;
    const op = state.confirmOp;
    if (!op) return;
    if (button.dataset.action === "confirm-sheet") {
      closeConfirmSheet();
      executeOperation(op);
    } else if (button.dataset.action === "cancel-sheet") {
      closeConfirmSheet();
      cancelOperation(op);
    } else if (button.dataset.action === "edit-sheet") {
      renderConfirmSheet(op, true);
    } else if (button.dataset.action === "back-sheet") {
      renderConfirmSheet(op, false);
    } else if (button.dataset.action === "save-sheet") {
      saveConfirmEdits(op);
    }
  });
}

function showHome() {
  navigateTo("home");
}

function showChat() {
  navigateTo("chat");
}

function showSettings() {
  navigateTo("settings");
}

function navigateTo(route) {
  if (!["home", "chat", "settings"].includes(route) || route === state.nav.current) return;
  saveScroll(state.nav.current);
  state.nav.back.push(state.nav.current);
  state.nav.forward = [];
  state.nav.current = route;
  renderRoute(route);
  updateNavControls();
}

function goBack() {
  if (!state.nav.back.length) {
    toast("没有可返回的页面");
    return;
  }
  saveScroll(state.nav.current);
  state.nav.forward.push(state.nav.current);
  state.nav.current = state.nav.back.pop();
  renderRoute(state.nav.current);
  updateNavControls();
}

function goForward() {
  if (!state.nav.forward.length) {
    toast("没有可前进的页面");
    return;
  }
  saveScroll(state.nav.current);
  state.nav.back.push(state.nav.current);
  state.nav.current = state.nav.forward.pop();
  renderRoute(state.nav.current);
  updateNavControls();
}

function saveScroll(route) {
  if (route === "home") state.nav.homeScroll = $("#homeView").scrollTop;
  else if (route === "chat") state.nav.chatScroll = chat.scrollTop;
  else if (route === "settings") {
    const scroll = $("#settingsView .settings-scroll");
    if (scroll) state.nav.settingsScroll = scroll.scrollTop;
  }
}

function renderRoute(route) {
  state.view = route;
  $("#homeView").hidden = route !== "home";
  chat.hidden = route !== "chat";
  $(".composer").hidden = route !== "chat";
  $("#settingsView").hidden = route !== "settings";
  $("#settingsBtn").hidden = route === "settings";
  if (route === "settings") syncStatus();
  requestAnimationFrame(() => {
    if (route === "home" && state.nav.homeScroll !== null) {
      $("#homeView").scrollTop = state.nav.homeScroll;
    } else if (route === "chat") {
      if (state.nav.chatScroll !== null) chat.scrollTop = state.nav.chatScroll;
      else scrollChat();
    } else if (route === "settings") {
      const scroll = $("#settingsView .settings-scroll");
      if (scroll && state.nav.settingsScroll !== null) scroll.scrollTop = state.nav.settingsScroll;
    }
  });
}

function updateNavControls() {
  const backBtn = $("#backBtn");
  const forwardBtn = $("#forwardBtn");
  if (backBtn) backBtn.hidden = state.nav.back.length === 0;
  if (forwardBtn) forwardBtn.hidden = state.nav.forward.length === 0;
}

async function runTurn(text) {
  if (state.busy) {
    toast("上一条还在处理中");
    return;
  }
  if (state.backend.enabled) {
    await runBackendTurn(text);
    return;
  }
  state.busy = true;
  showChat();
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

  if (state.pendingReminder) {
    const handled = await resumePendingReminder(text, turnId);
    if (handled) {
      state.busy = false;
      return;
    }
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
    else if (/听歌|听音乐|播放|暂停|继续播放|恢复播放|上一首|下一首|切歌|音乐库|正在播放|来首歌|第[一二三2-3]首|^继续$|^恢复$/.test(text)) await musicFlow(text, turnId);
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
    state.pendingReminder = {
      title: intent.title,
      dateParts: intent.dateParts,
      missing: "time",
      hour: null,
      minute: 0,
      timezone: state.scenario.timezone
    };
    const bubble = await say("这条提醒要定在几点？请补充具体时间。我不会把未声明的时间默认成确定安排。");
    appendCancelPendingReply(bubble);
    completeTurn(turnId, "needs_input");
    setCharacter("waiting", "等待补充时间");
    return;
  }
  if (intent.needsPeriod) {
    state.pendingReminder = {
      title: intent.title,
      dateParts: intent.dateParts,
      missing: "period",
      hour: intent.parsedHour,
      minute: intent.parsedMinute ?? 0,
      timezone: state.scenario.timezone
    };
    const bubble = await say(
      `你指的是上午 ${displayHour(intent.parsedHour)} 点还是下午 ${displayHour(intent.parsedHour)} 点？也可以直接回复“下午三点”。`
    );
    appendCancelPendingReply(bubble);
    completeTurn(turnId, "needs_input");
    setCharacter("waiting", "等待上午/下午");
    return;
  }

  await startReminderPreview(turnId, intent.title, intent.dueAt);
}

async function startReminderPreview(turnId, title, dueAt) {
  state.pendingReminder = null;
  const args = { title, timezone: state.scenario.timezone };
  if (dueAt) args.dueAt = dueAt;
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

async function resumePendingReminder(text, turnId) {
  const pending = state.pendingReminder;
  if (!pending) return false;
  const trimmed = text.trim();

  if (/^(取消|算了|不用了|先不|不补了)/.test(trimmed)) {
    state.pendingReminder = null;
    await say("好，已取消这条待补提醒，没有创建任何记录。");
    emit(turnId, "tool.rejected", {
      tool: "create_reminder",
      status: "cancelled",
      reason: "user_cancelled_pending_task"
    });
    completeTurn(turnId, "cancelled");
    setCharacter("idle", "待命");
    return true;
  }

  if (isNewTaskRequest(trimmed)) {
    state.pendingReminder = null;
    assistantSay("已放弃上一条待补提醒，按新的请求处理。");
    return false;
  }

  const answer = parseTimeAnswer(trimmed);
  if (pending.missing === "time") {
    if (!answer || answer.periodOnly) {
      const bubble = await say("还需要一个具体时刻，例如“下午三点”或“上午十点半”。");
      appendCancelPendingReply(bubble);
      completeTurn(turnId, "needs_input");
      setCharacter("waiting", "等待补充时间");
      return true;
    }
    if (answer.needsPeriod) {
      pending.missing = "period";
      pending.hour = answer.hour;
      pending.minute = answer.minute;
      const bubble = await say(
        `你指的是上午 ${displayHour(answer.hour)} 点还是下午 ${displayHour(answer.hour)} 点？`
      );
      appendCancelPendingReply(bubble);
      completeTurn(turnId, "needs_input");
      setCharacter("waiting", "等待上午/下午");
      return true;
    }
    const dueAt = reminderDueAt(pending.dateParts, answer.hour, answer.minute);
    state.pendingReminder = null;
    setCharacter("thinking", "正在恢复任务");
    await sleep(180);
    await startReminderPreview(turnId, pending.title, dueAt);
    return true;
  }

  let hour = pending.hour;
  let minute = pending.minute ?? 0;
  if (answer && !answer.periodOnly) {
    if (answer.needsPeriod) {
      const bubble = await say("还需要确认是上午还是下午，请补充后再继续。");
      appendCancelPendingReply(bubble);
      completeTurn(turnId, "needs_input");
      setCharacter("waiting", "等待上午/下午");
      return true;
    }
    hour = answer.hour;
    minute = answer.minute;
  } else if (answer?.periodOnly) {
    hour = adjustHour(pending.hour, answer.period);
  } else if (/上午|早上|凌晨/.test(trimmed)) {
    hour = adjustHour(pending.hour, "上午");
  } else if (/下午|傍晚|晚上|中午/.test(trimmed)) {
    hour = adjustHour(pending.hour, trimmed.match(/下午|傍晚|晚上|中午/)[0]);
  } else {
    const bubble = await say("请补充“上午”或“下午”，例如直接回复“下午”。");
    appendCancelPendingReply(bubble);
    completeTurn(turnId, "needs_input");
    setCharacter("waiting", "等待上午/下午");
    return true;
  }

  const dueAt = reminderDueAt(pending.dateParts, hour, minute);
  state.pendingReminder = null;
  setCharacter("thinking", "正在恢复任务");
  await sleep(180);
  await startReminderPreview(turnId, pending.title, dueAt);
  return true;
}

function appendCancelPendingReply(bubble) {
  bubble.insertAdjacentHTML(
    "beforeend",
    `<div class="quick-replies"><button data-action="cancel-pending">取消这个任务</button></div>`
  );
}

function cancelPendingReminder() {
  if (!state.pendingReminder) {
    toast("当前没有待补任务");
    return;
  }
  if (state.busy) return;
  const turnId = createTurn("取消待补提醒");
  addUserMessage("取消待补提醒");
  state.pendingReminder = null;
  emit(turnId, "tool.rejected", {
    tool: "create_reminder",
    status: "cancelled",
    reason: "user_cancelled_pending_task"
  });
  assistantSay("已取消待补提醒，没有创建任何记录。之后补时间也不会恢复这个任务。");
  completeTurn(turnId, "cancelled");
  setCharacter("idle", "待命");
}

function isNewTaskRequest(text) {
  if (/(安排|日程|空闲|日历|运动|步数|走了|消耗|天气|气温|下雨|预报|咖啡|附近|导航|带我去|地点|总结|摘要|文章|短信|邮件|草稿|发给|听歌|听音乐|播放|音乐库)/.test(text)) {
    return true;
  }
  return /(提醒我|创建待办|新建待办|记一下|记得)/.test(text) && /(明天|后天|今天|周[一二三四五六日天])/.test(text) && text.length > 9;
}

async function calendarFlow(turnId) {
  if (state.scenario.calendarRead !== "granted") {
    const label = permissionLabel(state.scenario.calendarRead);
    const bubble = await say(
      `日历读取权限当前为「${label}」，不能查询日程或检查冲突。我不会用模拟日程冒充读取结果。`
    );
    if (state.scenario.calendarWrite === "granted") {
      bubble.insertAdjacentHTML(
        "beforeend",
        `<div class="quick-replies"><button data-action="calendar-create">明确创建明天 16:00 健身</button></div>
         <p class="hint">写入权限可用，但这次创建不会声称已检查日程冲突。</p>`
      );
    }
    emit(turnId, "tool.result", {
      tool: "list_calendar_events",
      status: "needs_authorization",
      data: null,
      error: { code: "calendar_read_permission_denied", message: label }
    });
    renderAuthorizationCard("list_calendar_events", label, "calendarRead");
    completeTurn(turnId, "needs_authorization");
    setCharacter("waiting", "等待日历读取授权");
    return;
  }
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

  if (state.scenario.calendarWrite !== "granted") {
    const label = permissionLabel(state.scenario.calendarWrite);
    await say(`日历写入权限当前为「${label}」，不能创建日程。查询结果不受影响。`);
    emit(turnId, "tool.result", {
      tool: "create_calendar_event",
      status: "needs_authorization",
      data: null,
      error: { code: "calendar_write_permission_denied", message: label }
    });
    renderAuthorizationCard("create_calendar_event", label, "calendarWrite");
    completeTurn(turnId, "needs_authorization");
    setCharacter("waiting", "等待日历写入授权");
    state.busy = false;
    return;
  }

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
  if (state.scenario.health === "loading") {
    await say("正在读取今天的模拟运动数据，结果还没有返回。此时不能把未知状态写成 0 步。");
    completeTurn(turnId, "pending");
    setCharacter("waiting", "正在读取健康数据");
    return;
  }
  if (state.scenario.health === "error") {
    await say("今天的运动数据读取失败。可能是权限、设备记录或服务异常，不能据此判断为 0 步。");
    emit(turnId, "turn.failed", {
      code: "health_read_failed",
      message: "运动数据读取失败，未取得可确认结果"
    });
    setCharacter("error", "健康数据读取失败");
    return;
  }
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
    openConfirmSheet(op);
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

async function musicFlow(text, turnId) {
  if (state.scenario.musicPermission !== "granted") {
    const label = permissionLabel(state.scenario.musicPermission);
    await say(
      `音乐库权限当前为「${label}」，不能查询或播放音乐。我不会假装已经读取你的 iPhone 音乐库。`
    );
    emit(turnId, "tool.result", {
      tool: "search_music_library",
      status: "needs_authorization",
      data: null,
      error: { code: "music_permission_denied", message: label }
    });
    renderAuthorizationCard("search_music_library", label, "musicPermission");
    completeTurn(turnId, "needs_authorization");
    setCharacter("waiting", "等待音乐库授权");
    return;
  }

  if (/暂停/.test(text)) return pauseMusic(turnId);
  if (/继续播放|恢复播放|继续音乐|恢复音乐|^继续$/.test(text)) return resumeMusic(turnId);
  if (/下一首|上一首|切歌/.test(text)) return skipMusic(text, turnId);
  if (/正在播放|播放什么|什么歌|播放状态/.test(text)) return describePlayback(turnId);

  const ordinal = /第([一二三2-3])首/.exec(text);
  if (ordinal) {
    const list = state.music.lastResults.length ? state.music.lastResults : musicLibrary();
    const track = list[ordinalToIndex(ordinal[1])];
    if (!track) {
      await say("这个序号没有对应的模拟曲目。请重新选择，不会自动播放其他内容。");
      completeTurn(turnId);
      setCharacter("waiting", "等待选曲");
      return;
    }
    return playMusicTrack(track, turnId);
  }

  const query = musicQuery(text);
  if (query) {
    const results = musicLibrary().filter((track) =>
      `${track.title} ${track.artist} ${track.album}`.toLowerCase().includes(query.toLowerCase())
    );
    state.music.lastResults = results;
    emit(turnId, "tool.requested", {
      tool: "search_music_library",
      toolCallId: `call_music_${uuid().slice(0, 8)}`,
      operationId: `op_music_${state.turnCounter}`,
      arguments: { query, limit: 5, source: "simulated_library" },
      requiresConfirmation: false
    });
    if (!results.length) {
      await say(
        `模拟曲库里没有匹配“${escapeHtml(query)}”的曲目。不会自动转到付费云端播放，也不会伪造音源。`
      );
      emit(turnId, "tool.result", {
        tool: "search_music_library",
        status: "success",
        data: { candidates: [], source: "simulated_library" }
      });
      completeTurn(turnId);
      setCharacter("waiting", "没有匹配曲目");
      return;
    }
    await say(`在模拟曲库中匹配到 ${results.length} 首。请选择一首：`);
    appendMusicLibraryCard(results);
    emit(turnId, "tool.result", {
      tool: "search_music_library",
      status: "success",
      data: { candidates: results.map(publicTrack), source: "simulated_library" }
    });
    completeTurn(turnId);
    setCharacter("waiting", "等待选曲");
    return;
  }

  if (state.music.currentId) {
    const track = currentTrack();
    await say(
      `当前是${state.music.status === "playing" ? "模拟播放中" : "模拟暂停"}：《${escapeHtml(track.title)}》· ${escapeHtml(track.artist)}。`
    );
    appendMusicPlayerCard();
  }
  await say(
    "音乐功能演示（模拟）。这里展示的是演示曲库，不是你 iPhone 里的音乐，也没有真实音源。请选择一首继续："
  );
  state.music.lastResults = musicLibrary();
  appendMusicLibraryCard(state.music.lastResults);
  emit(turnId, "tool.result", {
    tool: "get_playback_state",
    status: "success",
    data: { ...playbackState(), simulated: true }
  });
  completeTurn(turnId);
  setCharacter("waiting", "等待选曲");
}

function musicLibrary() {
  return [
    { id: "trk_night", title: "夜航", artist: "鲸鱼示例乐队", album: "演示曲库 A", duration: 214 },
    { id: "trk_rain", title: "雨天电台", artist: "林间信号", album: "演示曲库 B", duration: 242 },
    { id: "trk_light", title: "光的方向", artist: "示例歌手", album: "演示曲库 C", duration: 198 }
  ];
}

function publicTrack(track) {
  return { trackId: track.id, title: track.title, artist: track.artist, album: track.album, duration: track.duration };
}

function currentTrack() {
  return musicLibrary().find((track) => track.id === state.music.currentId) ?? null;
}

function playbackState() {
  const track = currentTrack();
  return {
    state: track ? state.music.status : "idle",
    track: track ? publicTrack(track) : null,
    queueLength: state.music.queue.length,
    position: state.music.position
  };
}

function ordinalToIndex(token) {
  return { 一: 0, 二: 1, 三: 2, "2": 1, "3": 2 }[token] ?? -1;
}

function musicQuery(text) {
  if (/音乐库|听歌|听音乐|来首歌|放首歌/.test(text)) return "";
  const match = /(?:播放|听|放)\s*([《“"]?[^，。,.!！?？]{1,18}?)(?:这首歌|的歌|歌曲|音乐)?$/.exec(text);
  if (!match) return "";
  const query = match[1]
    .replace(/^[《“"]|[》”"]$/g, "")
    .replace(/^(一下|一首|首歌|音乐库里的|音乐库中的)/, "")
    .trim();
  if (!query || ["歌", "音乐", "歌曲", "首歌", "一首歌", "听歌"].includes(query)) return "";
  return query;
}

async function playMusicTrack(track, turnId) {
  const source = state.music.lastResults.length ? state.music.lastResults : musicLibrary();
  state.music.queue = source.some((item) => item.id === track.id) ? [...source] : musicLibrary();
  state.music.currentId = track.id;
  state.music.status = "playing";
  state.music.position = Math.max(0, state.music.queue.findIndex((item) => item.id === track.id));
  emit(turnId, "tool.requested", {
    tool: "play_music",
    toolCallId: `call_music_${uuid().slice(0, 8)}`,
    operationId: `op_music_${state.turnCounter}_play`,
    arguments: { trackId: track.id, queueIntent: "replace", simulated: true },
    requiresConfirmation: false
  });
  await say(
    `已切换为模拟播放：《${escapeHtml(track.title)}》· ${escapeHtml(track.artist)}。` +
      `<p class="hint">这是演示状态，没有真实音频输出，也没有读取 iPhone 音乐库。</p>`
  );
  appendMusicPlayerCard();
  emit(turnId, "tool.result", {
    tool: "play_music",
    status: "success",
    data: { state: "playing", track: publicTrack(track), audible: false, simulated: true }
  });
  syncMusicMini();
  completeTurn(turnId);
  setCharacter("done", "已切换模拟播放");
}

async function pauseMusic(turnId) {
  const track = currentTrack();
  if (!track) {
    await say("当前没有模拟播放会话，无法暂停。请先选择一首演示曲目。");
    emit(turnId, "tool.result", {
      tool: "pause_music",
      status: "success",
      data: { state: "idle", message: "没有活动播放会话" }
    });
    completeTurn(turnId);
    setCharacter("idle", "没有活动播放");
    return;
  }
  state.music.status = "paused";
  emit(turnId, "tool.requested", {
    tool: "pause_music",
    toolCallId: `call_music_${uuid().slice(0, 8)}`,
    operationId: `op_music_${state.turnCounter}_pause`,
    arguments: { sessionTrackId: track.id },
    requiresConfirmation: false
  });
  await say(`已暂停《${escapeHtml(track.title)}》的模拟播放状态。没有真实音频需要停止。`);
  appendMusicPlayerCard();
  emit(turnId, "tool.result", {
    tool: "pause_music",
    status: "success",
    data: { state: "paused", track: publicTrack(track), simulated: true }
  });
  syncMusicMini();
  completeTurn(turnId);
  setCharacter("idle", "模拟已暂停");
}

async function resumeMusic(turnId) {
  const track = currentTrack();
  if (!track) {
    await say("没有可恢复的模拟播放队列。请从演示曲库选择一首：");
    state.music.lastResults = musicLibrary();
    appendMusicLibraryCard(state.music.lastResults);
    completeTurn(turnId);
    setCharacter("waiting", "等待选曲");
    return;
  }
  state.music.status = "playing";
  emit(turnId, "tool.requested", {
    tool: "resume_music",
    toolCallId: `call_music_${uuid().slice(0, 8)}`,
    operationId: `op_music_${state.turnCounter}_resume`,
    arguments: { sessionTrackId: track.id },
    requiresConfirmation: false
  });
  await say(`已恢复《${escapeHtml(track.title)}》的模拟播放状态。仍然没有真实音频输出。`);
  appendMusicPlayerCard();
  emit(turnId, "tool.result", {
    tool: "resume_music",
    status: "success",
    data: { state: "playing", track: publicTrack(track), simulated: true }
  });
  syncMusicMini();
  completeTurn(turnId);
  setCharacter("done", "模拟播放中");
}

async function skipMusic(text, turnId) {
  const track = currentTrack();
  if (!track) {
    await say("没有活动播放会话，无法切歌。请先选择一首演示曲目：");
    state.music.lastResults = musicLibrary();
    appendMusicLibraryCard(state.music.lastResults);
    completeTurn(turnId);
    setCharacter("waiting", "等待选曲");
    return;
  }
  const direction = /上一首/.test(text) ? "previous" : "next";
  const delta = direction === "next" ? 1 : -1;
  const queue = state.music.queue.length ? state.music.queue : musicLibrary();
  const nextIndex = state.music.position + delta;
  if (nextIndex < 0 || nextIndex >= queue.length) {
    await say(`已经到达模拟队列的${direction === "next" ? "末尾" : "开头"}，没有继续切换。`);
    emit(turnId, "tool.result", {
      tool: "skip_music_track",
      status: "boundary",
      data: { direction, state: state.music.status, track: publicTrack(track) }
    });
    completeTurn(turnId);
    setCharacter("waiting", "队列边界");
    return;
  }
  const nextTrack = queue[nextIndex];
  state.music.position = nextIndex;
  state.music.currentId = nextTrack.id;
  state.music.status = "playing";
  emit(turnId, "tool.requested", {
    tool: "skip_music_track",
    toolCallId: `call_music_${uuid().slice(0, 8)}`,
    operationId: `op_music_${state.turnCounter}_${direction}`,
    arguments: { direction, sessionTrackId: track.id, simulated: true },
    requiresConfirmation: false
  });
  await say(`已切换到《${escapeHtml(nextTrack.title)}》· ${escapeHtml(nextTrack.artist)} 的模拟播放状态。`);
  appendMusicPlayerCard();
  emit(turnId, "tool.result", {
    tool: "skip_music_track",
    status: "success",
    data: { direction, state: "playing", track: publicTrack(nextTrack), simulated: true }
  });
  syncMusicMini();
  completeTurn(turnId);
  setCharacter("done", "模拟播放中");
}

async function describePlayback(turnId) {
  const stateData = playbackState();
  emit(turnId, "tool.result", {
    tool: "get_playback_state",
    status: "success",
    data: { ...stateData, simulated: true }
  });
  if (!stateData.track) {
    await say("当前没有模拟播放会话，也没有可观察到的真实播放状态。");
    completeTurn(turnId);
    setCharacter("idle", "没有活动播放");
    return;
  }
  const label = { playing: "模拟播放中", paused: "模拟已暂停", loading: "加载中" }[stateData.state] ?? stateData.state;
  await say(`当前状态：${label} · 《${escapeHtml(stateData.track.title)}》· ${escapeHtml(stateData.track.artist)}。`);
  appendMusicPlayerCard();
  completeTurn(turnId);
  setCharacter("waiting", "播放状态");
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
        <strong>${escapeHtml(toolLabel(op.tool))}</strong>
        <small>${escapeHtml(skillLabel(op.tool))} · 需要确认</small>
      </div>
      <span class="chip pending" data-role="chip">待确认</span>
    </div>
    <dl class="args">${argumentRows(op)}</dl>
    <div class="card-actions" data-role="actions">
      <button class="btn ghost" data-action="cancel-tool" data-op="${op.id}">取消</button>
      <button class="btn primary" data-action="review-tool" data-op="${op.id}">查看并确认</button>
    </div>
    <div data-role="result"></div>`;
  op.card = card;
  appendAssistantNode(card);
}

function renderAuthorizationCard(tool, label, permissionKey = "permission") {
  const capability = permissionCapability(permissionKey);
  const card = document.createElement("article");
  card.className = "card";
  card.innerHTML = `
    <div class="card-head">
      <span class="tool-icon">${toolIcon(tool)}</span>
      <div class="card-title">
        <strong>${escapeHtml(toolLabel(tool))}</strong>
        <small>需要「${escapeHtml(capability)}」授权 · 当前${escapeHtml(label)}</small>
      </div>
      <span class="chip error">需要授权</span>
    </div>
    <div class="card-actions">
      <button class="btn primary" data-action="grant-permission" data-permission="${escapeAttr(permissionKey)}">模拟去设置授权</button>
    </div>`;
  appendAssistantNode(card);
}

async function executeOperation(op, options = {}) {
  if (op.status === "cancelled" || op.status === "superseded") {
    emit(op.turnId, "tool.rejected", {
      tool: op.tool,
      toolCallId: op.toolCallId,
      operationId: op.id,
      status: "rejected",
      reason: op.status === "superseded" ? "operation_superseded" : "operation_cancelled"
    });
    toast("该确认已失效，没有执行任何操作");
    return;
  }
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

  if (op.tool === "create_calendar_event" && state.scenario.calendarWrite !== "granted") {
    const label = permissionLabel(state.scenario.calendarWrite);
    updateStatus(op, "authorization");
    showResult(op, {
      status: "needs_authorization",
      message: `日历写入权限${label}，没有创建日程。请开启日历写入权限后重试。`
    });
    setCharacter("waiting", "等待日历写入授权");
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

function recordBackendReminder(operationId, data) {
  if (!operationId || state.reminders.some((item) => item.operationId === operationId)) return;
  state.reminders.push({
    operationId,
    recordId: data.recordId ?? `REM-BACKEND-${uuid().slice(0, 6).toUpperCase()}`,
    title: data.title ?? "提醒",
    dueAt: data.dueAt ?? null,
    timezone: data.timezone ?? state.scenario.timezone,
    createdAt: data.createdAt ?? nowDate().toISOString(),
    backendMock: true
  });
  localStorage.setItem(STORAGE_REMINDERS, JSON.stringify(state.reminders));
  syncStatus();
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

function completeTurn(turnId, status = "completed") {
  emit(turnId, "turn.completed", { status });
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
  if (event.type === "tool.rejected") return `${payload.tool ?? ""} 被拒绝${payload.reason ? ` · ${payload.reason}` : ""}`;
  if (event.type === "turn.limit_reached") return payload.message ?? "达到上限";
  if (event.type === "turn.failed") return payload.message ?? "失败";
  return payload.status ?? "completed";
}

function updateStatus(op, status) {
  const chip = op.card?.querySelector('[data-role="chip"]');
  if (!chip) return;
  const map = {
    requested: ["待确认", "pending"],
    running: ["执行中", "info"],
    success: ["已完成", "success"],
    cancelled: ["已取消", "muted"],
    superseded: ["已作废", "muted"],
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

function appendMusicLibraryCard(results) {
  const card = document.createElement("article");
  card.className = "card music-card";
  card.innerHTML = `
    <div class="card-head">
      <span class="tool-icon">♪</span>
      <div class="card-title">
        <strong>音乐功能演示</strong>
        <small>模拟曲库 · 未读取 iPhone 音乐</small>
      </div>
      <span class="chip pending">模拟</span>
    </div>
    <p class="music-note">没有真实音源。这里是选曲与播放状态演示，不代表已播放你的音乐库。</p>
    <div class="track-list">
      ${results
        .map(
          (track, index) => `
        <div class="track-row">
          <span class="track-index">${index + 1}</span>
          <div class="track-body"><strong>${escapeHtml(track.title)}</strong><small>${escapeHtml(track.artist)} · ${escapeHtml(track.album)}</small></div>
          <span class="track-duration">${formatTrackDuration(track.duration)}</span>
          <button class="mini-action" type="button" data-action="choose-music" data-track="${escapeAttr(track.id)}" aria-label="模拟播放 ${escapeAttr(track.title)}">播放</button>
        </div>`
        )
        .join("")}
    </div>`;
  appendAssistantNode(card);
}

function appendMusicPlayerCard() {
  const track = currentTrack();
  if (!track) return;
  const isPlaying = state.music.status === "playing";
  const card = document.createElement("article");
  card.className = "card music-card music-player-card";
  card.innerHTML = `
    <div class="card-head">
      <span class="tool-icon">${isPlaying ? "▶" : "⏸"}</span>
      <div class="card-title">
        <strong>${isPlaying ? "模拟播放中" : "模拟已暂停"}</strong>
        <small>${escapeHtml(track.title)} · ${escapeHtml(track.artist)}</small>
      </div>
      <span class="chip ${isPlaying ? "info" : "muted"}">${isPlaying ? "播放" : "暂停"}</span>
    </div>
    <div class="music-now">
      <span class="music-eq ${isPlaying ? "on" : ""}" aria-hidden="true"><i></i><i></i><i></i><i></i></span>
      <div class="track-body"><strong>${escapeHtml(track.title)}</strong><small>${escapeHtml(track.album)} · ${formatTrackDuration(track.duration)}</small></div>
    </div>
    <p class="music-note">这是本地模拟状态，没有真实音频输出。</p>
    <div class="card-actions">
      <button class="btn ghost" type="button" data-action="music-toggle">${isPlaying ? "暂停" : "继续"}</button>
      <button class="btn ghost" type="button" data-action="music-prev">上一首</button>
      <button class="btn ghost" type="button" data-action="music-next">下一首</button>
      <button class="btn primary" type="button" data-action="music-library">选歌</button>
    </div>`;
  appendAssistantNode(card);
}

function formatTrackDuration(seconds) {
  return `${Math.floor(seconds / 60)}:${pad(seconds % 60)}`;
}

function syncMusicMini() {
  const mini = $("#musicMini");
  if (!mini) return;
  const track = currentTrack();
  mini.hidden = !track;
  if (!track) return;
  $("#musicMiniTitle").textContent = `${track.title} · ${track.artist}`;
  $("#musicMiniMeta").textContent = `${state.music.status === "playing" ? "模拟播放中" : "模拟已暂停"} · 无真实音频`;
  $("#musicMiniToggle").textContent = state.music.status === "playing" ? "暂停" : "继续";
}

async function chooseMusicTrack(trackId) {
  if (state.busy) return;
  const track = musicLibrary().find((item) => item.id === trackId);
  if (!track) return;
  state.busy = true;
  showChat();
  addUserMessage(`播放《${track.title}》`);
  const turnId = createTurn(`播放音乐 ${track.title}`);
  setCharacter("thinking", "正在准备模拟播放");
  await sleep(260);
  await playMusicTrack(track, turnId);
  state.busy = false;
}

async function runMusicControl(kind) {
  if (state.busy) return;
  const labels = { toggle: "播放 / 暂停", next: "下一首", prev: "上一首", library: "从音乐库选歌" };
  const text = labels[kind] ?? "音乐控制";
  state.busy = true;
  showChat();
  addUserMessage(text);
  const turnId = createTurn(text);
  await sleep(180);
  try {
    if (kind === "toggle") {
      if (state.music.status === "playing") await pauseMusic(turnId);
      else await resumeMusic(turnId);
    } else if (kind === "next") {
      await skipMusic("下一首", turnId);
    } else if (kind === "prev") {
      await skipMusic("上一首", turnId);
    } else if (kind === "library") {
      state.music.lastResults = musicLibrary();
      await say("音乐功能演示（模拟）。请选择一首演示曲目；不会读取 iPhone 音乐库。");
      appendMusicLibraryCard(state.music.lastResults);
      completeTurn(turnId);
      setCharacter("waiting", "等待选曲");
    }
  } finally {
    state.busy = false;
  }
}

function placeCatalog() {
  return [
    { id: "p1", rank: 1, name: "Seesaw Coffee（南京西路店）", note: "步行 4 分钟 · 评分 4.7" },
    { id: "p2", rank: 2, name: "Manner Coffee（静安寺店）", note: "步行 6 分钟 · 评分 4.6" },
    { id: "p3", rank: 3, name: "星巴克臻选（愚园路店）", note: "步行 9 分钟 · 评分 4.5" }
  ];
}

function toolLabel(tool) {
  return {
    create_reminder: "创建提醒",
    create_calendar_event: "创建日程",
    list_calendar_events: "查询日程",
    search_music_library: "查询音乐库",
    play_music: "播放音乐",
    pause_music: "暂停音乐",
    resume_music: "继续播放",
    skip_music_track: "切换曲目",
    get_playback_state: "获取播放状态",
    open_navigation: "打开地图",
    prepare_message: "准备短信草稿"
  }[tool] ?? "执行操作";
}

function skillLabel(tool) {
  return {
    create_reminder: "日程能力",
    create_calendar_event: "日程能力",
    list_calendar_events: "日程能力",
    search_music_library: "音乐能力",
    play_music: "音乐能力",
    pause_music: "音乐能力",
    resume_music: "音乐能力",
    skip_music_track: "音乐能力",
    get_playback_state: "音乐能力",
    open_navigation: "出行能力",
    prepare_message: "通讯能力"
  }[tool] ?? "助手能力";
}

function displayZone(timeZone) {
  const map = {
    "Asia/Shanghai": "上海（+08:00）",
    "Europe/Berlin": "柏林（+01:00）",
    "America/New_York": "纽约（-05:00）"
  };
  return map[timeZone] ?? timeZone;
}

function confirmTitle(tool) {
  return {
    create_reminder: "创建提醒",
    create_calendar_event: "创建日程",
    open_navigation: "打开地图",
    prepare_message: "准备短信草稿"
  }[tool] ?? "确认操作";
}

function confirmPrimaryLabel(tool) {
  return {
    create_reminder: "确认创建",
    create_calendar_event: "确认创建",
    open_navigation: "确认打开",
    prepare_message: "确认准备"
  }[tool] ?? "确认";
}

function openConfirmSheet(op) {
  renderConfirmSheet(op, false);
}

function closeConfirmSheet() {
  $("#confirmBackdrop").hidden = true;
  $("#confirmSheet").hidden = true;
  state.confirmOp = null;
}

function renderConfirmSheet(op, editing) {
  state.confirmOp = op;
  $("#confirmTitle").textContent = confirmTitle(op.tool);
  $("#confirmSubtitle").textContent = editing ? "修改后需要重新确认" : confirmSubtitle(op);
  const body = $("#confirmBody");
  const actions = $("#confirmActions");
  const isReminder = op.tool === "create_reminder";

  if (editing && isReminder) {
    body.innerHTML = `
      <div class="confirm-row"><span class="label">事项</span><input id="editTitle" value="${escapeAttr(op.args.title)}" aria-label="提醒事项"></div>
      <div class="confirm-row"><span class="label">时间</span><input id="editDue" type="datetime-local" value="${op.args.dueAt ? toDateTimeLocal(op.args.dueAt) : ""}" aria-label="提醒时间"></div>
      <div class="confirm-row"><span class="label">时区</span><span class="value">${escapeHtml(displayZone(op.args.timezone))}</span></div>
      <p class="confirm-note">留空表示无日期待办。修改后旧确认失效，需要重新确认。</p>`;
    actions.innerHTML = `
      <button class="btn ghost" data-action="back-sheet">返回</button>
      <button class="btn primary" data-action="save-sheet">保存修改</button>`;
  } else {
    body.innerHTML = `${confirmRows(op)}<p class="confirm-note">${escapeHtml(confirmNote(op))}</p>`;
    actions.innerHTML = isReminder
      ? `<button class="btn ghost modify" data-action="edit-sheet">修改</button>
         <button class="btn ghost" data-action="cancel-sheet">取消</button>
         <button class="btn primary" data-action="confirm-sheet">${confirmPrimaryLabel(op.tool)}</button>`
      : `<button class="btn ghost" data-action="cancel-sheet">取消</button>
         <button class="btn primary" data-action="confirm-sheet">${confirmPrimaryLabel(op.tool)}</button>`;
  }
  $("#confirmBackdrop").hidden = false;
  $("#confirmSheet").hidden = false;
}

function confirmSubtitle(op) {
  if (op.tool === "open_navigation") return "交接前预览 · 地图尚未打开";
  if (op.tool === "prepare_message") return "草稿预览 · 尚未打开系统界面";
  return "执行前预览 · 尚未写入";
}

function confirmRows(op) {
  const args = op.args;
  let rows = [];
  if (op.tool === "create_reminder") {
    rows = [
      ["事项", args.title],
      ["时间", args.dueAt ? formatDueFull(args.dueAt) : "无日期待办"],
      ["时区", displayZone(args.timezone)]
    ];
  } else if (op.tool === "create_calendar_event") {
    rows = [
      ["日程", args.title],
      ["开始", formatDue(args.startAt)],
      ["结束", formatDue(args.endAt)],
      ["日历", args.calendarId ?? "个人"]
    ];
  } else if (op.tool === "open_navigation") {
    rows = [
      ["地点", state.selectedPlace?.name ?? args.placeId],
      ["方式", args.mode === "driving" ? "驾车" : args.mode]
    ];
  } else if (op.tool === "prepare_message") {
    rows = [
      ["收件人", "张三"],
      ["渠道", "短信"],
      ["正文", args.body]
    ];
  }
  return rows
    .map(
      ([label, value]) =>
        `<div class="confirm-row"><span class="label">${escapeHtml(label)}</span><span class="value">${escapeHtml(String(value))}</span></div>`
    )
    .join("");
}

function confirmNote(op) {
  if (op.tool === "create_reminder") return "确认后才会请求提醒事项权限并写入系统。";
  if (op.tool === "create_calendar_event") return "确认后才会写入日历，不覆盖已有事件。";
  if (op.tool === "open_navigation") return "确认后只会打开地图并交接地点，不代表已开始路线或抵达。";
  if (op.tool === "prepare_message") return "确认后只准备系统草稿，最终发送由你在系统界面完成。";
  return "确认后才会执行。";
}

function saveConfirmEdits(op) {
  const title = $("#editTitle")?.value.trim() ?? "";
  if (!title) {
    toast("事项不能为空");
    return;
  }
  const dueValue = $("#editDue")?.value ?? "";
  const args = { ...op.args, title };
  if (dueValue) args.dueAt = fromDateTimeLocal(dueValue);
  else delete args.dueAt;

  const changed = args.title !== op.args.title || args.dueAt !== op.args.dueAt;
  if (!changed) {
    closeConfirmSheet();
    toast("参数未变化，原确认仍然有效");
    return;
  }

  op.status = "superseded";
  updateStatus(op, "superseded");
  showResult(op, {
    status: "superseded",
    message: "参数已修改，这张旧确认已作废，不能再执行。"
  });
  emit(op.turnId, "tool.rejected", {
    tool: op.tool,
    toolCallId: op.toolCallId,
    operationId: op.id,
    status: "rejected",
    reason: "operation_superseded_by_edit"
  });

  const nextOp = makeOperation(op.turnId, op.tool, args);
  nextOp.supersedes = op.id;
  appendToolCard(nextOp);
  emit(op.turnId, "tool.requested", {
    tool: nextOp.tool,
    toolCallId: nextOp.toolCallId,
    operationId: nextOp.id,
    arguments: args,
    requiresConfirmation: true,
    requiresAuthorization: nextOp.tool === "create_calendar_event" ? ["eventkit"] : ["eventkit"]
  });
  emit(op.turnId, "tool.confirmation_required", {
    tool: nextOp.tool,
    toolCallId: nextOp.toolCallId,
    operationId: nextOp.id,
    arguments: args
  });
  closeConfirmSheet();
  toast("已生成新的待确认操作，旧确认已作废");
  setCharacter("waiting", "等待确认");
}

function toDateTimeLocal(iso) {
  const parts = zonedParts(new Date(iso), state.scenario.timezone);
  return `${parts.year}-${pad(parts.month)}-${pad(parts.day)}T${pad(parts.hour)}:${pad(parts.minute)}`;
}

function fromDateTimeLocal(value) {
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/.exec(value);
  if (!match) return null;
  const [, year, month, day, hour, minute] = match;
  return toLocalIso(
    { year: Number(year), month: Number(month), day: Number(day), hour: Number(hour), minute: Number(minute) },
    offsetMinutesAt(nowDate(), state.scenario.timezone)
  );
}

function argumentRows(op) {
  const args = op.args;
  let rows = [];
  if (op.tool === "create_reminder") {
    rows = [
      ["标题", args.title],
      ["时间", args.dueAt ? formatDue(args.dueAt) : "无日期待办"],
      ["时区", displayZone(args.timezone)],
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
      ["方式", args.mode === "driving" ? "驾车" : args.mode]
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
  return {
    create_reminder: "⏰",
    create_calendar_event: "🗓",
    list_calendar_events: "🗓",
    search_music_library: "🎵",
    play_music: "🎵",
    pause_music: "🎵",
    resume_music: "🎵",
    skip_music_track: "🎵",
    get_playback_state: "🎵",
    open_navigation: "🧭",
    prepare_message: "✉️"
  }[tool] ?? "🛠";
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

const PERMISSION_LABELS = { granted: "已允许", denied: "已拒绝", revoked: "已撤回" };

function permissionLabel(value) {
  return PERMISSION_LABELS[value] ?? "未知";
}

function permissionCapability(key) {
  return {
    permission: "提醒事项",
    calendarRead: "日历读取",
    calendarWrite: "日历写入",
    musicPermission: "音乐库"
  }[key] ?? "系统能力";
}

function healthSummary() {
  return {
    none: { primary: "暂无数据", note: "不推测为 0", settings: "无数据", panel: "无数据" },
    has: { primary: "6,482 步", note: "32 分钟 · 模拟", settings: "有数据（模拟）", panel: "有数据" },
    loading: { primary: "读取中", note: "正在读取模拟数据", settings: "读取中", panel: "读取中" },
    error: { primary: "读取失败", note: "可重试 · 不记为 0", settings: "读取失败（模拟）", panel: "读取失败" }
  }[state.scenario.health] ?? { primary: "暂无数据", note: "不推测为 0", settings: "无数据", panel: "无数据" };
}

function syncStatus() {
  $("#tzValue").textContent = state.scenario.timezone;
  const reminderText = permissionLabel(state.scenario.permission);
  $("#permValue").textContent = reminderText;
  $("#permValue").style.color = state.scenario.permission === "granted" ? "" : "var(--red)";
  const musicText = permissionLabel(state.scenario.musicPermission);
  if ($("#musicValue")) {
    $("#musicValue").textContent = musicText;
    $("#musicValue").style.color = state.scenario.musicPermission === "granted" ? "" : "var(--red)";
  }
  const calendarReadText = permissionLabel(state.scenario.calendarRead);
  const calendarWriteText = permissionLabel(state.scenario.calendarWrite);
  if ($("#calendarReadValue")) {
    $("#calendarReadValue").textContent = calendarReadText;
    $("#calendarReadValue").style.color = state.scenario.calendarRead === "granted" ? "" : "var(--red)";
  }
  if ($("#calendarWriteValue")) {
    $("#calendarWriteValue").textContent = calendarWriteText;
    $("#calendarWriteValue").style.color = state.scenario.calendarWrite === "granted" ? "" : "var(--red)";
  }
  $("#netValue").textContent = state.scenario.network === "online" ? "在线" : "断网";
  $("#netValue").style.color = state.scenario.network === "online" ? "" : "var(--red)";
  const health = healthSummary();
  $("#healthValue").textContent = health.panel;
  $("#healthValue").style.color = state.scenario.health === "error" ? "var(--red)" : "";
  $("#countValue").textContent = String(state.reminders.length);
  const pill = $("#modePill");
  if (state.backend.enabled) {
    pill.textContent = state.backend.modelMode === "deepseek" ? "DeepSeek" : "Backend Mock";
    pill.className = "pill ok";
  } else if (state.backend.status === "error") {
    pill.textContent = "后端不可用";
    pill.className = "pill warn";
  } else {
    pill.textContent = state.scenario.network === "online" ? "Mock" : "Offline";
    pill.className = `pill ${state.scenario.network === "online" ? "ok" : "warn"}`;
  }
  const backendValue = $("#backendValue");
  if (backendValue) backendValue.textContent = backendStatusText();

  const setReminder = $("#setReminder");
  if (setReminder) {
    setReminder.textContent = state.scenario.permission === "granted" ? "已允许 · 可创建" : `${reminderText} · 不可创建`;
    setReminder.style.color = state.scenario.permission === "granted" ? "" : "var(--red)";
  }
  const setCalendarRead = $("#setCalendarRead");
  if (setCalendarRead) {
    setCalendarRead.textContent = state.scenario.calendarRead === "granted" ? "已允许 · 可读取" : `${calendarReadText} · 不可读取`;
    setCalendarRead.style.color = state.scenario.calendarRead === "granted" ? "" : "var(--red)";
  }
  const setCalendarWrite = $("#setCalendarWrite");
  if (setCalendarWrite) {
    setCalendarWrite.textContent = state.scenario.calendarWrite === "granted" ? "已允许 · 可创建" : `${calendarWriteText} · 不可创建`;
    setCalendarWrite.style.color = state.scenario.calendarWrite === "granted" ? "" : "var(--red)";
  }
  const setHealth = $("#setHealth");
  if (setHealth) {
    setHealth.textContent = health.settings;
    setHealth.style.color = state.scenario.health === "error" ? "var(--red)" : "";
  }
  const setMusic = $("#setMusic");
  if (setMusic) {
    setMusic.textContent =
      state.scenario.musicPermission === "granted" ? "已允许 · 模拟" : `${musicText} · 不可用`;
    setMusic.style.color = state.scenario.musicPermission === "granted" ? "" : "var(--red)";
  }
  const homeHealthStrong = $("#homeHealthStrong");
  if (homeHealthStrong) homeHealthStrong.textContent = health.primary;
  const homeHealthNote = $("#homeHealthNote");
  if (homeHealthNote) homeHealthNote.textContent = health.note;
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
  let parsedMinute = 0;
  let parsedPeriod = null;
  let dateParts = null;

  if (dateMatch || timeMatch) {
    const dayShift = dateMatch ? DATE_WORDS[dateMatch[1]] : 0;
    dateParts = addDaysToDate(base, dayShift);
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
      parsedMinute = minute;
      parsedPeriod = period;
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
  return { title, dueAt, needsTime, needsPeriod, parsedHour, parsedMinute, parsedPeriod, dateParts };
}

function parseTimeAnswer(text) {
  const periodMatch = /(凌晨|早上|上午|中午|下午|傍晚|晚上)/.exec(text);
  const timeMatch = /(凌晨|早上|上午|中午|下午|傍晚|晚上)?\s*(\d{1,2}|[零一二两三四五六七八九十]{1,3})\s*[点时](半|一刻|三刻|[零一二三四五]刻|\d{1,2}分)?/.exec(text);
  if (!timeMatch) {
    if (periodMatch) {
      return { hour: null, minute: 0, period: periodMatch[1], needsPeriod: false, periodOnly: true };
    }
    return null;
  }

  const period = timeMatch[1] ?? periodMatch?.[1] ?? null;
  let hour = chineseNumber(timeMatch[2]);
  const minuteToken = timeMatch[3] ?? null;
  let minute = 0;
  if (minuteToken === "半") minute = 30;
  else if (minuteToken === "一刻") minute = 15;
  else if (minuteToken === "三刻") minute = 45;
  else if (minuteToken?.endsWith("分")) minute = chineseNumber(minuteToken.slice(0, -1));
  else if (minuteToken?.endsWith("刻")) minute = chineseNumber(minuteToken.slice(0, -1)) * 15;
  if (period) hour = adjustHour(hour, period);
  return {
    hour,
    minute,
    period,
    needsPeriod: !period && hour >= 1 && hour <= 12,
    periodOnly: false
  };
}

function adjustHour(hour, period) {
  if (["下午", "傍晚", "晚上"].includes(period) && hour < 12) return hour + 12;
  if (period === "中午" && hour < 11) return hour + 12;
  if (["凌晨", "早上", "上午"].includes(period) && hour === 12) return 0;
  return hour;
}

function displayHour(hour) {
  return hour === 0 ? "12" : String(hour);
}

function reminderDueAt(dateParts, hour, minute) {
  const offset = offsetMinutesAt(nowDate(), state.scenario.timezone);
  return toLocalIso({ ...dateParts, hour, minute }, offset);
}

function formatDue(iso) {
  if (!iso) return "无日期";
  const parts = zonedParts(new Date(iso), state.scenario.timezone);
  return `${parts.month}月${parts.day}日 ${pad(parts.hour)}:${pad(parts.minute)}`;
}

function formatDueFull(iso) {
  if (!iso) return "无日期";
  const parts = zonedParts(new Date(iso), state.scenario.timezone);
  return `${parts.year}年${parts.month}月${parts.day}日 ${pad(parts.hour)}:${pad(parts.minute)}`;
}

function loadJson(key, fallback) {
  try {
    const value = JSON.parse(localStorage.getItem(key));
    return value ?? fallback;
  } catch {
    return fallback;
  }
}

function loadScenario() {
  return { ...DEFAULTS, ...loadJson(STORAGE_SCENARIO, {}) };
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

// ---------- 后端模型桥接 ----------

function defaultBackendBase() {
  const stored = localStorage.getItem("whale01.backend.base");
  if (stored) return stored.replace(/\/+$/, "");
  const host = location.hostname || "127.0.0.1";
  return `http://${host}:8787`;
}

function newConversationId() {
  const random = (crypto.randomUUID?.() ?? String(Math.random()).slice(2)).replaceAll("-", "").slice(0, 16);
  return `conv_web_${random}`;
}

function loadStoredConversationId() {
  const stored = localStorage.getItem(STORAGE_CONVERSATION);
  if (stored && /^conv_[a-z0-9_-]{8,64}$/.test(stored)) return stored;
  const created = newConversationId();
  try {
    localStorage.setItem(STORAGE_CONVERSATION, created);
  } catch {}
  return created;
}

function storeConversationId() {
  try {
    localStorage.setItem(STORAGE_CONVERSATION, state.backend.conversationId);
  } catch {}
}

function backendStatusText() {
  if (state.backend.enabled) {
    return state.backend.modelMode === "deepseek" ? "DeepSeek 真实模型" : "后端 Mock 模型";
  }
  if (state.backend.status === "connecting") return "连接中";
  if (state.backend.status === "error") return "后端不可用";
  return "本地演示";
}

function backendPermissions() {
  const scenario = state.scenario;
  return {
    reminder: scenario.permission,
    calendarRead: scenario.calendarRead,
    calendarWrite: scenario.calendarWrite,
    music: scenario.musicPermission,
    location: "granted",
    activityRead: scenario.health === "none" ? "unknown" : "granted",
    contacts: "unknown",
    messages: "unknown"
  };
}

function bindBackend() {
  $("#backendConnect")?.addEventListener("click", () => {
    if (state.backend.enabled) {
      disconnectBackend();
    } else {
      connectBackend({ silent: false });
    }
  });

  $("#backendNewConversation")?.addEventListener("click", () => {
    state.backend.conversationId = newConversationId();
    state.backend.activePending = null;
    storeConversationId();
    $$("#chat .backend-card[data-active='1']").forEach((card) => markCardResolved(card, "已作废 · 已开启新会话"));
    toast("已开启新的后端会话");
    if (state.backend.enabled) assistantSay("已开启新的后端会话，之前的上下文不再带入。");
  });

  chat.addEventListener("click", (event) => {
    const button = event.target.closest("[data-action^='backend-']");
    if (!button) return;
    const action = button.dataset.action;
    if (action === "backend-confirm") {
      sendBackendConfirm(button);
    } else if (action === "backend-say") {
      runTurn(button.dataset.text ?? "");
    } else if (action === "backend-retry") {
      runTurn(button.dataset.text ?? state.backend.lastText);
    } else if (action === "backend-reconnect") {
      connectBackend({ silent: false });
    }
  });
}

async function initBackend() {
  if (localStorage.getItem(STORAGE_BACKEND_OFF) === "1") {
    state.backend.status = "disabled";
    updateBackendUi();
    return;
  }
  await connectBackend({ silent: true });
}

async function connectBackend({ silent = false } = {}) {
  state.backend.status = "connecting";
  updateBackendUi();
  try {
    const health = await backendFetch("/healthz", { timeoutMs: 5000 });
    state.backend.modelMode = health.modelMode ?? null;
    state.backend.executionMode = health.executionMode ?? null;
    state.backend.adapterConfigured = Boolean(health.adapterConfigured);
    state.backend.status = "connected";
    const usable =
      health.modelMode === "deepseek" ? health.adapterConfigured : true;
    state.backend.enabled = usable && (silent ? health.modelMode === "deepseek" : true);
    if (state.backend.enabled) {
      try {
        localStorage.removeItem(STORAGE_BACKEND_OFF);
      } catch {}
      if (!silent) setCharacter("idle", "待命");
      toast(`已连接后端：${backendStatusText()} · 执行仍为模拟`);
      if (!silent) {
        assistantSay(
          health.modelMode === "deepseek"
            ? "已连接后端 DeepSeek：自然语言理解由真实模型完成，提醒、日历、音乐等工具仍是 Mock 模拟。"
            : "已连接后端 Mock 模型：这是规则模拟，不是真实 AI。"
        );
      }
    } else if (health.modelMode === "deepseek" && !health.adapterConfigured) {
      toast("后端已配置 DeepSeek 模式，但缺少 API Key");
    }
  } catch (error) {
    state.backend.status = "error";
    state.backend.enabled = false;
    if (!silent) toast(backendErrorMessage(error));
  }
  updateBackendUi();
  syncStatus();
}

function disconnectBackend() {
  state.backend.enabled = false;
  state.backend.status = "disabled";
  state.backend.activePending = null;
  try {
    localStorage.setItem(STORAGE_BACKEND_OFF, "1");
  } catch {}
  updateBackendUi();
  syncStatus();
  toast("已回到本地规则演示");
  assistantSay("已断开后端，回到本地规则演示。本地演示不会调用真实模型。");
}

function updateBackendUi() {
  const mode = $("#backendModeLabel");
  const model = $("#backendModelLabel");
  const exec = $("#backendExecLabel");
  const connect = $("#backendConnect");
  if (mode) {
    mode.textContent = state.backend.enabled
      ? state.backend.modelMode === "deepseek"
        ? "DeepSeek 真实模型"
        : "后端 Mock 模型"
      : state.backend.status === "error"
        ? "连接失败"
        : state.backend.status === "connecting"
          ? "正在连接"
          : "本地规则演示";
  }
  if (model) {
    if (!state.backend.modelMode) model.textContent = "未连接";
    else if (state.backend.modelMode === "deepseek") {
      model.textContent = state.backend.adapterConfigured ? "deepseek-chat" : "缺少 API Key";
    } else model.textContent = "mock（规则模型）";
  }
  if (exec) {
    exec.textContent = state.backend.executionMode === "mock" ? "Mock 模拟" : state.backend.executionMode ?? "本地模拟";
  }
  if (connect) {
    connect.textContent = state.backend.enabled
      ? "断开后端，回到本地演示"
      : state.backend.status === "connecting"
        ? "正在连接…"
        : "连接本地后端";
  }
  const value = $("#backendValue");
  if (value) value.textContent = backendStatusText();
}

async function backendFetch(path, { method = "GET", body = null, timeoutMs = 60000 } = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(`${state.backend.baseUrl}${path}`, {
      method,
      headers: body ? { "content-type": "application/json" } : undefined,
      body: body ? JSON.stringify(body) : undefined,
      signal: controller.signal
    });
    const text = await response.text();
    let json = null;
    try {
      json = text ? JSON.parse(text) : null;
    } catch {}
    if (!response.ok) {
      const error = new Error(json?.error?.message ?? `后端返回 HTTP ${response.status}`);
      error.code = json?.error?.code ?? "http_error";
      error.status = response.status;
      throw error;
    }
    if (json === null) {
      const error = new Error("后端返回了无法解析的内容");
      error.code = "invalid_response";
      throw error;
    }
    return json;
  } catch (error) {
    if (error.name === "AbortError") {
      const timeout = new Error("后端响应超时");
      timeout.code = "backend_timeout";
      throw timeout;
    }
    if (error instanceof TypeError) {
      const unreachable = new Error("无法连接后端，请确认 backend 已启动");
      unreachable.code = "backend_unreachable";
      throw unreachable;
    }
    throw error;
  } finally {
    clearTimeout(timer);
  }
}

async function runBackendTurn(text) {
  state.busy = true;
  state.backend.lastText = text;
  showChat();
  addUserMessage(text);

  if (state.scenario.network === "offline") {
    renderBackendError({ message: "网络不可用，无法调用后端模型。你的输入已保留。", code: "network_offline" }, text);
    state.busy = false;
    return;
  }

  setCharacter("thinking", "正在理解");
  const typing = addTypingBubble();
  let turnId = null;
  let streamNode = null;
  let streamText = "";
  try {
    if (await maybeCancelBackendPending(text)) {
      typing.remove();
      return;
    }
    const snapshot = await requestBackendTurn({
      text,
      onTurnId: (id) => {
        turnId = id;
      },
      onDelta: (chunk) => {
        if (!streamNode) {
          typing.remove();
          streamNode = appendStreamingBubble();
        }
        streamText += chunk;
        updateStreamingBubble(streamNode, streamText);
      }
    });
    typing.remove();
    if (snapshot.conversationId) {
      state.backend.conversationId = snapshot.conversationId;
      storeConversationId();
    }
    if (streamNode) finalizeStreamingBubble(streamNode, snapshot.reply || streamText);
    renderBackendSnapshot(snapshot, { skipReply: Boolean(streamNode) });
  } catch (error) {
    typing.remove();
    const interrupted = Boolean(turnId) && (error.streamStarted || error.code === "stream_interrupted");
    if (interrupted) {
      if (!streamNode) streamNode = appendStreamingBubble();
      setStreamingStatus(streamNode, "连接中断，正在从后台恢复本轮结果…");
      let snapshot = null;
      try {
        snapshot = await resumeBackendTurn(turnId, {
          onStatus: (status) => setStreamingStatus(streamNode, status)
        });
      } catch {}
      if (snapshot) {
        if (snapshot.conversationId) {
          state.backend.conversationId = snapshot.conversationId;
          storeConversationId();
        }
        finalizeStreamingBubble(streamNode, snapshot.reply || streamText);
        setStreamingStatus(streamNode, "");
        renderBackendSnapshot(snapshot, { skipReply: true });
        return;
      }
      setStreamingStatus(streamNode, "恢复超时：本轮可能仍在后台执行，稍后可重新连接查看。");
      setCharacter("error", "连接中断");
      return;
    }
    if (streamNode) finalizeStreamingBubble(streamNode, streamText);
    renderBackendError(error, text);
  } finally {
    state.busy = false;
  }
}

async function requestBackendTurn({ text, onTurnId, onDelta }) {
  let attempt = 0;
  while (true) {
    try {
      return await streamBackendTurn({ text, onTurnId, onDelta });
    } catch (error) {
      const retryable =
        !error.streamStarted &&
        (error.code === "backend_unreachable" ||
          error.status === 429 ||
          (typeof error.status === "number" && error.status >= 500));
      if (!retryable || attempt >= 3) throw error;
      attempt += 1;
      await sleep(Math.min(4000, 400 * 2 ** attempt) + Math.random() * 200);
    }
  }
}

async function streamBackendTurn({ text, onTurnId, onDelta }) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 150000);
  let sawData = false;
  let turnId = null;
  try {
    const response = await fetch(`${state.backend.baseUrl}/v1/turns`, {
      method: "POST",
      headers: { "content-type": "application/json", accept: "text/event-stream" },
      body: JSON.stringify({
        text,
        now: FIXED_NOW,
        timezone: state.scenario.timezone,
        conversationId: state.backend.conversationId,
        autoConfirm: false,
        permissions: backendPermissions()
      }),
      signal: controller.signal
    });
    if (!response.ok) {
      const bodyText = await response.text().catch(() => "");
      let json = null;
      try {
        json = bodyText ? JSON.parse(bodyText) : null;
      } catch {}
      const error = new Error(json?.error?.message ?? `后端返回 HTTP ${response.status}`);
      error.code = json?.error?.code ?? "http_error";
      error.status = response.status;
      error.streamStarted = sawData;
      throw error;
    }

    const contentType = response.headers.get("content-type") ?? "";
    if (!contentType.includes("text/event-stream")) {
      return await response.json();
    }

    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";
    let snapshot = null;
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      sawData = true;
      buffer += decoder.decode(value, { stream: true });
      let boundary = buffer.indexOf("\n\n");
      while (boundary >= 0) {
        const block = buffer.slice(0, boundary);
        buffer = buffer.slice(boundary + 2);
        boundary = buffer.indexOf("\n\n");
        const parsed = parseSseBlock(block);
        if (!parsed) continue;
        const data = parsed.data;
        if (parsed.name === "turn.snapshot" || (!data.type && data.status)) {
          snapshot = data;
          continue;
        }
        if (data.type === "turn.started") {
          turnId = data.turnId;
          onTurnId?.(turnId);
          continue;
        }
        if (data.type === "assistant.delta") {
          onDelta?.(String(data.payload?.text ?? ""));
        }
      }
    }

    if (snapshot) return snapshot;
    if (turnId) {
      const recovered = await resumeBackendTurn(turnId);
      if (recovered) return recovered;
    }
    const error = new Error("后端事件流意外中断");
    error.code = "stream_interrupted";
    error.streamStarted = sawData;
    error.turnId = turnId;
    throw error;
  } catch (error) {
    if (error.name === "AbortError") {
      const timeout = new Error("后端事件流超时");
      timeout.code = "backend_timeout";
      timeout.streamStarted = sawData;
      timeout.turnId = turnId;
      throw timeout;
    }
    if (error instanceof TypeError) {
      const unreachable = new Error("无法连接后端，请确认 backend 已启动");
      unreachable.code = "backend_unreachable";
      unreachable.streamStarted = sawData;
      unreachable.turnId = turnId;
      throw unreachable;
    }
    if (!error.code) error.code = "stream_interrupted";
    error.streamStarted = error.streamStarted ?? sawData;
    error.turnId = error.turnId ?? turnId;
    throw error;
  } finally {
    clearTimeout(timer);
  }
}

function parseSseBlock(block) {
  let name = "";
  const dataLines = [];
  for (const line of block.split(/\r?\n/)) {
    if (line.startsWith("event:")) name = line.slice(6).trim();
    else if (line.startsWith("data:")) dataLines.push(line.slice(5).trim());
  }
  if (!dataLines.length) return null;
  try {
    return { name, data: JSON.parse(dataLines.join("\n")) };
  } catch {
    return null;
  }
}

async function resumeBackendTurn(turnId, { onStatus } = {}) {
  const settled = new Set([
    "completed",
    "completed_with_limits",
    "failed",
    "cancelled",
    "superseded",
    "awaiting_confirmation",
    "awaiting_tool_results"
  ]);
  const deadline = Date.now() + 90000;
  let delay = 600;
  let attempt = 0;
  while (Date.now() < deadline) {
    attempt += 1;
    onStatus?.(`连接中断，正在恢复…（第 ${attempt} 次）`);
    try {
      const snapshot = await backendFetch(`/v1/turns/${encodeURIComponent(turnId)}`, { timeoutMs: 8000 });
      if (snapshot && settled.has(snapshot.status)) return snapshot;
    } catch (error) {
      if (!["backend_unreachable", "backend_timeout"].includes(error.code)) throw error;
    }
    await sleep(delay);
    delay = Math.min(4000, Math.round(delay * 1.6));
  }
  return null;
}

function appendStreamingBubble() {
  const node = document.createElement("div");
  node.className = "bubble streaming";
  node.innerHTML = `<div class="stream-text"></div><p class="hint stream-status" hidden></p>`;
  appendAssistantNode(node);
  return node;
}

function updateStreamingBubble(node, text) {
  const target = node?.querySelector(".stream-text");
  if (!target) return;
  target.innerHTML = renderMarkdownLite(text);
  scrollChat();
}

function setStreamingStatus(node, text) {
  const status = node?.querySelector(".stream-status");
  if (!status) return;
  status.hidden = !text;
  status.textContent = text ?? "";
  scrollChat();
}

function finalizeStreamingBubble(node, text) {
  if (!node) return;
  node.classList.remove("streaming");
  updateStreamingBubble(node, text);
}

async function maybeCancelBackendPending(text) {
  const pending = state.backend.activePending;
  if (!pending) return false;
  const trimmed = text.trim();
  const pureCancel =
    trimmed.length <= 15 &&
    !/[，,；;]/.test(trimmed) &&
    !/(查一下|查查|看看|天气|日程|播放|听歌|导航|发消息|帮我)/.test(trimmed) &&
    /^(算了|取消|不用了|先不|不弄了|别弄了)/.test(trimmed);
  if (!pureCancel) return false;
  try {
    const snapshot = await backendFetch(`/v1/turns/${encodeURIComponent(pending.turnId)}/confirm`, {
      method: "POST",
      timeoutMs: 60000,
      body: { operationId: pending.operationId, confirmed: false }
    });
    const card = $(`#chat .backend-card[data-op='${pending.operationId}']`);
    markCardResolved(card, "已取消");
    state.backend.activePending = null;
    renderBackendSnapshot(snapshot);
    return true;
  } catch (error) {
    toast(backendErrorMessage(error));
    return false;
  }
}

function addTypingBubble() {
  const wrapper = document.createElement("div");
  wrapper.className = "msg assistant";
  wrapper.innerHTML = `<span class="msg-avatar">${avatarMarkup()}</span><div class="bubble"><span class="typing"><i></i><i></i><i></i></span></div>`;
  chat.append(wrapper);
  scrollChat();
  return wrapper;
}

function renderBackendSnapshot(snapshot, { skipReply = false } = {}) {
  if (Array.isArray(snapshot.events)) {
    snapshot.events.forEach((event) => {
      appendEventLog(event);
      if (
        event.type === "tool.result" &&
        event.payload?.tool === "create_reminder" &&
        event.payload?.status === "success"
      ) {
        recordBackendReminder(event.payload.operationId, event.payload.data ?? {});
      }
    });
  }

  const cancelled = (snapshot.events ?? []).find(
    (event) =>
      event.type === "tool.result" &&
      event.payload?.tool === "cancel_active_task" &&
      event.payload?.status === "success"
  );
  if (cancelled && state.backend.activePending) {
    const card = $(`#chat .backend-card[data-op='${state.backend.activePending.operationId}']`);
    markCardResolved(card, "已取消");
    state.backend.activePending = null;
  }

  if (snapshot.status === "failed") {
    const failure = (snapshot.events ?? []).find((event) => event.type === "turn.failed");
    renderBackendError(
      {
        code: failure?.payload?.code ?? "model_error",
        message: failure?.payload?.message ?? "模型调用失败"
      },
      state.backend.lastText
    );
    setCharacter("error", "服务失败");
    return;
  }

  if (snapshot.reply && !skipReply) renderBackendReply(snapshot.reply);

  const pending = snapshot.pending ?? [];
  if (snapshot.status === "awaiting_confirmation" && pending.length) {
    pending.forEach((item) => renderBackendPending(item, snapshot.turnId));
    state.backend.activePending = { turnId: snapshot.turnId, operationId: pending[0].operationId };
    setCharacter("waiting", "等待确认");
    return;
  }

  renderBackendEvents(snapshot);
  state.backend.activePending = null;

  if (snapshot.status === "completed_with_limits") {
    const limit = (snapshot.events ?? []).find((event) => event.type === "turn.limit_reached");
    assistantSay(limit?.payload?.message ?? "本轮达到执行上限，任务尚未完成。");
    setCharacter("error", "达到上限");
    return;
  }
  if (snapshot.status === "superseded") {
    toast("旧任务已被新的修改取代");
    setCharacter("idle", "待命");
    return;
  }
  setCharacter("idle", "待命");
}

function renderBackendReply(text) {
  const node = document.createElement("div");
  node.className = "bubble";
  node.innerHTML = renderMarkdownLite(text);
  appendAssistantNode(node);
}

function renderMarkdownLite(text) {
  const lines = String(text ?? "").split(/\r?\n/);
  let html = "";
  let list = [];
  const flush = () => {
    if (!list.length) return;
    html += `<div class="md-list">${list
      .map((item) => `<span>${escapeHtml(item).replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")}</span>`)
      .join("")}</div>`;
    list = [];
  };
  for (const raw of lines) {
    const line = raw.trim();
    if (!line) {
      flush();
      continue;
    }
    const bullet = /^[-•]\s+(.*)$/.exec(line);
    if (bullet) {
      list.push(bullet[1]);
      continue;
    }
    flush();
    const safe = escapeHtml(line).replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>");
    html += `<p class="md-line">${safe}</p>`;
  }
  flush();
  return html || escapeHtml(text ?? "");
}

function renderBackendPending(pending, turnId) {
  const title = pending.arguments?.title ?? pending.arguments?.placeId ?? pending.tool;
  markSupersededCards(pending.tool, title, pending.operationId);

  const node = document.createElement("div");
  node.className = "bubble backend-card";
  node.dataset.tool = pending.tool;
  node.dataset.title = String(title);
  node.dataset.op = pending.operationId;
  node.dataset.turn = turnId;
  node.dataset.active = "1";
  node.innerHTML = `
    <div class="backend-card-head">
      <strong>${escapeHtml(backendToolLabel(pending.tool))}</strong>
      <span class="pill warn">模拟 · 待确认</span>
    </div>
    <div class="backend-rows">${backendArgRows(pending)}</div>
    <p class="hint">确认后由后端 Mock 执行，不会写入真实系统或发出声音。</p>
    <div class="quick-replies">
      <button type="button" data-action="backend-confirm" data-confirm="0">取消</button>
      <button type="button" data-action="backend-confirm" data-confirm="1">确认执行</button>
    </div>`;
  appendAssistantNode(node);
}

function backendArgRows(pending) {
  const args = pending.arguments ?? {};
  if (pending.tool === "create_reminder") {
    return [
      ["事项", args.title],
      ["时间", args.dueAt ? formatDueFull(args.dueAt) : "无日期待办"],
      ["时区", displayZone(args.timezone)]
    ].map(([label, value]) => backendRow(label, value)).join("");
  }
  if (pending.tool === "create_calendar_event") {
    return [
      ["日程", args.title],
      ["开始", formatDueFull(args.startAt)],
      ["结束", formatDueFull(args.endAt)],
      ["日历", args.calendarId ?? "个人"]
    ].map(([label, value]) => backendRow(label, value)).join("");
  }
  if (pending.tool === "open_navigation") {
    return [
      ["地点", args.placeId],
      ["方式", args.mode === "driving" ? "驾车" : args.mode ?? "步行"]
    ].map(([label, value]) => backendRow(label, value)).join("");
  }
  if (pending.tool === "prepare_message") {
    return [
      ["渠道", args.channel === "sms" ? "短信" : "邮件"],
      ["收件人", args.recipientId],
      ["正文", args.body]
    ].map(([label, value]) => backendRow(label, value)).join("");
  }
  return Object.entries(args)
    .map(([key, value]) => backendRow(key, typeof value === "object" ? JSON.stringify(value) : value))
    .join("");
}

function backendRow(label, value) {
  return `<div class="backend-row"><span>${escapeHtml(String(label))}</span><span>${escapeHtml(String(value ?? "—"))}</span></div>`;
}

function markSupersededCards(tool, title, exceptOperationId) {
  $$("#chat .backend-card[data-active='1']").forEach((card) => {
    if (card.dataset.tool === tool && card.dataset.title === String(title) && card.dataset.op !== exceptOperationId) {
      markCardResolved(card, "已作废 · 旧确认失效");
    }
  });
}

function markCardResolved(card, text) {
  if (!card) return;
  card.classList.add("is-resolved");
  card.removeAttribute("data-active");
  card.querySelectorAll("button").forEach((button) => {
    button.disabled = true;
  });
  let status = card.querySelector(".backend-status");
  if (!status) {
    status = document.createElement("p");
    status.className = "backend-status";
    card.append(status);
  }
  status.textContent = text;
}

async function sendBackendConfirm(button) {
  const card = button.closest(".backend-card");
  if (!card) return;
  const operationId = card.dataset.op;
  const turnId = card.dataset.turn;
  const confirmed = button.dataset.confirm === "1";
  card.querySelectorAll("button").forEach((item) => {
    item.disabled = true;
  });
  let status = card.querySelector(".backend-status");
  if (!status) {
    status = document.createElement("p");
    status.className = "backend-status";
    card.append(status);
  }
  status.textContent = confirmed ? "正在执行…" : "正在取消…";
  try {
    const snapshot = await backendFetch(`/v1/turns/${encodeURIComponent(turnId)}/confirm`, {
      method: "POST",
      timeoutMs: 60000,
      body: { operationId, confirmed }
    });
    markCardResolved(card, confirmed ? "已确认" : "已取消");
    if (state.backend.activePending?.operationId === operationId) state.backend.activePending = null;
    renderBackendSnapshot(snapshot);
  } catch (error) {
    if (error.code === "operation_superseded" || /取代|不能确认/.test(error.message)) {
      markCardResolved(card, "已作废 · 旧确认失效");
      toast("旧确认已失效，请使用新的预览");
      return;
    }
    card.querySelectorAll("button").forEach((item) => {
      item.disabled = false;
    });
    status.textContent = `执行失败：${backendErrorMessage(error)}`;
  }
}

function renderBackendEvents(snapshot) {
  const events = (snapshot.events ?? []).filter((event) =>
    ["tool.result", "tool.rejected", "tool.superseded"].includes(event.type)
  );
  for (const event of events) {
    const card = backendToolCard(event);
    if (card) appendAssistantNode(card);
  }
}

function backendToolCard(event) {
  const payload = event.payload ?? {};
  if (event.type === "tool.superseded") {
    const node = document.createElement("div");
    node.className = "bubble backend-card is-resolved";
    node.innerHTML = `<div class="backend-card-head"><strong>${escapeHtml(backendToolLabel(payload.tool))}</strong><span class="pill warn">已作废</span></div><p class="hint">旧确认已被新的修改取代，不会执行。</p>`;
    return node;
  }

  const status = payload.status ?? (event.type === "tool.rejected" ? "rejected" : "failed");
  const success = status === "success";
  const badge = success
    ? `<span class="pill ok">模拟执行</span>`
    : status === "needs_authorization"
      ? `<span class="pill warn">需要授权</span>`
      : status === "cancelled"
        ? `<span class="pill warn">已取消</span>`
        : `<span class="pill warn">未完成</span>`;

  let rows = "";
  if (payload.data) rows = backendToolRows(payload.tool, payload.data);
  if (payload.error) {
    rows += backendRow("原因", payload.error.message ?? payload.error.code ?? "未知错误");
  }

  let extras = "";
  if (payload.tool === "search_music_library" && payload.data?.tracks?.length) {
    extras = payload.data.tracks
      .map(
        (track, index) =>
          `<div class="backend-track"><div><strong>${escapeHtml(track.title)}</strong><small>${escapeHtml(track.artist)} · ${formatSeconds(track.durationSec)}</small></div><button type="button" data-action="backend-say" data-text="播放第${index + 1}首">播放</button></div>`
      )
      .join("");
  } else if (["play_music", "pause_music", "resume_music", "skip_music_track", "get_playback_state"].includes(payload.tool)) {
    extras = `<div class="quick-replies">
      ${payload.data?.state === "playing" ? `<button type="button" data-action="backend-say" data-text="暂停">暂停</button>` : ""}
      ${payload.data?.state === "paused" ? `<button type="button" data-action="backend-say" data-text="继续">继续</button>` : ""}
      <button type="button" data-action="backend-say" data-text="下一首">下一首</button>
    </div>`;
  } else if (payload.tool === "search_places" && payload.data?.places?.length) {
    extras = payload.data.places
      .map(
        (place, index) =>
          `<div class="backend-track"><div><strong>${escapeHtml(place.name)}</strong><small>${escapeHtml(place.category)} · ${place.distanceMeters} 米</small></div><button type="button" data-action="backend-say" data-text="带我去第${index + 1}家">导航</button></div>`
      )
      .join("");
  }

  const hint =
    status === "success"
      ? "Mock 执行结果，不代表真实系统已完成。"
      : status === "cancelled"
        ? "已取消，本次没有执行或写入。"
        : status === "needs_authorization"
          ? "需要先授权后再试，本次没有执行。"
          : "未执行成功，可换个说法或检查权限后重试。";

  const node = document.createElement("div");
  node.className = "bubble backend-card";
  node.innerHTML = `
    <div class="backend-card-head"><strong>${escapeHtml(backendToolLabel(payload.tool))}</strong>${badge}</div>
    ${rows ? `<div class="backend-rows">${rows}</div>` : ""}
    ${extras}
    <p class="hint">${hint}</p>`;
  return node;
}

function backendToolRows(tool, data) {
  if (tool === "create_reminder") {
    return [
      ["事项", data.title],
      ["时间", data.dueAt ? formatDueFull(data.dueAt) : "无日期待办"],
      ["列表", data.listName ?? "提醒事项"]
    ].map(([label, value]) => backendRow(label, value)).join("");
  }
  if (tool === "create_calendar_event") {
    return [
      ["日程", data.title],
      ["开始", formatDueFull(data.startAt)],
      ["结束", formatDueFull(data.endAt)],
      ["日历", data.calendarId ?? "个人"]
    ].map(([label, value]) => backendRow(label, value)).join("");
  }
  if (tool === "list_calendar_events") {
    if (!data.events?.length) return backendRow("结果", data.note ?? "该区间没有模拟日程");
    return data.events
      .map((event) => backendRow(formatDue(event.startAt), event.title))
      .join("");
  }
  if (tool === "get_weather") {
    return [
      ["城市", data.locationName],
      ["日期", data.date],
      ["天气", `${data.summary}（${data.condition}）`],
      ["气温", `${data.temperatureC?.min}–${data.temperatureC?.max}℃`],
      ["降雨", `${data.precipitationChance}%`],
      ["来源", "模拟天气"]
    ].map(([label, value]) => backendRow(label, value)).join("");
  }
  if (tool === "get_activity_summary") {
    return [
      ["状态", data.state === "no_data" ? "无数据" : data.state],
      ["说明", data.note ?? "不推测为 0"]
    ].map(([label, value]) => backendRow(label, value)).join("");
  }
  if (tool === "search_music_library") {
    return [
      ["候选", `${data.total ?? data.tracks?.length ?? 0} 首`],
      ["来源", "演示曲库 · 非 iPhone 音乐库"]
    ].map(([label, value]) => backendRow(label, value)).join("");
  }
  if (["play_music", "pause_music", "resume_music", "skip_music_track", "get_playback_state"].includes(tool)) {
    const stateText = { playing: "播放中", paused: "已暂停", stopped: "已停止" }[data.state] ?? data.state;
    return [
      ["状态", stateText],
      ["曲目", data.track ? `${data.track.title} · ${data.track.artist}` : "无"],
      ["音频", data.audioOutput ? "有输出" : "无真实音频"]
    ].map(([label, value]) => backendRow(label, value)).join("");
  }
  if (tool === "search_places") {
    return backendRow("结果", `${data.places?.length ?? 0} 个模拟地点`);
  }
  if (tool === "open_navigation") {
    return [
      ["状态", data.handoff === "opened_map" ? "已交接给地图（模拟）" : data.handoff],
      ["说明", data.note ?? "不代表已出发或抵达"]
    ].map(([label, value]) => backendRow(label, value)).join("");
  }
  if (tool === "prepare_message") {
    return [
      ["状态", "草稿预览"],
      ["正文", data.body]
    ].map(([label, value]) => backendRow(label, value)).join("");
  }
  if (tool === "summarize_shared_content") {
    return (data.points ?? []).map((point) => backendRow("要点", point)).join("");
  }
  if (tool === "cancel_active_task") {
    return [
      ["状态", "已取消"],
      ["任务", data.taskId ?? "未执行任务"]
    ].map(([label, value]) => backendRow(label, value)).join("");
  }
  return backendRow("返回", JSON.stringify(data).slice(0, 160));
}

function formatSeconds(value) {
  const total = Number(value ?? 0);
  if (!total) return "";
  return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`;
}

function backendToolLabel(tool) {
  return {
    create_reminder: "创建提醒",
    create_calendar_event: "创建日程",
    list_calendar_events: "查看日程",
    get_weather: "查询天气",
    get_activity_summary: "活动摘要",
    search_places: "搜索地点",
    open_navigation: "打开导航",
    summarize_shared_content: "分享摘要",
    prepare_message: "短信草稿",
    search_music_library: "搜索音乐",
    play_music: "播放音乐",
    pause_music: "暂停音乐",
    resume_music: "继续音乐",
    skip_music_track: "切换曲目",
    get_playback_state: "播放状态",
    cancel_active_task: "取消任务"
  }[tool] ?? tool;
}

function renderBackendError(error, retryText = "") {
  const message = backendErrorMessage(error);
  setCharacter("error", "服务失败");
  const node = document.createElement("div");
  node.className = "bubble";
  node.innerHTML = `<p>${escapeHtml(message)}</p>
    <p class="hint">模型失败不会静默切回本地规则，也不会把未完成说成已完成。</p>
    ${retryText ? `<div class="quick-replies"><button type="button" data-action="backend-retry" data-text="${escapeAttr(retryText)}">重试</button><button type="button" data-action="backend-reconnect">重新连接</button></div>` : ""}`;
  appendAssistantNode(node);
}

function backendErrorMessage(error) {
  const code = error?.code;
  if (code === "backend_unreachable") {
    return "无法连接本地后端。请在 backend 目录运行 node src/server.mjs，并确认 8787 端口可访问。";
  }
  if (code === "backend_timeout") return "后端响应超时。可以重试；这次没有生成任何结果。";
  if (code === "missing_api_key") return "后端缺少 DEEPSEEK_API_KEY，无法调用真实模型。";
  if (code === "rate_limited") return "模型服务额度或频率受限，请稍后重试。";
  if (code === "network_offline") return "网络不可用，无法调用后端模型。";
  if (code === "invalid_conversation_id" || code === "unknown_conversation") {
    return "会话标识无效，请开启新会话后重试。";
  }
  if (code === "operation_superseded") return "旧确认已失效，请使用新的预览。";
  return `后端处理失败：${error?.message ?? "未知错误"}`;
}

init();
