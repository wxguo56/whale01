const EASTMONEY_TOKEN = "D43BF722C8E33BDC906FB84D85E326E8";
const EASTMONEY_FIELDS = [
  "f43", "f44", "f45", "f46", "f47", "f48", "f50", "f57", "f58",
  "f59", "f60", "f86", "f116", "f117", "f162", "f168", "f169", "f170"
].join(",");

export class MarketError extends Error {
  constructor(message, code = "market_unavailable", status = 502) {
    super(message);
    this.name = "MarketError";
    this.code = code;
    this.status = status;
  }
}

export class MarketService {
  constructor({
    fetchImpl = globalThis.fetch,
    now = () => new Date(),
    quoteCacheTtlMs = 20_000,
    timeoutMs = 8000
  } = {}) {
    if (typeof fetchImpl !== "function") throw new TypeError("MarketService 需要 fetch");
    this.fetchImpl = fetchImpl;
    this.now = now;
    this.quoteCacheTtlMs = quoteCacheTtlMs;
    this.timeoutMs = timeoutMs;
    this.quoteCache = new Map();
  }

  async quotes(symbols, { allowPartial = true, force = false } = {}) {
    if (!Array.isArray(symbols) || !symbols.length) {
      throw new MarketError("symbols 至少需要一个股票代码", "invalid_symbols", 400);
    }
    if (symbols.length > 20) {
      throw new MarketError("一次最多查询 20 个股票", "too_many_symbols", 400);
    }
    const normalized = dedupeSymbols(symbols.map(normalizeSymbol).filter(Boolean));
    if (!normalized.length) {
      throw new MarketError("没有识别出有效的 A 股代码", "invalid_symbols", 400);
    }

    const nowMs = this.now().getTime();
    const quoteMap = new Map();
    const stale = [];
    for (const symbol of normalized) {
      const cached = this.quoteCache.get(symbol.symbol);
      if (!force && cached && nowMs - cached.cachedAt < this.quoteCacheTtlMs) quoteMap.set(symbol.symbol, cached.value);
      else stale.push(symbol);
    }

    const errors = [];
    if (stale.length) {
      try {
        const batch = await this.#tencentQuotes(stale);
        for (const [symbol, quote] of batch) {
          quoteMap.set(symbol, quote);
          quote.fetchedAt = this.now().toISOString();
          this.quoteCache.set(symbol, { cachedAt: this.now().getTime(), value: quote });
        }
      } catch (error) {
        errors.push({ symbols: stale.map((item) => item.symbol), message: error.message });
      }

      const missing = stale.filter((symbol) => !quoteMap.has(symbol.symbol));
      for (const symbol of missing) {
        try {
          const quote = await this.#eastmoneyQuote(symbol);
          quoteMap.set(symbol.symbol, quote);
          quote.fetchedAt = this.now().toISOString();
          this.quoteCache.set(symbol.symbol, { cachedAt: this.now().getTime(), value: quote });
        } catch (error) {
          errors.push({ symbol: symbol.symbol, message: error.message });
        }
      }
    }

    const quotes = normalized.map((symbol) => quoteMap.get(symbol.symbol)).filter(Boolean);
    if (!quotes.length) {
      throw new MarketError(
        errors[0]?.message ?? "行情源没有返回数据",
        "market_sources_unavailable"
      );
    }
    if (!allowPartial && quotes.length !== normalized.length) {
      throw new MarketError(`部分股票未取到行情：${normalized.filter((item) => !quoteMap.has(item.symbol)).map((item) => item.symbol).join("、")}`);
    }
    const source = [...new Set(quotes.map((quote) => quote.source))].join(" / ");
    return {
      updatedAt: quotes.map(quote => quote.fetchedAt).filter(Boolean).sort()[0] ?? null,
      delayedMinutes: null,
      source,
      quotes,
      errors
    };
  }

  async quote(input) {
    const symbol = normalizeSymbol(input);
    if (!symbol) throw new MarketError(`无法识别股票代码 ${input}`, "invalid_symbol", 400);
    const result = await this.quotes([symbol.symbol]);
    return result.quotes[0];
  }

  async resolve(query, { limit = 5 } = {}) {
    const text = String(query ?? "").trim();
    if (!text) throw new MarketError("query 不能为空", "invalid_query", 400);
    const direct = splitQueries(text).map(normalizeSymbol).filter(Boolean);
    if (direct.length) {
      const result = await this.quotes(direct.map((item) => item.symbol));
      return {
        query: text,
        matches: result.quotes.map((quote) => ({ symbol: quote.symbol, code: quote.code, name: quote.name, market: quote.market })),
        quotes: result.quotes,
        errors: result.errors,
        ambiguous: false
      };
    }

    const search = await this.search(text, { limit });
    if (!search.results.length) {
      throw new MarketError(`没有找到与「${text}」匹配的 A 股`, "stock_not_found", 404);
    }
    const result = await this.quotes([search.results[0].symbol]);
    return {
      query: text,
      matches: search.results,
      quotes: result.quotes,
      errors: result.errors,
      ambiguous: search.results.length > 1
    };
  }

