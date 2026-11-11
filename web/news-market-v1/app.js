const NEWS = {
  ai: [
    { tag: '大模型', title: 'DeepSeek 新一代推理模型开放测试，代码与数学能力再提升', source: '机器之心', time: '12 分钟前', summary: '模型在代码生成、数学推理和长上下文任务上展示了更强的稳定性；具体开放范围和调用价格以官方公告为准。', thumb: '' },
    { tag: 'Agent', title: '开源多模态 Agent 框架发布：一句话完成跨 App 操作', source: '量子位', time: '38 分钟前', summary: '框架把屏幕理解、工具调用和失败恢复拆成独立模块，开发者可以按需组合。', thumb: 'alt' },
    { tag: '芯片', title: '国产 GPU 推理集群落地，单卡吞吐提升 2.4 倍', source: '36 氪', time: '1 小时前', summary: '新集群针对长上下文推理做了显存与调度优化，实际吞吐仍需结合模型规模评估。', thumb: 'warm' },
    { tag: '开源', title: 'Hacker News 今日热帖：本地优先的 AI 助手正在回归', source: 'Hacker News', time: '2 小时前', summary: '讨论集中在隐私、离线可用性和端侧模型成本，多个项目选择把记忆留在设备上。', thumb: 'alt' }
  ],
  headline: [
    { tag: '要闻', title: '今日要闻：多项促消费政策落地，服务消费成重点', source: '新华社', time: '18 分钟前', summary: '政策覆盖文旅、体育、养老等服务消费场景，具体执行细则由各地陆续发布。', thumb: '' },
    { tag: '社会', title: '全国多地发布寒潮预警，部分高铁线路调整运行', source: '央视新闻', time: '45 分钟前', summary: '铁路部门提示旅客关注车站公告，预留更充足的进站时间。', thumb: 'alt' },
    { tag: '财经', title: '进博会闭幕：意向成交额创新高，AI 与绿色能源受关注', source: '第一财经', time: '1 小时前', summary: '本届进博会意向成交额继续保持增长，技术装备与绿色能源展区热度靠前。', thumb: 'warm' },
    { tag: '全球', title: '国际油价小幅回落，市场关注本周库存数据', source: '路透中文', time: '2 小时前', summary: '交易员正在评估需求预期与供应端变化，短期波动仍然存在。', thumb: 'alt' }
  ]
};

const STOCKS = {
  '600519': { name: '贵州茅台', code: '600519', market: 'SH', price: 1682.40, delta: 20.60, pct: 1.24, open: '1,665.00', high: '1,690.80', low: '1,658.20', volume: '2.84 万手', amount: '47.6 亿', turnover: '0.23%', pe: '29.8', cap: '2.11 万亿', points: [1658,1664,1661,1670,1668,1674,1671,1678,1675,1682,1679,1686,1683,1690,1684,1688,1681,1685,1680,1682] },
  '300750': { name: '宁德时代', code: '300750', market: 'SZ', price: 268.15, delta: -1.02, pct: -0.38, open: '269.30', high: '271.10', low: '266.80', volume: '18.6 万手', amount: '49.9 亿', turnover: '0.71%', pe: '22.4', cap: '1.18 万亿', points: [271,270,269,270,268,269,267,268,267,266,267,268,269,268,267,268,269,268,267,268] },
  '688981': { name: '中芯国际', code: '688981', market: 'SH', price: 92.36, delta: 1.90, pct: 2.10, open: '90.60', high: '93.20', low: '90.10', volume: '64.2 万手', amount: '58.7 亿', turnover: '1.12%', pe: '86.5', cap: '7,342 亿', points: [90.2,90.8,90.5,91.2,91.0,91.8,91.5,92.2,92.0,92.8,92.4,93.0,92.6,93.2,92.8,93.0,92.7,92.9,92.5,92.36] },
  '600036': { name: '招商银行', code: '600036', market: 'SH', price: 41.28, delta: 0.06, pct: 0.15, open: '41.20', high: '41.55', low: '41.05', volume: '42.1 万手', amount: '17.3 亿', turnover: '0.20%', pe: '6.8', cap: '1.04 万亿', points: [41.2,41.3,41.25,41.35,41.3,41.4,41.32,41.38,41.35,41.42,41.38,41.45,41.4,41.5,41.42,41.46,41.4,41.44,41.38,41.28] }
};

