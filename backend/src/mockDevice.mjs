import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import { permissionKeysForTool } from "./capabilities.mjs";

const MUSIC_LIBRARY = [
  { trackId: "music_demo_1", title: "夜航", artist: "鲸鱼示例乐队", album: "演示曲库 A", durationSec: 214 },
  { trackId: "music_demo_2", title: "雨天电台", artist: "林间信号", album: "演示曲库 B", durationSec: 242 },
  { trackId: "music_demo_3", title: "光的方向", artist: "示例歌手", album: "演示曲库 C", durationSec: 198 }
];

const DEMO_CALENDAR = [
  {
    eventId: "CAL-DEMO-1",
    title: "深色模式评审",
    startAt: "2026-11-09T16:00:00+08:00",
    endAt: "2026-11-09T17:00:00+08:00",
    calendarId: "work",
    location: "线上"
  },
  {
    eventId: "CAL-DEMO-2",
    title: "健身",
    startAt: "2026-11-10T16:00:00+08:00",
    endAt: "2026-11-10T17:00:00+08:00",
    calendarId: "personal",
    location: "社区健身房"
  }
];

export class MockDeviceExecutor {
  constructor({ remindersPath, calendarPath = null, now = () => new Date() } = {}) {
    this.remindersPath = remindersPath;
    this.calendarPath = calendarPath;
    this.now = now;
    this.musicSessions = new Map();
    this.extraTracks = new Map();
    this.memories = new Map();
  }

  seedTracks(tracks = []) {
    for (const track of tracks) {
      const trackId = track?.trackId ?? track?.id;
      if (!trackId) continue;
      this.extraTracks.set(trackId, {
        trackId,
        title: track.title ?? trackId,
        artist: track.artist ?? "评测夹具",
        album: track.album ?? "评测曲库",
        durationSec: track.durationSec ?? 0,
        simulated: true
      });
    }
  }

  seedPlayback(conversationId, playback = {}) {
    const queue = [...(playback.queue ?? [])];
    if (!queue.length && playback.trackId) queue.push(playback.trackId);
    const customTracks = new Map();
    for (const id of queue) {
      if (!MUSIC_LIBRARY.some((track) => track.trackId === id)) {
        customTracks.set(id, {
          trackId: id,
          title: id,
          artist: "评测夹具",
          durationSec: 0,
          simulated: true
        });
      }
    }
    const index = Math.max(0, queue.indexOf(playback.trackId));
    this.musicSessions.set(conversationId, {
      sessionId: playback.sessionId ?? `ms_seed_${Date.now().toString(36)}`,
      queue,
      index,
      state: playback.state ?? "playing",
      customTracks,
      startedAt: new Date().toISOString()
    });
    return this.#playbackState(conversationId).data;
  }

  capabilities() {
    return [
      "get_weather",
      "list_calendar_events",
      "find_free_slots",
      "create_calendar_event",
      "create_reminder",
      "list_reminders",
      "update_reminder",
      "delete_reminder",
      "update_calendar_event",
      "delete_calendar_event",
      "get_activity_summary",
      "get_current_location",
      "search_places",
      "open_navigation",
      "summarize_shared_content",
      "prepare_message",
      "search_music_library",
      "play_music",
      "pause_music",
      "resume_music",
      "skip_music_track",
      "get_playback_state",
      "list_memory",
      "set_memory",
      "delete_memory",
      "search_web",
      "fetch_web_content",
      "search_merchant_prices"
    ];
  }