  async search(query, { limit = 8 } = {}) {
    const text = String(query ?? "").trim();
    if (!text) throw new MarketError("query 不能为空", "invalid_query", 400);
    const safeLimit = Math.max(1, Math.min(20, Number(limit) || 8));
    try {
      const results = await this.#searchSina(text, safeLimit);
      if (results.length) return { query: text, results, source: "新浪财经证券搜索" };
    } catch {
      // The Tencent suggester below is deliberately tried before failing.
    }
    const results = await this.#searchTencent(text, safeLimit);
    return { query: text, results, source: "腾讯财经证券搜索" };
  }

  async kline(input, { days = 120 } = {}) {
    const symbol = input && typeof input === "object" && input.secid ? input : normalizeSymbol(input);
    if (!symbol) throw new MarketError(`无法识别股票代码 ${input}`, "invalid_symbol", 400);
    const safeDays = Math.max(5, Math.min(500, Number(days) || 120));
    const url = new URL("https://web.ifzq.gtimg.cn/appstock/app/fqkline/get");
    url.searchParams.set("param", `${symbol.symbol},day,,,${safeDays},qfq`);
    const json = await this.#fetchJson(url, "https://gu.qq.com/");
    const block = json?.data?.[symbol.symbol];
    if (!block) throw new MarketError(`腾讯财经未返回 ${symbol.symbol} 的日线`, "kline_not_found");
    const rows = block.qfqday ?? block.day ?? block.hfqday ?? [];
    const points = rows.map((row) => ({
      date: String(row[0] ?? ""),
      open: numeric(row[1]),
      close: numeric(row[2]),
      high: numeric(row[3]),
      low: numeric(row[4]),
      volumeLots: numeric(row[5]),
      volume: numeric(row[5]) === null ? null : numeric(row[5]) * 100,
      amount: null
    })).filter((point) => point.date && point.close !== null);
    const qt = block.qt?.[symbol.symbol];
    return {
      symbol: symbol.symbol,
      code: String(qt?.[2] ?? symbol.code),
      name: String(qt?.[1] ?? symbol.code),
      days: safeDays,
      source: "腾讯财经公开行情",
      delayedMinutes: null,
      points
    };
  }

  async intraday(input) {
    const symbol = input && typeof input === "object" && input.secid ? input : normalizeSymbol(input);
    if (!symbol) throw new MarketError(`无法识别股票代码 ${input}`, "invalid_symbol", 400);
    const url = new URL("https://web.ifzq.gtimg.cn/appstock/app/day/query");
    url.searchParams.set("code", symbol.symbol);
    const json = await this.#fetchJson(url, "https://gu.qq.com/");
    const block = json?.data?.[symbol.symbol];
    const days = Array.isArray(block?.data) ? block.data : [];
    const latest = [...days].sort((left, right) => String(right.date ?? "").localeCompare(String(left.date ?? "")))[0];
    if (!latest || !Array.isArray(latest.data) || !latest.data.length) {
      throw new MarketError(`腾讯财经未返回 ${symbol.symbol} 的分时数据`, "intraday_not_found");
    }
    const points = latest.data.map((line) => {
      const parts = String(line).trim().split(/\s+/);
      const time = String(parts[0] ?? "");
      return {
        time: time.length === 4 ? `${time.slice(0, 2)}:${time.slice(2)}` : time,
        price: numeric(parts[1]),
        volumeLots: numeric(parts[2]),
        amount: numeric(parts[3])
      };
    }).filter((point) => point.time && point.price !== null);
    return {
      symbol: symbol.symbol,
      code: symbol.code,
      name: String(block?.qt?.[symbol.symbol]?.[1] ?? symbol.code),
      date: String(latest.date ?? ""),
      source: "腾讯财经公开行情",
      delayedMinutes: null,
      points
    };
  }

