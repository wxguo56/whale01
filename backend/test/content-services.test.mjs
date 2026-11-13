import test from "node:test";
import assert from "node:assert/strict";
import { NewsService, parseFeed, cleanText } from "../src/news.mjs";
import { MarketService, normalizeSymbol } from "../src/market.mjs";
import { GameRankService } from "../src/gameRank.mjs";
import { ServerToolExecutor } from "../src/serverTools.mjs";
import { readTextBounded } from "../src/boundedContent.mjs";

const NOW = new Date("2026-11-11T08:00:00.000Z");

test("缺失发布时间不伪造刚刚，手动刷新保留真实获取时间", async () => {
  let clock = NOW, calls = 0;
  const service = new NewsService({ now: () => clock,
    feeds: [{ id: "a", name: "源A", url: "https://a.test/rss", channels: ["ai"] }],
    fetchImpl: async () => { calls++; return new Response('<rss><channel><item><title>AI 进展</title><link>https://example.com/a</link><description>真实摘要</description></item></channel></rss>'); }
  });
  const first = await service.list();
  assert.equal(first.items[0].publishedAt, null);
  clock = new Date(NOW.getTime() + 1000);
  assert.equal((await service.list()).updatedAt, NOW.toISOString());
  assert.equal(calls, 1);
  assert.equal((await service.list({ force: true })).updatedAt, clock.toISOString());
  assert.equal(calls, 2);
});

test("同地址并发新闻请求只下载一次，总数遵守各自上限", async () => {
  let calls = 0;
  const service = new NewsService({ now: () => NOW,
    feeds: [{ id: "a", name: "源A", url: "https://a.test/rss", channels: ["ai"] }, { id: "b", name: "源B", url: "https://a.test/rss", channels: ["ai"] }],
    fetchImpl: async () => { calls++; await new Promise(resolve => setTimeout(resolve, 10)); return new Response('<rss><channel><item><title>AI 进展</title><link>https://example.com/a</link></item></channel></rss>'); }
  });
  const results = await Promise.all([service.list({ limit: 1 }), service.list({ limit: 2 })]);
  assert.equal(calls, 1);
  assert.ok(results[0].items.length <= 1);
  assert.ok(results[1].items.length <= 2);
});

test("流式下载达到字节上限立即取消，不依赖 Content-Length", async () => {
  let cancelled = false;
  const response = new Response(new ReadableStream({
    pull(controller) { controller.enqueue(new Uint8Array(64)); },
    cancel() { cancelled = true; }
  }));
  await assert.rejects(readTextBounded(response, 100), /budget/);
  assert.equal(cancelled, true);
});

test("RSS/Atom 解析保留标题、链接、摘要与时间", () => {
  const rss = `<rss><channel><item><title><![CDATA[大模型新进展]]></title><link>https://example.com/a</link><description><![CDATA[<p>摘要 &amp; 内容</p>]]></description><pubDate>Tue, 11 Nov 2026 07:00:00 GMT</pubDate></item></channel></rss>`;
  const items = parseFeed(rss);
  assert.equal(items.length, 1);
  assert.equal(cleanText(items[0].title), "大模型新进展");
  assert.equal(items[0].link, "https://example.com/a");
  assert.equal(cleanText(items[0].summary), "摘要 & 内容");

  const atom = `<feed><entry><title>Agent update</title><link rel="alternate" href="https://example.com/b"/><summary>summary</summary><updated>2026-11-11T06:00:00Z</updated></entry></feed>`;
  const atomItems = parseFeed(atom);
  assert.equal(atomItems[0].link, "https://example.com/b");
});

test("新闻摘要多层转义与 HTML 标签被清理成纯文本", () => {
  assert.equal(cleanText("<![CDATA[<p data-vmark=\"abc\">AI <strong>新闻</strong></p>]]>"), "AI 新闻");
  assert.equal(cleanText("&lt;p&gt;游戏&amp;lt;b&amp;gt;资讯&lt;/b&gt;&lt;/p&gt;"), "游戏 资讯");
  assert.equal(cleanText("&amp;lt;p&amp;gt;双层转义&amp;lt;/p&amp;gt;"), "双层转义");
  assert.equal(cleanText("&amp;amp;lt;p&amp;amp;gt;三层转义&amp;amp;lt;/p&amp;amp;gt;"), "三层转义");
  assert.equal(cleanText("<style>.x{color:red}</style>正文&nbsp;&amp;&nbsp;更多"), "正文 & 更多");
});

test("NewsService 只返回真实源内容、去重并缓存", async () => {
  let calls = 0;
  const feedXml = (title, link, date) => `<rss><channel><item><title>${title}</title><link>${link}</link><description>AI 摘要</description><pubDate>${date}</pubDate></item></channel></rss>`;
  const service = new NewsService({
    now: () => NOW,
    cacheTtlMs: 60_000,
    feeds: [
      { id: "a", name: "源A", url: "https://a.test/rss", channels: ["ai"] },
      { id: "b", name: "源B", url: "https://b.test/rss", channels: ["ai"] }
    ],
    fetchImpl: async (url) => {
      calls += 1;
      const target = String(url);
      const body = target.includes("a.test")
        ? feedXml("第一条 AI 新闻", "https://example.com/1", "Tue, 11 Nov 2026 07:00:00 GMT")
        : feedXml("第一条 AI 新闻", "https://example.com/2", "Tue, 11 Nov 2026 06:00:00 GMT");
      return new Response(body, { status: 200 });
    }
  });
  const first = await service.list({ channel: "ai", limit: 10 });
  assert.equal(first.items.length, 1);
  assert.equal(first.items[0].title, "第一条 AI 新闻");
  assert.equal(calls, 2);
  const second = await service.list({ channel: "ai", limit: 10 });
  assert.equal(second.cached, true);
  assert.equal(calls, 2);
});

