const { chromium } = require('C:/Users/hzwangxiuguo/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs = require('node:fs/promises');
const path = require('node:path');
const vm = require('node:vm');

async function checkReport() {
  const targetRoot='F:/VS_t/代号鲸鱼01/web/checklist-audit';
  const document=await fs.readFile(path.join(targetRoot,'index.html'),'utf8');
  const scripts=[...document.matchAll(/<script(?: [^>]*)?>([\s\S]*?)<\/script>/g)];
  new vm.Script(scripts.at(-1)[1]);
  const data=JSON.parse(document.match(/<script id="audit-data" type="application\/json">([\s\S]*?)<\/script>/)[1]);
  if(data.tasks.length!==59||data.cases.length!==76||data.scenarios.length!==3||data.safari.length!==39)throw new Error('Wrong audit cardinality');
  if(/00008140-|DEEPSEEK_API_KEY\s*[=:]\s*["']?sk-|pairing_file_contents/i.test(document))throw new Error('Sensitive content in public report');
  const browser=await chromium.launch({channel:'msedge',headless:true});
  const page=await browser.newPage({viewport:{width:1280,height:1000}});
  const errors=[];
  page.on('pageerror',error=>errors.push(error.message));
  try {
    await page.goto('http://127.0.0.1:8088/checklist-audit/index.html');
    await page.getByRole('tab',{name:'任务逐项核对',exact:true}).click();
    if(await page.locator('#task-body tr').count()!==59)throw new Error('Task rendering failed');
    await page.locator('#task-search').fill('W01-015');
    if(await page.locator('#task-body tr').count()!==1)throw new Error('Task search failed');
    if(!(await page.locator('#task-body').innerText()).includes('requestLocation'))throw new Error('Search row content mismatch');
    await page.locator('#task-search').fill('');
    await page.locator('#task-status').selectOption('gap');
    if(await page.locator('#task-body tr').count()<1)throw new Error('Status filter failed');
    await page.locator('#task-body [data-evidence-jump]').first().click();
    if(!(await page.locator('#evidence').isVisible()))throw new Error('Evidence jump failed');
    await page.getByRole('tab',{name:'验收矩阵',exact:true}).click();
    if(await page.locator('#case-body tr').count()!==76)throw new Error('Acceptance rows failed');
    await page.locator('#case-search').fill('C12');
    if(await page.locator('#case-body tr').count()!==1)throw new Error('Acceptance search failed');
    await page.locator('#case-search').fill('');
    await page.getByRole('button',{name:'3 个端到端剧本',exact:true}).click();
    if(await page.locator('#case-body tr').count()!==3)throw new Error('Scenario rows failed');
    await page.getByRole('button',{name:'Safari · 39 项附加',exact:true}).click();
    if(await page.locator('#case-body tr').count()!==39)throw new Error('Safari rows failed');
    for(const viewportWidth of [1280,434,320]) {
      await page.setViewportSize({width:viewportWidth,height:1000});
      for(const label of ['总览与门槛','任务逐项核对','验收矩阵','缺口与偏差','证据与版本']) {
        await page.getByRole('tab',{name:label,exact:true}).click();
        const geometry=await page.evaluate(()=>({width:document.documentElement.clientWidth,scrollWidth:document.documentElement.scrollWidth}));
        if(geometry.scrollWidth>geometry.width+2)throw new Error('Report body overflow: '+viewportWidth+' '+label);
      }
    }
    await page.setViewportSize({width:1280,height:1000});
    await page.getByRole('tab',{name:'总览与门槛',exact:true}).click();
    await page.screenshot({path:path.join(__dirname,'report-overview.png'),fullPage:true});
    if(errors.length)throw new Error(errors.join(' | '));
    const result={status:'passed',tasks:59,cases:76,scenarios:3,safari:39,views:5,viewportWidths:[1280,434,320],searchAndFilters:'passed',evidenceLinks:'passed',scriptErrors:errors,scope:'HTML审计报告自身检查，不是项目76项验收通过'};
    await fs.writeFile(path.join(__dirname,'report-validation.json'),JSON.stringify(result,null,2));
    console.log(JSON.stringify(result));
  } finally {await browser.close();}
}

checkReport().catch(error=>{console.error(error.message);process.exitCode=1;});