const INDICES = [
  { name: '上证指数', value: '3,412.56', pct: 0.62 },
  { name: '深证成指', value: '10,876.31', pct: 0.41 },
  { name: '创业板指', value: '2,214.08', pct: -0.18 }
];

const WATCHLIST = ['600519', '300750', '688981', '600036'];
const BODY = {
  '大模型': '报道提到，新模型已面向部分开发者开放测试，重点优化了长上下文中的推理稳定性。实际能力、开放范围和调用价格仍以官方页面为准。',
  'Agent': '文章拆解了框架的屏幕理解、工具调用和失败恢复三个模块，并给出跨 App 任务的演示。真实可用性仍取决于系统权限与目标 App 的开放程度。',
  '芯片': '报道介绍了新集群的显存配置与调度策略，并给出特定模型下的吞吐对比。不同模型规模、 batch 大小和精度设置都会影响最终结果。',
  '开源': '讨论集中在隐私、离线可用性和端侧模型成本。多个项目选择把记忆与推理留在设备上，但能力边界和功耗仍是主要限制。',
  '要闻': '政策覆盖文旅、体育、养老等服务消费场景，具体执行细则由各地陆续发布。后续效果仍需观察实际落地进度。',
  '社会': '铁路部门提示旅客关注车站公告，预留更充足的进站时间。受天气影响的车次信息以 12306 实时公告为准。',
  '财经': '本届进博会意向成交额继续保持增长，技术装备与绿色能源展区热度靠前。意向成交与实际履约之间通常存在差异。',
  '全球': '交易员正在评估需求预期与供应端变化，短期波动仍然存在。油价走势还受库存数据与主要产油国政策影响。'
};
const CHIPS = { ai: ['推荐', '大模型', '芯片', '开源', 'Agent'], headline: ['要闻', '社会', '财经', '全球'] };
let currentSegment = 'ai';
let currentFilter = '推荐';
let currentStock = '600519';

function fitPhone() {
  const shell = document.querySelector('.phone-shell');
  if (!shell) return;
  const narrow = window.innerWidth <= 880;
  const byHeight = (window.innerHeight - (narrow ? 34 : 76)) / 874;
  const byWidth = (window.innerWidth - (narrow ? 24 : 0)) / 402;
  const scale = Math.max(0.62, Math.min(1, byHeight, byWidth));
  shell.style.transform = `scale(${scale})`;
  shell.style.marginBottom = `${-(874 * (1 - scale))}px`;
}

function fmtPct(pct) { return `${pct >= 0 ? '+' : ''}${pct.toFixed(2)}%`; }
function clsPct(pct) { return pct >= 0 ? 'up' : 'down'; }
function fmtPrice(price) { return price.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 }); }

