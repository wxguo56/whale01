import { createHash } from "node:crypto";
import { readTextBounded } from "./boundedContent.mjs";

const DEFAULT_FEEDS = [
  {
    id: "jiqizhixin",
    name: "机器之心",
    url: "https://www.jiqizhixin.com/rss",
    channels: ["ai"],
    requireAiKeyword: false
  },
  {
    id: "qbitai",
    name: "量子位",
    url: "https://www.qbitai.com/feed",
    channels: ["ai"],
    requireAiKeyword: false
  },
  {
    id: "ithome",
    name: "IT之家",
    url: "https://www.ithome.com/rss/",
    channels: ["ai", "headline"],
    requireAiKeyword: true
  },
  {
    id: "36kr",
    name: "36氪",
    url: "https://36kr.com/feed",
    channels: ["ai", "headline"],
    requireAiKeyword: true
  },
  {
    id: "bing-ai",
    name: "Bing 新闻",
    url: "https://www.bing.com/news/search?q=AI%20%E4%BA%BA%E5%B7%A5%E6%99%BA%E8%83%BD&format=rss&setlang=zh-cn",
    channels: ["ai"],
    requireAiKeyword: false
  },
  {
    id: "bing-headline",
    name: "Bing 新闻",
    url: "https://www.bing.com/news/search?q=%E4%BB%8A%E6%97%A5%E8%A6%81%E9%97%BB&format=rss&setlang=zh-cn",
    channels: ["headline"],
    requireAiKeyword: false
  },
  {
    id: "sina-china",
    name: "新浪新闻",
    url: "https://rss.sina.com.cn/news/china/focus15.xml",
    channels: ["headline"],
    requireAiKeyword: false
  },
  {
    id: "youxiputao",
    name: "游戏葡萄",
    url: "https://www.youxituoluo.com/feed",
    channels: ["game"],
    requireAiKeyword: false
  },
  {
    id: "youxichaguan",
    name: "游戏茶馆",
    url: "https://www.youxichaguan.com/feed",
    channels: ["game"],
    requireAiKeyword: false
  },
  {
    id: "chuapp",
    name: "触乐",
    url: "https://www.chuapp.com/feed",
    channels: ["game"],
    requireAiKeyword: false
  }
];

const AI_PATTERN = /(?:^|[^a-z])(ai|a\.i\.|agi|agent|llm|gpt|chatgpt|claude|gemini|deepseek|openai|anthropic|nvidia|transformer|diffusion|multimodal|大模型|人工智能|机器学习|深度学习|神经网络|智能体|生成式|多模态|算力|芯片)(?:$|[^a-z])/i;

export class NewsError extends Error {
  constructor(message, code = "news_unavailable", status = 502) {
    super(message);
    this.name = "NewsError";
    this.code = code;
    this.status = status;
  }
}

export class NewsService {
  constructor({
    fetchImpl = globalThis.fetch,
    now = () => new Date(),
    feeds = DEFAULT_FEEDS,
    cacheTtlMs = 5 * 60 * 1000,
    timeoutMs = 8000
  } = {}) {
    if (typeof fetchImpl !== "function") throw new TypeError("NewsService 需要 fetch");
    this.fetchImpl = fetchImpl;
    this.now = now;
    this.feeds = feeds;
    this.cacheTtlMs = cacheTtlMs;
    this.timeoutMs = timeoutMs;
    this.cache = new Map();
    this.feedCache = new Map();
    this.feedPending = new Map();
  }

  async list({ channel = "ai", limit = 20, force = false } = {}) {
    const normalizedChannel = ["ai", "headline", "game"].includes(channel) ? channel : null;
    if (!normalizedChannel) throw new NewsError("channel 只能是 ai、headline 或 game", "invalid_channel", 400);
    const safeLimit = clampInteger(limit, 1, 40, 20);
    const cacheKey = `${normalizedChannel}:${safeLimit}`;
    const cached = this.cache.get(cacheKey);
    const nowMs = this.now().getTime();
    if (!force && cached && nowMs - cached.cachedAt < this.cacheTtlMs) {
      return { ...cached.value, cached: true };
    }

    const feeds = this.feeds.filter((feed) => feed.channels.includes(normalizedChannel));
    const settled = await Promise.allSettled(feeds.map((feed) => this.#fetchFeed(feed, normalizedChannel, force)));
    const items = [];
    const sources = [];
    const unavailableSources = [];

    settled.forEach((result, index) => {
      const feed = feeds[index];
      if (result.status === "fulfilled") {
        sources.push(feed.name);
        items.push(...result.value);
      } else {
        unavailableSources.push(feed.name);
      }
    });

    const unique = deduplicate(items)
      .sort((left, right) => (right.publishedAt ?? "").localeCompare(left.publishedAt ?? "") || left.link.localeCompare(right.link))
      .slice(0, safeLimit)
      .map((item, index) => ({ ...item, rank: index + 1 }));

    if (!unique.length) {
      throw new NewsError(
        unavailableSources.length
          ? `资讯源暂时不可用：${[...new Set(unavailableSources)].join("、")}`
          : "资讯源没有返回可用条目",
        "news_sources_unavailable"
      );
    }

    const value = {
      channel: normalizedChannel,
      updatedAt: items.map(item => item.fetchedAt).sort()[0],
      cached: false,
      sources: [...new Set(sources)].sort(),
      unavailableSources: [...new Set(unavailableSources)].sort(),
      items: unique
    };
    this.cache.set(cacheKey, { cachedAt: nowMs, value });
    return value;
  }

  async #fetchXml(feed, force) {
    const key = feed.url;
    if (this.feedPending.has(key)) return this.feedPending.get(key);
    const cached = this.feedCache.get(key);
    if (!force && cached && this.now().getTime() - cached.at < this.cacheTtlMs) return cached;
    const pending = (async () => {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), this.timeoutMs);
      try {
        const response = await this.fetchImpl(feed.url, {
          headers: { accept: "application/rss+xml,application/atom+xml,text/xml", "user-agent": "WhaleAgent/0.6" },
          signal: controller.signal, cache: "no-store"
        });
        if (!response.ok) throw new Error(`${feed.name} HTTP ${response.status}`);
        const xml = await readTextBounded(response);
        const entry = { xml, at: this.now().getTime(), fetchedAt: this.now().toISOString() };
        this.feedCache.set(key, entry);
        return entry;
      } finally { clearTimeout(timer); }
    })();
    this.feedPending.set(key, pending);
    try { return await pending; }
    finally { this.feedPending.delete(key); }
  }

  async #fetchFeed(feed, channel, force) {
      const { xml, fetchedAt } = await this.#fetchXml(feed, force);
      const parsed = parseFeed(xml);
      const items = [];
      for (const entry of parsed) {
        const title = cleanText(entry.title);
        const link = cleanLink(entry.link);
        if (!title || !link) continue;
        const summary = truncate(cleanText(entry.summary), 220);
        const haystack = `${title}\n${summary}`;
        if (feed.requireAiKeyword && channel === "ai" && !AI_PATTERN.test(haystack)) continue;
        items.push({
          id: createHash("sha1").update(`${feed.id}|${link}`).digest("hex").slice(0, 16),
          title,
          summary,
          source: feed.name,
          link,
          publishedAt: normalizeDate(entry.publishedAt),
          fetchedAt,
          channel
        });
      }
      return items.slice(0, 30);
  }
}