  async #tencentQuotes(symbols) {
    const url = `https://qt.gtimg.cn/q=${symbols.map((item) => item.symbol).join(",")}`;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const response = await this.fetchImpl(url, {
        headers: { "user-agent": "Mozilla/5.0", referer: "https://gu.qq.com/" },
        signal: controller.signal
      });
      if (!response.ok) throw new MarketError(`腾讯财经 HTTP ${response.status}`, "market_http_error");
      const buffer = await response.arrayBuffer();
      const text = new TextDecoder("gbk").decode(buffer);
      const map = new Map();
      for (const match of text.matchAll(/v_((?:sh|sz|bj)\d{6})="([^"]*)"/g)) {
        const symbol = normalizeSymbol(match[1]);
        if (!symbol) continue;
        const quote = parseTencentQuote(symbol, match[2].split("~"), this.now);
        if (quote) map.set(symbol.symbol, quote);
      }
      if (!map.size) throw new MarketError("腾讯财经没有返回有效行情", "market_empty_response");
      return map;
    } catch (error) {
      if (error.name === "AbortError") throw new MarketError("行情请求超时", "market_timeout");
      if (error instanceof MarketError) throw error;
      throw new MarketError(`行情请求失败：${error.message}`, "market_network_error");
    } finally {
      clearTimeout(timer);
    }
  }

  async #eastmoneyQuote(symbol) {
    const url = new URL("https://push2.eastmoney.com/api/qt/stock/get");
    url.searchParams.set("secid", symbol.secid);
    url.searchParams.set("ut", EASTMONEY_TOKEN);
    url.searchParams.set("invt", "2");
    url.searchParams.set("fltt", "2");
    url.searchParams.set("fields", EASTMONEY_FIELDS);
    const json = await this.#fetchJson(url, "https://quote.eastmoney.com/");
    const data = json?.data;
    if (!data || data.f57 === undefined) {
      throw new MarketError(`东方财富未返回 ${symbol.symbol} 的行情`, "quote_not_found");
    }
    return {
      symbol: symbol.symbol,
      code: String(data.f57 ?? symbol.code),
      market: symbol.market,
      name: String(data.f58 ?? symbol.code),
      price: numeric(data.f43),
      previousClose: numeric(data.f60),
      open: numeric(data.f46),
      high: numeric(data.f44),
      low: numeric(data.f45),
      change: numeric(data.f169),
      changePercent: numeric(data.f170),
      volumeLots: numeric(data.f47),
      volume: numeric(data.f47) === null ? null : numeric(data.f47) * 100,
      amount: numeric(data.f48),
      turnoverPercent: numeric(data.f168),
      pe: numeric(data.f162),
      marketCap: numeric(data.f116),
      floatMarketCap: numeric(data.f117),
      timestamp: timestampFromUnix(data.f86, this.now),
      source: "东方财富公开行情",
      delayedMinutes: null
    };
  }

  async #searchSina(query, limit) {
    const url = new URL("https://suggest3.sinajs.cn/suggest/type=11,12,13,14,15");
    url.searchParams.set("key", query);
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const response = await this.fetchImpl(url, {
        headers: { "user-agent": "Mozilla/5.0", referer: "https://finance.sina.com.cn/" },
        signal: controller.signal
      });
      if (!response.ok) throw new MarketError(`新浪财经搜索 HTTP ${response.status}`);
      const buffer = await response.arrayBuffer();
      const text = new TextDecoder("gbk").decode(buffer);
      const match = /suggestvalue="([\s\S]*?)"/.exec(text);
      if (!match) return [];
      const results = [];
      const seen = new Set();
      for (const row of match[1].split(";")) {
        const fields = row.split(",");
        const code = String(fields[2] ?? "").trim();
        const quoteSymbol = String(fields[3] ?? "").trim();
        const name = String(fields[4] ?? "").trim();
        const symbol = normalizeSymbol(quoteSymbol);
        if (!symbol || symbol.code !== code || !name || seen.has(symbol.symbol)) continue;
        seen.add(symbol.symbol);
        results.push(searchResult(symbol, name));
        if (results.length >= limit) break;
      }
      return results;
    } finally {
      clearTimeout(timer);
    }
  }

  async #searchTencent(query, limit) {
    const url = new URL("https://smartbox.gtimg.cn/s3/");
    url.searchParams.set("q", query);
    url.searchParams.set("t", "all");
    const json = await this.#fetchTextJson(url, "https://gu.qq.com/");
    const match = /v_hint="([\s\S]*?)"/.exec(json);
    if (!match) return [];
    const results = [];
    const seen = new Set();
    for (const row of match[1].split("^")) {
      const fields = row.split("~");
      const symbol = normalizeSymbol(`${fields[0] ?? ""}${fields[1] ?? ""}`);
      if (!symbol || seen.has(symbol.symbol)) continue;
      let name = fields[2] ?? "";
      try {
        name = JSON.parse(`"${name.replace(/"/g, '\\"')}"`);
      } catch {
        // Keep the original text when the suggester already returned UTF-8.
      }
      if (!name) continue;
      seen.add(symbol.symbol);
      results.push(searchResult(symbol, name));
      if (results.length >= limit) break;
    }
    return results;
  }

  async #fetchJson(url, referer) {
    const text = await this.#fetchText(url, referer);
    try {
      return JSON.parse(text);
    } catch {
      const jsonp = /^[^(]*\(([\s\S]*)\)\s*;?$/.exec(text);
      if (jsonp) return JSON.parse(jsonp[1]);
      throw new MarketError("行情源返回了无法解析的数据", "market_decode_error");
    }
  }

  async #fetchTextJson(url, referer) {
    return this.#fetchText(url, referer);
  }

  async #fetchText(url, referer = "https://gu.qq.com/") {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const response = await this.fetchImpl(url, {
        headers: {
          accept: "application/json, text/plain, */*",
          "user-agent": "Mozilla/5.0",
          referer
        },
        signal: controller.signal
      });
      if (!response.ok) throw new MarketError(`行情源 HTTP ${response.status}`, "market_http_error");
      const body = await response.text();
      if (!body.trim()) throw new MarketError("行情源返回了空响应", "market_empty_response");
      return body;
    } catch (error) {
      if (error.name === "AbortError") throw new MarketError("行情请求超时", "market_timeout");
      if (error instanceof MarketError) throw error;
      throw new MarketError(`行情请求失败：${error.message}`, "market_network_error");
    } finally {
      clearTimeout(timer);
    }
  }
}