function sparkline(points, up, width = 58, height = 25) {
  const min = Math.min(...points), max = Math.max(...points), range = max - min || 1;
  const step = width / (points.length - 1);
  const d = points.map((p, i) => {
    const x = i * step;
    const y = height - 2 - ((p - min) / range) * (height - 4);
    return `${i ? 'L' : 'M'}${x.toFixed(1)},${y.toFixed(1)}`;
  }).join(' ');
  const color = up ? '#ff8a7a' : '#5be0b0';
  return `<svg class="spark" viewBox="0 0 ${width} ${height}" preserveAspectRatio="none" aria-hidden="true"><path d="${d}" fill="none" stroke="${color}" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
}

function chart(points, up) {
  const w = 340, h = 150, pad = 10;
  const min = Math.min(...points), max = Math.max(...points), range = max - min || 1;
  const step = (w - pad * 2) / (points.length - 1);
  const color = up ? '#ff8a7a' : '#5be0b0';
  const path = points.map((p, i) => {
    const x = pad + i * step;
    const y = h - pad - ((p - min) / range) * (h - pad * 2);
    return `${i ? 'L' : 'M'}${x.toFixed(1)},${y.toFixed(1)}`;
  }).join(' ');
  const area = `${path} L${w - pad},${h - pad} L${pad},${h - pad} Z`;
  const grid = [0.25, 0.5, 0.75].map((t) => `<line x1="${pad}" y1="${(h * t).toFixed(1)}" x2="${w - pad}" y2="${(h * t).toFixed(1)}" stroke="rgba(255,255,255,.055)" stroke-width="1"/>`).join('');
  return `<svg viewBox="0 0 ${w} ${h}" preserveAspectRatio="none" aria-hidden="true"><defs><linearGradient id="areaFill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${color}" stop-opacity=".26"/><stop offset="1" stop-color="${color}" stop-opacity="0"/></linearGradient></defs>${grid}<path d="${area}" fill="url(#areaFill)"/><path d="${path}" fill="none" stroke="${color}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/><circle cx="${(w - pad).toFixed(1)}" cy="${(h - pad - ((points[points.length - 1] - min) / range) * (h - pad * 2)).toFixed(1)}" r="3" fill="${color}"/></svg>`;
}

function renderNews(segment = currentSegment) {
  const chips = CHIPS[segment] || CHIPS.ai;
  if (!chips.includes(currentFilter)) currentFilter = chips[0];
  document.getElementById('news-chips').innerHTML = chips.map((chip) => `<button class="chip ${chip === currentFilter ? 'active' : ''}" data-chip="${chip}">${chip}</button>`).join('');
  const items = NEWS[segment] || NEWS.ai;
  const lead = items[0];
  document.getElementById('news-lead-slot').innerHTML = `
    <button class="news-lead" data-news="${segment}" data-index="0">
      <div class="lead-art"></div><div class="lead-shade"></div>
      <div class="lead-content"><span class="lead-tag">${lead.tag} · 焦点</span><h2>${lead.title}</h2><div class="lead-meta"><span>${lead.source}</span><i></i><span>${lead.time}</span></div></div>
    </button>`;
  document.getElementById('news-list').innerHTML = items.slice(1).map((item, i) => `
    <button class="news-row" data-news="${segment}" data-index="${i + 1}">
      <div class="news-thumb ${item.thumb}"></div>
      <div class="news-body"><h3>${item.title}</h3><div class="news-src"><span class="tag">${item.tag}</span><i></i><span>${item.source}</span><i></i><span>${item.time}</span></div></div>
    </button>`).join('');
}

function renderMarket() {
  document.getElementById('index-strip').innerHTML = INDICES.map((item) => `
    <div class="index-card"><small>${item.name}</small><b>${item.value}</b><span class="${clsPct(item.pct)}">${fmtPct(item.pct)}</span></div>`).join('');
  document.getElementById('watch-list').innerHTML = WATCHLIST.map((code) => {
    const stock = STOCKS[code];
    return `
    <button class="watch-row" data-stock="${code}">
      <div class="watch-left"><b>${stock.name}</b><small>${stock.code} · ${stock.market}</small></div>
      ${sparkline(stock.points, stock.pct >= 0)}
      <div class="watch-price"><b>${fmtPrice(stock.price)}</b><span class="${clsPct(stock.pct)}">${fmtPct(stock.pct)}</span></div>
    </button>`;
  }).join('');
}

function setSegment(segment) {
  currentSegment = segment;
  document.querySelectorAll('.segment button').forEach((btn) => btn.classList.toggle('active', btn.dataset.segment === segment));
  document.getElementById('pane-news').classList.toggle('active', segment !== 'market');
  document.getElementById('pane-market').classList.toggle('active', segment === 'market');
  if (segment === 'market') renderMarket();
  else renderNews(segment);
}

function showScreen(name) {
  const target = document.getElementById(`screen-${name}`);
  if (!target) return;
  document.querySelectorAll('.screen').forEach((screen) => screen.classList.toggle('active', screen === target));
  target.scrollTop = 0;
}

