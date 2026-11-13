import { MarketError } from "./market.mjs";
import { NewsError } from "./news.mjs";
import { GameRankError } from "./gameRank.mjs";

const SERVER_TOOLS = [
  "get_tech_news",
  "get_game_rank",
  "get_stock_quote",
  "search_stock",
  "get_stock_kline",
  "get_stock_intraday"
];

export class ServerToolExecutor {
  constructor({ news, market, gameRank }) {
    this.news = news;
    this.market = market;
    this.gameRank = gameRank;
  }

  capabilities() {
    return SERVER_TOOLS;
  }

  async execute({ tool, arguments: args = {} }) {
    try {
      switch (tool) {
        case "get_tech_news":
          return await this.#news(args);
        case "get_game_rank":
          return await this.#gameRank(args);
        case "get_stock_quote":
          return await this.#quote(args);
        case "search_stock":
          return await this.#search(args);
        case "get_stock_kline":
          return await this.#kline(args);
        case "get_stock_intraday":
          return await this.#intraday(args);
        default:
          return unsupported(tool);
      }
    } catch (error) {
      const message = error instanceof NewsError || error instanceof MarketError || error instanceof GameRankError
        ? error.message
        : `服务端工具执行失败：${error.message}`;
      return {
        status: "failed",
        data: null,
        error: { code: error.code ?? "server_tool_error", message },
        deduplicated: false
      };
    }
  }

  async #news(args) {
    const channel = ["ai", "headline", "game"].includes(args.channel) ? args.channel : "ai";
    const result = await this.news.list({
      channel,
      limit: Math.max(1, Math.min(12, Number(args.limit) || 8))
    });
    return success({
      channel: result.channel,
      updatedAt: result.updatedAt,
      sources: result.sources,
      unavailableSources: result.unavailableSources,
      items: result.items.slice(0, Math.max(1, Math.min(12, Number(args.limit) || 8))).map((item) => ({
        title: item.title,
        summary: item.summary,
        source: item.source,
        publishedAt: item.publishedAt,
        link: item.link
      }))
    });
  }

  async #gameRank(args) {
    if (!this.gameRank) return unsupported("get_game_rank");
    const board = args.board === "grossing" ? "grossing" : "free";
    const result = await this.gameRank.list({
      board,
      limit: Math.max(1, Math.min(50, Number(args.limit) || 20))
    });
    return success(result);
  }

  async #quote(args) {
    const query = String(args.query ?? "").trim();
    if (!query) return failed("invalid_query", "get_stock_quote 需要 query");
    const result = await this.market.resolve(query, { limit: 5 });
    const quotes = result.quotes.slice(0, 3);
    const ambiguous = Boolean(result.ambiguous) && !isMultiQuery(query);
    return success({
      query,
      source: "东方财富公开行情",
      delayedMinutes: result.delayedMinutes ?? quotes.find(quote => quote.delayedMinutes != null)?.delayedMinutes ?? null,
      updatedAt: result.updatedAt ?? quotes.map(quote => quote.fetchedAt).filter(Boolean).sort()[0] ?? null,
      ambiguous,
      quotes,
      matches: result.matches.slice(0, 5)
    });
  }

  async #search(args) {
    const query = String(args.query ?? "").trim();
    if (!query) return failed("invalid_query", "search_stock 需要 query");
    return success(await this.market.search(query, { limit: args.limit }));
  }

  async #kline(args) {
    const query = String(args.query ?? "").trim();
    if (!query) return failed("invalid_query", "get_stock_kline 需要 query");
    let symbol = query;
    if (!/^(sh|sz|bj)?\d{6}$/i.test(symbol.replace(/\./g, ""))) {
      const search = await this.market.search(query, { limit: 1 });
      if (!search.results.length) {
        return failed("stock_not_found", `没有找到与「${query}」匹配的 A 股`);
      }
      symbol = search.results[0].symbol;
    }
    return success(await this.market.kline(symbol, { days: args.days }));
  }

  async #intraday(args) {
    const query = String(args.query ?? "").trim();
    if (!query) return failed("invalid_query", "get_stock_intraday 需要 query");
    let symbol = query;
    if (!/^(sh|sz|bj)?\d{6}$/i.test(symbol.replace(/\./g, ""))) {
      const search = await this.market.search(query, { limit: 1 });
      if (!search.results.length) {
        return failed("stock_not_found", `没有找到与「${query}」匹配的 A 股`);
      }
      symbol = search.results[0].symbol;
    }
    const result = await this.market.intraday(symbol);
    return success({
      ...result,
      points: result.points.filter((_, index) => index % 3 === 0 || index === result.points.length - 1)
    });
  }
}

function success(data) {
  return { status: "success", data, error: null, deduplicated: false };
}

function failed(code, message) {
  return { status: "failed", data: null, error: { code, message }, deduplicated: false };
}

function unsupported(tool) {
  return {
    status: "unsupported",
    data: null,
    error: { code: "server_tool_not_implemented", message: `服务端未实现 ${tool}` },
    deduplicated: false
  };
}

function isMultiQuery(query) {
  return query.split(/[，,、;；\s]+/).filter(Boolean).length > 1;
}