export function normalizeSymbol(input) {
  if (!input) return null;
  let value = String(input).trim().toLowerCase().replace(/\s+/g, "");
  let match = /^(sh|sz|bj)(\d{6})$/.exec(value);
  if (match) return buildSymbol(match[1], match[2]);
  match = /^(\d{6})\.(sh|sz|bj)$/.exec(value);
  if (match) return buildSymbol(match[2], match[1]);
  match = /^([01])\.(\d{6})$/.exec(value);
  if (match) return buildSymbol(match[1] === "1" ? "sh" : "sz", match[2]);
  match = /^(\d{6})$/.exec(value);
  if (!match) return null;
  const code = match[1];
  if (/^[569]/.test(code)) return buildSymbol("sh", code);
  if (/^[48]/.test(code)) return buildSymbol("bj", code);
  if (/^[013]/.test(code)) return buildSymbol("sz", code);
  return null;
}

function parseTencentQuote(symbol, fields, now) {
  if (fields.length < 35 || !fields[1] || !fields[2]) return null;
  const price = numeric(fields[3]);
  if (price === null) return null;
  const volumeLots = numeric(fields[6]);
  const amountWan = numeric(fields[37]);
  const marketCapYi = numeric(fields[45]);
  const floatMarketCapYi = numeric(fields[44]);
  return {
    symbol: symbol.symbol,
    code: String(fields[2] ?? symbol.code),
    market: symbol.market,
    name: String(fields[1]),
    price,
    previousClose: numeric(fields[4]),
    open: numeric(fields[5]),
    high: numeric(fields[33]),
    low: numeric(fields[34]),
    change: numeric(fields[31]),
    changePercent: numeric(fields[32]),
    volumeLots,
    volume: volumeLots === null ? null : volumeLots * 100,
    amount: amountWan === null ? null : amountWan * 10_000,
    turnoverPercent: numeric(fields[38]),
    pe: numeric(fields[39]),
    marketCap: marketCapYi === null ? null : marketCapYi * 100_000_000,
    floatMarketCap: floatMarketCapYi === null ? null : floatMarketCapYi * 100_000_000,
    timestamp: parseTencentTime(fields[30]) ?? now().toISOString(),
    source: "腾讯财经公开行情",
    delayedMinutes: null
  };
}

function parseTencentTime(value) {
  const match = /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})$/.exec(String(value ?? ""));
  if (!match) return null;
  return `${match[1]}-${match[2]}-${match[3]}T${match[4]}:${match[5]}:${match[6]}+08:00`;
}

function searchResult(symbol, name) {
  return {
    symbol: symbol.symbol,
    code: symbol.code,
    name,
    market: symbol.market,
    type: /指数/.test(name) ? "index" : "stock"
  };
}

function buildSymbol(market, code) {
  const prefix = market === "sh" ? "sh" : market === "bj" ? "bj" : "sz";
  return {
    symbol: `${prefix}${code}`,
    code,
    market: prefix.toUpperCase(),
    secid: `${prefix === "sh" ? "1" : "0"}.${code}`
  };
}

function splitQueries(text) {
  return text.split(/[，,、;；\s]+/).map((item) => item.trim()).filter(Boolean);
}

function dedupeSymbols(symbols) {
  const seen = new Set();
  return symbols.filter((symbol) => {
    if (seen.has(symbol.symbol)) return false;
    seen.add(symbol.symbol);
    return true;
  });
}

function numeric(value) {
  if (value === null || value === undefined || value === "" || value === "-") return null;
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function timestampFromUnix(value, fallback) {
  const number = numeric(value);
  if (number === null) return fallback().toISOString();
  const millis = number > 10_000_000_000 ? number : number * 1000;
  const date = new Date(millis);
  return Number.isNaN(date.getTime()) ? fallback().toISOString() : date.toISOString();
}