export function parseFeed(xml) {
  if (typeof xml !== "string" || !xml.trim()) return [];
  const blocks = [];
  for (const match of xml.matchAll(/<item\b[^>]*>([\s\S]*?)<\/item>/gi)) blocks.push(match[1]);
  if (!blocks.length) {
    for (const match of xml.matchAll(/<entry\b[^>]*>([\s\S]*?)<\/entry>/gi)) blocks.push(match[1]);
  }
  return blocks.map((block) => ({
    title: pickTag(block, "title"),
    link: pickLink(block),
    summary: pickTag(block, "description") || pickTag(block, "summary") || pickTag(block, "content:encoded") || pickTag(block, "content"),
    publishedAt: pickTag(block, "pubDate") || pickTag(block, "published") || pickTag(block, "updated") || pickTag(block, "dc:date")
  }));
}

function pickTag(block, name) {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = new RegExp(`<${escaped}(?:\\s[^>]*)?>([\\s\\S]*?)<\\/${escaped}>`, "i").exec(block);
  return match ? match[1] : "";
}

function pickLink(block) {
  const direct = pickTag(block, "link");
  if (direct.trim()) return direct;
  const href = /<link\b[^>]*\bhref\s*=\s*["']([^"']+)["'][^>]*\/?>/i.exec(block);
  if (href) return href[1];
  const guid = /<guid\b[^>]*>([\s\S]*?)<\/guid>/i.exec(block);
  return guid ? guid[1] : "";
}

export function cleanText(value) {
  if (!value) return "";
  let text = String(value);
  // RSS 摘要常见多层转义：CDATA 里再套 &lt;p&gt;，甚至 &amp;lt;。
  // 每轮先解实体再剥标签，多轮直到稳定，避免把 HTML 当正文展示。
  for (let round = 0; round < 3; round += 1) {
    text = text.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1");
    text = text.replace(/<script\b[\s\S]*?<\/script>/gi, " ");
    text = text.replace(/<style\b[\s\S]*?<\/style>/gi, " ");
    text = text.replace(/<!--[\s\S]*?-->/g, " ");
    text = text.replace(/<\/?[a-z][^>]*>/gi, " ");
    text = decodeEntities(text);
  }
  text = text.replace(/<\/?[a-z][^>]*>/gi, " ");
  text = text.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u200b-\u200d\ufeff]/gi, " ");
  return text.replace(/\s+/g, " ").trim();
}

function cleanLink(value) {
  const text = cleanText(value);
  if (!/^https?:\/\//i.test(text)) return "";
  return text;
}

function decodeEntities(text) {
  const named = {
    amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'", nbsp: " ",
    ldquo: "“", rdquo: "”", lsquo: "‘", rsquo: "’", mdash: "—", ndash: "–", hellip: "…"
  };
  return text
    .replace(/&#x([0-9a-f]+);/gi, (_, hex) => safeCodePoint(parseInt(hex, 16)))
    .replace(/&#(\d+);/g, (_, dec) => safeCodePoint(parseInt(dec, 10)))
    .replace(/&([a-z]+);/gi, (match, name) => named[name.toLowerCase()] ?? match);
}

function safeCodePoint(code) {
  try {
    return String.fromCodePoint(code);
  } catch {
    return "";
  }
}

function normalizeDate(value) {
  const parsed = Date.parse(value);
  return Number.isNaN(parsed) ? null : new Date(parsed).toISOString();
}

function truncate(text, length) {
  return text.length > length ? `${text.slice(0, length - 1)}…` : text;
}

function deduplicate(items) {
  const seenLinks = new Set();
  const seenTitles = new Set();
  return items.filter((item) => {
    const titleKey = item.title.replace(/\s+/g, "").toLowerCase();
    if (seenLinks.has(item.link) || seenTitles.has(titleKey)) return false;
    seenLinks.add(item.link);
    seenTitles.add(titleKey);
    return true;
  });
}

function clampInteger(value, min, max, fallback) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.max(min, Math.min(max, Math.trunc(number)));
}
