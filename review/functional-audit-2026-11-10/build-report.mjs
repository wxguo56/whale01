import fs from 'node:fs';
import path from 'node:path';
const root='F:/VS_t/代号鲸鱼01';
const web=path.join(root,'web/function-audit-2026-11-10');
const d=JSON.parse(fs.readFileSync(path.join(web,'audit-data.json'),'utf8'));
let html=fs.readFileSync(path.join(web,'index.html'),'utf8');
const css=fs.readFileSync(path.join(web,'styles.css'),'utf8');
const app=fs.readFileSync(path.join(web,'app.js'),'utf8');
const js=fs.readFileSync(path.join(web,'audit-data.js'),'utf8');
html=html.replace('<link rel="stylesheet" href="styles.css">','<style>'+css+'</style>')
  .replace('<script src="audit-data.js" defer></script>','')
  .replace('<script src="app.js" defer></script>','')
  .replace('</body>','<script>'+js.replaceAll('</script','<\\/script')+'</script><script>'+app.replaceAll('</script','<\\/script')+'</script></body>');
const downloads={'audit-data.json':JSON.stringify(d,null,2),'backend-tests.txt':fs.readFileSync(path.join(web,'backend-tests.txt'),'utf8'),'package-facts.json':fs.readFileSync(path.join(web,'package-facts.json'),'utf8')};
for(const [name,contents] of Object.entries(downloads)) html=html.replaceAll(`href="${name}" download`,`href="data:${name.endsWith('.json')?'application/json':'text/plain'};base64,${Buffer.from(contents).toString('base64')}" download="${name}"`);
html=html.replace('href="standalone.html" download','href="#top"').replace('下载单文件 HTML','已是单文件 HTML');
fs.writeFileSync(path.join(web,'standalone.html'),html);
const c=Object.fromEntries(Object.keys(d.statuses).map(s=>[s,d.rows.filter(r=>r.status===s).length]));
const md=[`# 代号鲸鱼01：功能完成情况审计（不含 UI）`,``, `快照：${d.meta.snapshot}。源码 HEAD ${d.meta.sourceHead}；当前运行代码/安装包记录 ${d.meta.packageSource}。`, ``, `当前本地 IPA：${d.packageFacts.version} (${d.packageFacts.build})，${d.packageFacts.bytes} bytes。SHA256：${d.packageFacts.sha256}。`, ``, `最近完整真机验收为 ${d.meta.deviceBaseline}，${d.meta.deviceOS}。不推断手机当前安装版本，不将旧证据直接等同新构建通过。`, ``, `本次独立后端回归：62/62，Mock 模型与执行。CI 成功来自执行记录；本次未新做真机测试、Xcode 构建或在线语义评估。`, ``, `## 能力项分布`, ``, ...Object.entries(c).map(([s,n])=>`- ${d.statuses[s]}：${n} 项。`), ``, `共 ${d.rows.length} 项；不是完成率。原清单映射 25 个非 UI 主任务；W01-010/022 与界面/动效/手势不计入。`, ``, `## 推荐顺序`, ``, ...d.priorities.flatMap(p=>[`### ${p.n} ${p.title}`,``,p.why,``,...p.steps.map((x,i)=>`${i+1}. ${x}`),``, `门槛：${p.gate}`,``]), `## 逐项结论`, ``, ...d.rows.flatMap(r=>[`### ${r.id} ${r.title}`,``, `状态：${d.statuses[r.status]}；${r.version}。`, ``, `计划：${r.plan}`, ``, `已做：${r.done}`, ``, `未做/原因：${r.why}`, ``, `下一步：${r.next}`, ``, `依据：${r.refs.join('、')}。任务：${r.ids.join('、')}。`,``]), `## 证据位置`, ``, ...d.evidence.flatMap(e=>[`### ${e.id} ${e.title}`,``,e.note,``, `项目根：${root}`,``, `文件：${e.files}`,``]), `## 交付`, ``, `- 可访问报告：http://127.0.0.1:8088/function-audit-2026-11-10/index.html`, `- 单文件 HTML：${web}/standalone.html（自含数据/CSS/JS/日志下载内容；浏览器离线渲染未实测）`, `- 可复核数据：${web}/audit-data.json`, `- 测试日志：${root}/review/functional-audit-2026-11-10/backend-tests.txt`, ``];
fs.writeFileSync(path.join(root,'review/functional-audit-2026-11-10/审计结论.md'),md.join('\n'));
console.log(JSON.stringify({standaloneBytes:Buffer.byteLength(html),externalScripts:(html.match(/<script[^>]+src=/g)||[]).length,externalStyles:(html.match(/<link[^>]+stylesheet/g)||[]).length,capabilityItems:d.rows.length,originalTasks:d.taskRows.length}));