test("行情符号归一化覆盖沪深北与指数", () => {
  assert.deepEqual(normalizeSymbol("sh600519"), { symbol: "sh600519", code: "600519", market: "SH", secid: "1.600519" });
  assert.deepEqual(normalizeSymbol("000001"), { symbol: "sz000001", code: "000001", market: "SZ", secid: "0.000001" });
  assert.deepEqual(normalizeSymbol("300750.SZ"), { symbol: "sz300750", code: "300750", market: "SZ", secid: "0.300750" });
  assert.deepEqual(normalizeSymbol("1.000001"), { symbol: "sh000001", code: "000001", market: "SH", secid: "1.000001" });
  assert.equal(normalizeSymbol("AAPL"), null);
});

test("MarketService 解析真实行情响应并标注延迟", async () => {
  const service = new MarketService({
    now: () => NOW,
    fetchImpl: async () => new Response(JSON.stringify({
      rc: 0,
      data: {
        f43: 1688.5, f44: 1700, f45: 1670, f46: 1680, f47: 12345,
        f48: 2080000000, f57: "600519", f58: "贵州茅台", f60: 1670,
        f86: 1762800000, f116: 2100000000000, f117: 2100000000000,
        f162: 28.6, f168: 0.34, f169: 18.5, f170: 1.11
      }
    }), { status: 200 })
  });
  const result = await service.quotes(["sh600519"]);
  assert.equal(result.delayedMinutes, null);
  assert.equal(result.quotes[0].fetchedAt, NOW.toISOString());
  assert.equal(result.quotes[0].name, "贵州茅台");
  assert.equal(result.quotes[0].price, 1688.5);
  assert.equal(result.quotes[0].volume, 1_234_500);
});

test("GameRankService 读取 App Store 公开榜单并缓存", async () => {
  let calls = 0;
  const payload = {
    feed: {
      entry: [
        {
          "im:name": { label: "王者荣耀" },
          "im:image": [{ label: "https://example.com/53.png" }, { label: "https://example.com/100.png" }],
          "im:artist": { label: "Tencent" },
          "category": { attributes: { label: "游戏" } },
          "im:releaseDate": { label: "2015-10-26T00:00:00-07:00" },
          "id": { label: "989673964", attributes: { "im:id": "989673964" } },
          link: [{ attributes: { href: "https://apps.apple.com/cn/app/id989673964" } }]
        }
      ]
    }
  };
  const service = new GameRankService({
    now: () => NOW,
    fetchImpl: async () => {
      calls += 1;
      return new Response(JSON.stringify(payload), { status: 200 });
    }
  });
  const first = await service.list({ board: "free", limit: 10 });
  assert.equal(first.items.length, 1);
  assert.equal(first.items[0].rank, 1);
  assert.equal(first.items[0].name, "王者荣耀");
  assert.equal(first.items[0].icon, "https://example.com/100.png");
  assert.equal(first.source, "Apple App Store 中国区公开榜单");
  const second = await service.list({ board: "free", limit: 10 });
  assert.equal(second.cached, true);
  assert.equal(calls, 1);
});

test("服务端工具把新闻与行情转换为可引用的真实结果", async () => {
  const news = { list: async () => ({ channel: "ai", updatedAt: NOW.toISOString(), sources: ["源A"], unavailableSources: [], items: [{ title: "AI 新闻", summary: "摘要", source: "源A", publishedAt: NOW.toISOString(), link: "https://example.com/a" }] }) };
  const quote = { symbol: "sh600519", code: "600519", name: "贵州茅台", price: 1688.5, delayedMinutes: 15 };
  const market = {
    resolve: async () => ({ query: "茅台", quotes: [quote], matches: [{ symbol: "sh600519", name: "贵州茅台" }], errors: [], ambiguous: false }),
    search: async () => ({ results: [] }),
    kline: async () => ({ points: [] })
  };
  const gameRank = {
    list: async () => ({ board: "grossing", boardName: "畅销榜", updatedAt: NOW.toISOString(), source: "Apple App Store 中国区公开榜单", items: [{ rank: 1, name: "王者荣耀" }] })
  };
  const executor = new ServerToolExecutor({ news, market, gameRank });
  const newsResult = await executor.execute({ tool: "get_tech_news", arguments: { channel: "ai" } });
  assert.equal(newsResult.status, "success");
  assert.equal(newsResult.data.items[0].title, "AI 新闻");
  const quoteResult = await executor.execute({ tool: "get_stock_quote", arguments: { query: "茅台" } });
  assert.equal(quoteResult.status, "success");
  assert.equal(quoteResult.data.quotes[0].name, "贵州茅台");
  assert.equal(quoteResult.data.delayedMinutes, 15);
  const rankResult = await executor.execute({ tool: "get_game_rank", arguments: { board: "grossing" } });
  assert.equal(rankResult.status, "success");
  assert.equal(rankResult.data.items[0].name, "王者荣耀");
});