  async execute({ tool, arguments: args = {}, operationId, turnId, conversationId = "conv_local", permissions = {} }) {
    const denied = permissionKeysForTool(tool).find((key) => permissions[key] === "denied");
    if (denied) {
      return {
        status: "needs_authorization",
        data: null,
        error: {
          code: "permission_denied",
          permission: denied,
          message: `需要先授权 ${denied}，本次未执行`
        },
        deduplicated: false
      };
    }

    switch (tool) {
      case "create_reminder":
        return this.#createReminder({ args, operationId, turnId });
      case "list_reminders":
        return this.#listReminders(args);
      case "update_reminder":
        return this.#updateReminder(args);
      case "delete_reminder":
        return this.#deleteReminder(args);
      case "list_calendar_events":
        return this.#listCalendarEvents(args);
      case "find_free_slots":
        return this.#findFreeSlots(args);
      case "create_calendar_event":
        return this.#createCalendarEvent({ args, operationId, turnId });
      case "update_calendar_event":
        return this.#updateCalendarEvent(args);
      case "delete_calendar_event":
        return this.#deleteCalendarEvent(args);
      case "get_weather":
        return this.#getWeather(args);
      case "get_current_location":
        return this.#getCurrentLocation();
      case "get_activity_summary":
        return this.#getActivitySummary();
      case "search_places":
        return this.#searchPlaces(args);
      case "open_navigation":
        return this.#openNavigation(args);
      case "summarize_shared_content":
        return this.#summarizeContent(args);
      case "prepare_message":
        return this.#prepareMessage(args);
      case "search_music_library":
        return this.#searchMusic(args);
      case "play_music":
        return this.#playMusic(args, conversationId);
      case "pause_music":
        return this.#pauseMusic(conversationId);
      case "resume_music":
        return this.#resumeMusic(conversationId);
      case "skip_music_track":
        return this.#skipMusic(args, conversationId);
      case "get_playback_state":
        return this.#playbackState(conversationId);
      case "list_memory":
        return this.#listMemory();
      case "set_memory":
        return this.#setMemory(args);
      case "delete_memory":
        return this.#deleteMemory(args);
      case "search_web":
        return this.#searchWeb(args);
      case "fetch_web_content":
        return this.#fetchWebContent(args);
      case "search_merchant_prices":
        return this.#searchMerchantPrices(args);
      default:
        return {
          status: "unsupported",
          data: null,
          error: { code: "mock_tool_not_implemented", message: `Mock 设备未实现 ${tool}` },
          deduplicated: false
        };
    }
  }

  async #createReminder({ args, operationId, turnId }) {
    if (args.dueAt && Number.isNaN(Date.parse(args.dueAt))) {
      return this.#failure("invalid_due_at", "dueAt 无法解析");
    }