function openDiscover(segment) {
  showScreen('discover');
  setSegment(segment);
  const map = { ai: 'ai', headline: 'headline', market: 'market' };
  document.querySelectorAll('.scenario').forEach((btn) => btn.classList.toggle('active', btn.dataset.action === map[segment]));
}

function openStock(code) {
  const stock = STOCKS[code] || STOCKS['600519'];
  currentStock = code;
  document.getElementById('stock-name').textContent = stock.name;
  document.getElementById('stock-code').textContent = `${stock.code} · ${stock.market}`;
  document.getElementById('stock-price').textContent = fmtPrice(stock.price);
  const chg = document.getElementById('stock-chg');
  chg.textContent = `${stock.delta >= 0 ? '+' : ''}${stock.delta.toFixed(2)} · ${fmtPct(stock.pct)}`;
  chg.className = `chg ${clsPct(stock.pct)}`;
  document.getElementById('stock-chart').innerHTML = chart(stock.points, stock.pct >= 0);
  const stats = [['今开', stock.open], ['最高', stock.high], ['最低', stock.low], ['成交量', stock.volume], ['成交额', stock.amount], ['换手率', stock.turnover], ['市盈率', stock.pe], ['总市值', stock.cap]];
  document.getElementById('stock-stats').innerHTML = stats.map(([label, value]) => `<div class="stat"><small>${label}</small><b>${value}</b></div>`).join('');
  showScreen('stock');
  document.querySelectorAll('.scenario').forEach((btn) => btn.classList.toggle('active', btn.dataset.action === 'stock'));
}

function openNews(segment, index) {
  const item = (NEWS[segment] || NEWS.ai)[index] || NEWS.ai[0];
  document.getElementById('article-title').textContent = item.title;
  document.getElementById('article-source').textContent = item.source;
  document.getElementById('article-time').textContent = item.time;
  document.getElementById('article-tag').textContent = item.tag;
  document.getElementById('article-summary').textContent = item.summary;
  document.getElementById('article-p1').textContent = BODY[item.tag] || item.summary;
  document.getElementById('article-p2').textContent = '这条内容用于演示新闻详情的层级：标题、来源、摘要、关键信息优先，阅读原文始终是主操作。正式版本只展示抓取到的摘要与原文链接。';
  showScreen('news');
  document.querySelectorAll('.scenario').forEach((btn) => btn.classList.toggle('active', btn.dataset.action === 'article'));
}

function goHome() {
  showScreen('home');
  document.querySelectorAll('.scenario').forEach((btn) => btn.classList.toggle('active', btn.dataset.action === 'home'));
}

document.addEventListener('click', (event) => {
  const segmentBtn = event.target.closest('[data-segment]');
  if (segmentBtn) { setSegment(segmentBtn.dataset.segment); return; }

  const chip = event.target.closest('[data-chip]');
  if (chip) {
    currentFilter = chip.dataset.chip;
    document.querySelectorAll('.chip').forEach((el) => el.classList.toggle('active', el === chip));
    return;
  }

  const newsBtn = event.target.closest('[data-news]');
  if (newsBtn) { openNews(newsBtn.dataset.news, Number(newsBtn.dataset.index)); return; }

  const stockBtn = event.target.closest('[data-stock]');
  if (stockBtn) { openStock(stockBtn.dataset.stock); return; }

  const action = event.target.closest('[data-action]');
  if (!action) return;
  switch (action.dataset.action) {
    case 'home': goHome(); break;
    case 'back-home': goHome(); break;
    case 'back-discover': openDiscover(currentSegment); break;
    case 'ai': openDiscover('ai'); break;
    case 'headline': openDiscover('headline'); break;
    case 'market': openDiscover('market'); break;
    case 'stock': openStock(currentStock); break;
    case 'article': openNews(currentSegment === 'market' ? 'ai' : currentSegment, 0); break;
  }
});

renderNews('ai');
renderMarket();
fitPhone();
window.addEventListener('resize', fitPhone);
