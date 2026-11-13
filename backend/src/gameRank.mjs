const BOARDS = {
  free: {
    name: "免费榜",
    url: "https://itunes.apple.com/cn/rss/topfreeapplications/limit=100/genre=6014/json"
  },
  grossing: {
    name: "畅销榜",
    url: "https://itunes.apple.com/cn/rss/topgrossingapplications/limit=100/genre=6014/json"
  }
};

export const GAME_RANK_SOURCE = "Apple App Store 中国区公开榜单";

export class GameRankError extends Error {
  constructor(message, code = "game_rank_unavailable", status = 502) {
    super(message);
    this.name = "GameRankError";
    this.code = code;
    this.status = status;
  }
}

export class GameRankService {
  constructor({ fetchImpl = globalThis.fetch, now = () => new Date(), cacheTtlMs = 10 * 60 * 1000, timeoutMs = 8000 } = {}) {
    if (typeof fetchImpl !== "function") throw new TypeError("GameRankService 需要 fetch");
    this.fetchImpl = fetchImpl;
    this.now = now;
    this.cacheTtlMs = cacheTtlMs;
    this.timeoutMs = timeoutMs;
    this.cache = new Map();
  }

  async list({ board = "free", limit = 50, force = false } = {}) {
    if (!BOARDS[board]) throw new GameRankError("board 只能是 free 或 grossing", "invalid_board", 400);
    const safeLimit = clampInteger(limit, 1, 100, 50);
    const cacheKey = `${board}:${safeLimit}`;
    const cached = this.cache.get(cacheKey);
    const nowMs = this.now().getTime();
    if (!force && cached && nowMs - cached.cachedAt < this.cacheTtlMs) {
      return { ...cached.value, cached: true };
    }

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    let payload;
    try {
      const response = await this.fetchImpl(BOARDS[board].url, {
        headers: {
          accept: "application/json",
          "user-agent": "WhaleAgent/0.5"
        },
        signal: controller.signal
      });
      if (!response.ok) throw new GameRankError(`App Store 榜单 HTTP ${response.status}`);
      payload = await response.json();
    } catch (error) {
      if (error instanceof GameRankError) throw error;
      throw new GameRankError(`App Store 榜单暂时不可用：${error.message}`);
    } finally {
      clearTimeout(timer);
    }

    const entries = Array.isArray(payload?.feed?.entry)
      ? payload.feed.entry
      : payload?.feed?.entry
        ? [payload.feed.entry]
        : [];
    const items = entries
      .map((entry, index) => ({
        rank: index + 1,
        id: text(entry?.["id"]?.attributes?.["im:id"]) || text(entry?.["id"]?.label),
        name: text(entry?.["im:name"]?.label),
        artist: text(entry?.["im:artist"]?.label),
        category: text(entry?.category?.attributes?.label),
        icon: imageURL(entry?.["im:image"]),
        releaseDate: text(entry?.["im:releaseDate"]?.label),
        link: linkURL(entry?.link)
      }))
      .filter((item) => item.name && item.link)
      .slice(0, safeLimit);

    if (!items.length) throw new GameRankError("App Store 榜单没有返回可用条目", "game_rank_empty");

    const value = {
      board,
      boardName: BOARDS[board].name,
      updatedAt: this.now().toISOString(),
      source: GAME_RANK_SOURCE,
      note: "榜单随 App Store 实时变化，仅展示公开排名，不构成推荐。",
      cached: false,
      items
    };
    this.cache.set(cacheKey, { cachedAt: nowMs, value });
    return value;
  }
}

function text(value) {
  return typeof value === "string" ? value.trim() : "";
}

function imageURL(images) {
  if (!Array.isArray(images) || !images.length) return "";
  const last = images[images.length - 1];
  const url = text(last?.label).replace(/^http:\/\//i, "https://");
  return /^https:\/\//i.test(url) ? url : "";
}

function linkURL(link) {
  const candidate = Array.isArray(link) ? link[0] : link;
  const href = text(candidate?.attributes?.href);
  return /^https?:\/\//i.test(href) ? href.replace(/^http:\/\//i, "https://") : "";
}

function clampInteger(value, min, max, fallback) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.max(min, Math.min(max, Math.trunc(number)));
}