    const records = await this.#readJson(this.remindersPath, []);
    const existing = records.find((record) => record.operationId === operationId);
    if (existing) {
      return this.#success(
        {
          recordId: existing.recordId,
          title: existing.title,
          dueAt: existing.dueAt,
          timezone: existing.timezone,
          listName: existing.listName,
          recurrence: existing.recurrence ?? null,
          simulated: true
        },
        true
      );
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
      recurrence: args.recurrence ?? null,
      createdAt: new Date().toISOString()
    };
    records.push(record);
    await this.#writeJson(this.remindersPath, records);

    return this.#success({
      recordId: record.recordId,
      title: record.title,
      dueAt: record.dueAt,
      timezone: record.timezone,
      listName: record.listName,
      recurrence: record.recurrence,
      simulated: true
    });
  }

  async #listReminders(args = {}) {
    const records = await this.#readJson(this.remindersPath, []);
    const includeCompleted = args.includeCompleted === true;
    const start = args.startAt ? Date.parse(args.startAt) : null;
    const end = args.endAt ? Date.parse(args.endAt) : null;
    const limit = Math.max(1, Math.min(args.limit ?? 50, 100));
    const reminders = records
      .filter((record) => includeCompleted || !record.completed)
      .filter((record) => {
        if (start === null && end === null) return true;
        if (!record.dueAt) return false;
        const due = Date.parse(record.dueAt);
        if (Number.isNaN(due)) return false;
        if (start !== null && due < start) return false;
        if (end !== null && due >= end) return false;
        return true;
      })
      .sort((left, right) => {
        if (!left.dueAt) return 1;
        if (!right.dueAt) return -1;
        return Date.parse(left.dueAt) - Date.parse(right.dueAt);
      })
      .slice(0, limit)
      .map((record) => ({
        recordId: record.recordId,
        title: record.title,
        dueAt: record.dueAt ?? null,
        completed: record.completed === true,
        listName: record.listName ?? "提醒事项",
        notes: record.notes ?? null
      }));
    return this.#success({
      reminders,
      count: reminders.length,
      source: "mock_reminders",
      simulated: true
    });
  }

  async #updateReminder(args = {}) {
    const records = await this.#readJson(this.remindersPath, []);
    const index = this.#findReminderIndex(records, args);
    if (index < 0) return this.#failure("reminder_not_found", "没有找到匹配的提醒，请先查询确认");
    const record = records[index];
    if (args.newTitle) record.title = args.newTitle;
    else if (args.recordId && args.title) record.title = args.title;
    if (args.dueAt !== undefined) {
      if (args.dueAt && Number.isNaN(Date.parse(args.dueAt))) {
        return this.#failure("invalid_due_at", "dueAt 无法解析");
      }
      record.dueAt = args.dueAt || null;
    }
    if (args.completed !== undefined) {
      record.completed = args.completed === true;
      record.completionDate = record.completed ? new Date().toISOString() : null;
    }
    if (args.notes !== undefined) record.notes = args.notes;
    if (args.listId) record.listName = args.listId;
    records[index] = record;
    await this.#writeJson(this.remindersPath, records);
    return this.#success({
      recordId: record.recordId,
      title: record.title,
      dueAt: record.dueAt ?? null,
      completed: record.completed === true,
      listName: record.listName ?? "提醒事项",
      simulated: true
    });
  }

  async #deleteReminder(args = {}) {
    const records = await this.#readJson(this.remindersPath, []);
    const index = this.#findReminderIndex(records, args);
    if (index < 0) return this.#failure("reminder_not_found", "没有找到匹配的提醒，请先查询确认");
    const [removed] = records.splice(index, 1);
    await this.#writeJson(this.remindersPath, records);
    return this.#success({
      recordId: removed.recordId,
      title: removed.title,
      deleted: true,
      simulated: true
    });
  }

  #findReminderIndex(records, args = {}) {
    if (args.recordId) return records.findIndex((record) => record.recordId === args.recordId);
    if (!args.title) return -1;
    const title = String(args.title).trim();
    const expectedDue = args.dueAt ? Date.parse(args.dueAt) : null;
    return records.findIndex((record) => {
      if ((record.title ?? "").trim() !== title) return false;
      if (expectedDue === null) return true;
      if (!record.dueAt) return false;
      return Math.abs(Date.parse(record.dueAt) - expectedDue) < 60_000;
    });
  }

  async #listCalendarEvents(args) {
    const start = Date.parse(args.startAt);
    const end = Date.parse(args.endAt);
    const stored = this.calendarPath ? await this.#readJson(this.calendarPath, []) : [];
    const events = [...DEMO_CALENDAR, ...stored].filter((event) => {
      const at = Date.parse(event.startAt);
      return at >= start && at < end;
    });
    return this.#success({
      events,
      count: events.length,
      source: "mock_demo_calendar",
      note: events.length ? "模拟日历数据，不代表已读取 iPhone 日历" : "模拟日历在该区间没有事件，不代表真实日历为空"
    });
  }

  async #findFreeSlots(args = {}) {
    const rangeStart = Date.parse(args.startAt);
    const rangeEnd = Date.parse(args.endAt);
    if (Number.isNaN(rangeStart) || Number.isNaN(rangeEnd) || rangeEnd <= rangeStart) {
      return this.#failure("invalid_time_range", "结束时间必须晚于开始时间");
    }
    const duration = Math.max(15, Math.min(args.durationMinutes ?? 60, 480));
    const buffer = Math.max(0, Math.min(args.bufferMinutes ?? 0, 120));
    const limit = Math.max(1, Math.min(args.limit ?? 8, 20));
    const [startHour, startMinute] = String(args.dayStart ?? "09:00").split(":").map(Number);
    const [endHour, endMinute] = String(args.dayEnd ?? "21:00").split(":").map(Number);
    if (![startHour, startMinute, endHour, endMinute].every(Number.isFinite)
        || startHour * 60 + startMinute >= endHour * 60 + endMinute) {
      return this.#failure("invalid_day_window", "dayStart 必须早于 dayEnd");
    }

    const stored = this.calendarPath ? await this.#readJson(this.calendarPath, []) : [];
    const events = [...DEMO_CALENDAR, ...stored].filter((event) => args.includeAllDay === true || !event.isAllDay);
    const slots = [];
    const cursor = new Date(rangeStart);
    cursor.setHours(0, 0, 0, 0);
    let inspectedDays = 0;
    while (cursor.getTime() < rangeEnd && slots.length < limit && inspectedDays < 14) {
      const windowStart = new Date(cursor);
      windowStart.setHours(startHour, startMinute, 0, 0);
      const windowEnd = new Date(cursor);
      windowEnd.setHours(endHour, endMinute, 0, 0);
      const clippedStart = Math.max(windowStart.getTime(), rangeStart);
      const clippedEnd = Math.min(windowEnd.getTime(), rangeEnd);
      if (clippedStart < clippedEnd) {
        const busy = events
          .map((event) => ({
            start: Math.max(clippedStart, Date.parse(event.startAt) - buffer * 60_000),
            end: Math.min(clippedEnd, Date.parse(event.endAt) + buffer * 60_000)
          }))
          .filter((interval) => Number.isFinite(interval.start) && Number.isFinite(interval.end) && interval.start < interval.end)
          .sort((left, right) => left.start - right.start);
        let freeStart = clippedStart;
        for (const interval of busy) {
          this.#appendMockSlots(freeStart, interval.start, duration, slots, limit);
          if (slots.length >= limit) break;
          freeStart = Math.max(freeStart, interval.end);
          if (freeStart >= clippedEnd) break;
        }
        if (slots.length < limit && freeStart < clippedEnd) {
          this.#appendMockSlots(freeStart, clippedEnd, duration, slots, limit);
        }
      }
      cursor.setDate(cursor.getDate() + 1);
      inspectedDays += 1;
    }

    return this.#success({
      slots,
      count: slots.length,
      durationMinutes: duration,
      bufferMinutes: buffer,
      timezone: args.timezone,
      dayStart: args.dayStart ?? "09:00",
      dayEnd: args.dayEnd ?? "21:00",
      source: "mock_calendar",
      simulated: true,
      note: "模拟空档，不代表真实日历可用性；创建前仍需确认"
    });
  }

  #appendMockSlots(startMs, endMs, duration, slots, limit) {
    const durationMs = duration * 60_000;
    let cursor = startMs;
    while (cursor + durationMs <= endMs && slots.length < limit) {
      slots.push({
        startAt: new Date(cursor).toISOString(),
        endAt: new Date(cursor + durationMs).toISOString(),
        durationMinutes: duration
      });
      cursor += durationMs;
    }
  }

  async #createCalendarEvent({ args, operationId, turnId }) {
    if (Number.isNaN(Date.parse(args.startAt)) || Number.isNaN(Date.parse(args.endAt))) {
      return this.#failure("invalid_time_range", "日程开始或结束时间无法解析");
    }
    if (Date.parse(args.endAt) <= Date.parse(args.startAt)) {
      return this.#failure("invalid_time_range", "结束时间必须晚于开始时间");
    }
    const records = this.calendarPath ? await this.#readJson(this.calendarPath, []) : [];
    const existing = records.find((record) => record.operationId === operationId);
    if (existing) {
      return this.#success({ ...existing, simulated: true }, true);
    }
    const event = {
      operationId,
      turnId,
      eventId: `CAL-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`,
      title: args.title,
      startAt: args.startAt,
      endAt: args.endAt,
      calendarId: args.calendarId ?? "personal",
      location: args.location ?? null,
      notes: args.notes ?? null,
      recurrence: args.recurrence ?? null,
      createdAt: new Date().toISOString()
    };
    if (this.calendarPath) {
      records.push(event);
      await this.#writeJson(this.calendarPath, records);
    }
    return this.#success({
      eventId: event.eventId,
      title: event.title,
      startAt: event.startAt,
      endAt: event.endAt,
      calendarId: event.calendarId,
      recurrence: event.recurrence,
      simulated: true
    });
  }

  async #updateCalendarEvent(args = {}) {
    const records = await this.#readJson(this.calendarPath, []);
    const index = records.findIndex((event) => event.eventId === args.eventId);
    if (index < 0) return this.#failure("event_not_found", "没有找到这条日程，请先查询确认");
    const event = records[index];
    if (args.title) event.title = args.title;
    if (args.startAt) {
      if (Number.isNaN(Date.parse(args.startAt))) return this.#failure("invalid_time_range", "startAt 无法解析");
      event.startAt = args.startAt;
    }
    if (args.endAt) {
      if (Number.isNaN(Date.parse(args.endAt))) return this.#failure("invalid_time_range", "endAt 无法解析");
      event.endAt = args.endAt;
    }
    if (Date.parse(event.endAt) <= Date.parse(event.startAt)) {
      return this.#failure("invalid_time_range", "结束时间必须晚于开始时间");
    }
    if (args.location !== undefined) event.location = args.location;
    if (args.notes !== undefined) event.notes = args.notes;
    if (args.calendarId) event.calendarId = args.calendarId;
    records[index] = event;
    await this.#writeJson(this.calendarPath, records);
    return this.#success({ ...event, simulated: true });
  }

  async #deleteCalendarEvent(args = {}) {
    const records = await this.#readJson(this.calendarPath, []);
    const index = records.findIndex((event) => event.eventId === args.eventId);
    if (index < 0) return this.#failure("event_not_found", "没有找到这条日程，请先查询确认");
    const [removed] = records.splice(index, 1);
    await this.#writeJson(this.calendarPath, records);
    return this.#success({
      eventId: removed.eventId,
      title: removed.title,
      deleted: true,
      simulated: true
    });
  }

  #getWeather(args) {
    const date = String(args.startAt).slice(0, 10);
    const city = args.locationName;
    if (date === "2026-11-10" && /杭州/.test(city)) {
      return this.#success({
        locationName: city,
        date,
        condition: "rainy",
        summary: "小雨",
        temperatureC: { min: 16, max: 21 },
        precipitationChance: 70,
        advice: "带伞",
        source: "mock_weather",
        simulated: true
      });
    }
    return this.#success({
      locationName: city,
      date,
      condition: "cloudy",
      summary: "多云",
      temperatureC: { min: 18, max: 24 },
      precipitationChance: 20,
      advice: "暂无强降雨信号",
      source: "mock_weather",
      simulated: true
    });
  }

  #getActivitySummary() {
    return this.#success({
      state: "no_data",
      metrics: {},
      note: "未读取健康数据，不能推断为 0 步",
      source: "mock_health",
      simulated: true
    });
  }

  #getCurrentLocation() {
    return this.#success({
      displayAddress: "浙江省杭州市西湖区（模拟位置）",
      name: "模拟位置",
      street: "文三路",
      district: "西湖区",
      city: "杭州市",
      province: "浙江省",
      country: "中国",
      latitude: 30.2741,
      longitude: 120.1551,
      accuracyMeters: 50,
      locatedAt: "2026-11-10T12:00:00+08:00",
      addressResolved: true,
      source: "mock_location",
      simulated: true,
      note: "Mock 环境返回模拟位置，不能当作真实手机定位。"
    });
  }

  #searchPlaces(args) {
    const query = args.query ?? "附近";
    const places = [
      { placeId: "place_cafe_1", name: "河岸咖啡", category: "咖啡", distanceMeters: 320, address: "示例路 18 号", simulated: true },
      { placeId: "place_cafe_2", name: "晴窗咖啡", category: "咖啡", distanceMeters: 540, address: "示例路 42 号", simulated: true },
      { placeId: "place_cafe_3", name: "慢岛咖啡馆", category: "咖啡", distanceMeters: 810, address: "滨江道 6 号", simulated: true }
    ];
    return this.#success({
      query,
      places: places.slice(0, args.limit ?? 3),
      source: "mock_places",
      note: "演示地点，不是实时地图结果",
      simulated: true
    });
  }

  #openNavigation(args) {
    return this.#success({
      handoff: "opened_map",
      placeId: args.placeId,
      mode: args.mode ?? "walking",
      note: "仅表示已把地点交给地图，未开始路线或抵达",
      simulated: true
    });
  }

  #summarizeContent(args) {
    return this.#success({
      contentId: args.contentId,
      points: ["这是一段模拟摘要，用于演示分享内容处理", "真实摘要需要可访问的内容来源"],
      source: "mock_content",
      simulated: true
    });
  }

  #prepareMessage(args) {
    return this.#success({
      draft: "prepared",
      channel: args.channel,
      recipientId: args.recipientId,
      body: args.body,
      note: "仅生成草稿预览，未打开系统界面，也未发送",
      simulated: true
    });
  }

  #searchMusic(args) {
    const query = (args.query ?? "").toLowerCase();
    const artist = (args.artist ?? "").toLowerCase();
    const tracks = [...MUSIC_LIBRARY, ...this.extraTracks.values()].filter((track) => {
      const matchesQuery = !query || track.title.toLowerCase().includes(query) || track.artist.toLowerCase().includes(query);
      const matchesArtist = !artist || track.artist.toLowerCase().includes(artist);
      return matchesQuery && matchesArtist;
    }).slice(0, args.limit ?? 5);
    return this.#success({
      tracks,
      total: tracks.length,
      library: "demo",
      note: tracks.length
        ? "演示曲库，未读取 iPhone 音乐库，也没有真实音源"
        : "演示曲库没有匹配曲目；不会自动转成云端付费播放",
      simulated: true
    });
  }

  #playMusic(args, conversationId) {
    let session = this.musicSessions.get(conversationId);
    const track =
      this.#libraryTrack(args.trackId) ??
      session?.customTracks?.get(args.trackId);
    if (!track) {
      return this.#failure("unknown_track", "曲目引用不存在或已过期，请重新选择");
    }
    if (!session) {
      session = { sessionId: `ms_${Date.now().toString(36)}`, queue: [], index: 0, state: "stopped" };
      this.musicSessions.set(conversationId, session);
    }
    if (args.queueIntent === "append") {
      session.queue.push(track.trackId);
    } else {
      session.queue = [track.trackId];
      session.index = 0;
    }
    session.state = "playing";
    session.startedAt = new Date().toISOString();
    return this.#success(this.#playbackPayload(session, track));
  }

  #pauseMusic(conversationId) {
    const session = this.musicSessions.get(conversationId);
    if (!session || session.state !== "playing") {
      return this.#failure("no_active_playback", "当前没有正在播放的音乐");
    }
    session.state = "paused";
    const track = this.#trackById(session, session.queue[session.index]);
    return this.#success(this.#playbackPayload(session, track));
  }

  #resumeMusic(conversationId) {
    const session = this.musicSessions.get(conversationId);
    if (!session || session.state !== "paused") {
      return this.#failure("no_paused_playback", "当前没有可继续的播放，需要先选曲");
    }
    session.state = "playing";
    const track = this.#trackById(session, session.queue[session.index]);
    return this.#success(this.#playbackPayload(session, track));
  }

  #skipMusic(args, conversationId) {
    const session = this.musicSessions.get(conversationId);
    if (!session || !session.queue.length) {
      return this.#failure("no_active_playback", "当前没有可切换的播放队列");
    }
    const nextIndex = session.index + (args.direction === "previous" ? -1 : 1);
    if (nextIndex < 0 || nextIndex >= session.queue.length) {
      const track = this.#trackById(session, session.queue[session.index]);
      return this.#success({ ...this.#playbackPayload(session, track), atBoundary: true });
    }
    session.index = nextIndex;
    const track = this.#trackById(session, session.queue[session.index]);
    return this.#success(this.#playbackPayload(session, track));
  }

  #playbackState(conversationId) {
    const session = this.musicSessions.get(conversationId);
    if (!session) {
      return this.#success({ state: "stopped", track: null, sessionId: null, simulated: true });
    }
    const track = this.#trackById(session, session.queue[session.index]);
    return this.#success(this.#playbackPayload(session, track));
  }

  #trackById(session, trackId) {
    if (!trackId) return null;
    return (
      this.#libraryTrack(trackId) ??
      session?.customTracks?.get(trackId) ??
      null
    );
  }

  #libraryTrack(trackId) {
    return MUSIC_LIBRARY.find((item) => item.trackId === trackId) ?? this.extraTracks.get(trackId) ?? null;
  }

  #playbackPayload(session, track) {
    return {
      sessionId: session.sessionId,
      state: session.state,
      track: track ?? null,
      positionSec: 0,
      queueLength: session.queue.length,
      simulated: true,
      audioOutput: false,
      note: "模拟播放状态，没有真实音频输出"
    };
  }

  #listMemory() {
    const memories = [...this.memories.values()];
    return this.#success({
      memories,
      count: memories.length,
      source: "mock_memory",
      simulated: true,
      note: "偏好只用于建议，不构成长期操作授权"
    });
  }

  #setMemory(args = {}) {
    const key = String(args.key ?? "").trim();
    const value = String(args.value ?? "").trim();
    if (!key || !value) return this.#failure("memory_invalid", "偏好名称和内容不能为空");
    if (key.length > 40 || value.length > 500) {
      return this.#failure("memory_invalid", "偏好名称最多 40 个字符，内容最多 500 个字符");
    }
    const id = key.toLowerCase();
    const memory = { id, key, value, updatedAt: new Date().toISOString(), simulated: true };
    this.memories.set(id, memory);
    return this.#success(memory);
  }

  #deleteMemory(args = {}) {
    const id = args.id ?? args.key ?? "";
    const deleted = this.memories.delete(String(id).toLowerCase());
    return this.#success({ id, deleted, simulated: true });
  }

  #searchWeb(args = {}) {
    const query = String(args.query ?? "").trim();
    if (!query) return this.#failure("empty_query", "搜索关键词不能为空");
    return this.#success({
      query,
      results: [
        {
          title: `模拟搜索结果：${query}`,
          url: "https://example.com/mock-result",
          snippet: "这是模拟结果，不代表真实网页内容；真实运行时会读取公开网页。"
        }
      ],
      count: 1,
      source: "mock_search",
      simulated: true,
      note: "模拟结果，不能作为价格或事实依据"
    });
  }

  #fetchWebContent(args = {}) {
    return this.#success({
      url: args.url,
      finalURL: args.url,
      title: "模拟网页",
      text: "这是模拟网页正文，仅用于演示工具闭环，不代表真实网页已经读取。",
      charCount: 30,
      truncated: false,
      source: "mock_web",
      simulated: true,
      note: "模拟正文，不能作为价格或事实依据"
    });
  }

  #searchMerchantPrices(args = {}) {
    const merchant = String(args.merchant ?? "").trim();
    if (!merchant) return this.#failure("empty_merchant", "商户名不能为空");
    return this.#success({
      merchant,
      branch: args.branch ?? null,
      city: args.city ?? null,
      evidence: [],
      evidenceCount: 0,
      sources: [],
      sourceCount: 0,
      priceDataAvailable: false,
      verified: false,
      source: "mock_merchant_price",
      simulated: true,
      note: "Mock 环境不提供真实价格来源。不得把本结果当作价格依据；真机会读取公开网页并区分分店匹配程度。"
    });
  }

  #success(data, deduplicated = false) {
    return { status: "success", data, error: null, deduplicated };
  }

  #failure(code, message) {
    return { status: "failed", data: null, error: { code, message }, deduplicated: false };
  }

  async #readJson(path, fallback) {
    if (!path) return fallback;
    try {
      const content = await readFile(path, "utf8");
      const parsed = JSON.parse(content);
      return Array.isArray(parsed) ? parsed : fallback;
    } catch (error) {
      if (error.code === "ENOENT") return fallback;
      throw error;
    }
  }

  async #writeJson(path, records) {
    if (!path) return;
    await mkdir(dirname(path), { recursive: true });
    const tempPath = `${path}.tmp`;
    await writeFile(tempPath, JSON.stringify(records, null, 2), "utf8");
    await rename(tempPath, path);
  }
}
