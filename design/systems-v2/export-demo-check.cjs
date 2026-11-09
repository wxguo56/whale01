const { chromium } = require('C:/Users/hzwangxiuguo/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs = require('node:fs/promises');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

async function checkExportedDemo() {
  const fileMode=process.argv.includes('--file');
  const targetUrl=fileMode?pathToFileURL(path.resolve(__dirname,'../../web/design-v2/index.html')).href:'http://127.0.0.1:8088/design-v2/index.html';
  const browser = await chromium.launch({channel:'msedge',headless:true});
  const page = await browser.newPage({viewport:{width:1000,height:1400}});
  const errors = [];
  const externalRequests = [];
  const results = [];
  page.on('pageerror',error=>errors.push(error.message));
  await page.route('**/*',route=>{
    const url=route.request().url();
    if(url.startsWith('http://127.0.0.1:8088/')||url.startsWith('file:')||url.startsWith('data:')||url.startsWith('blob:'))return route.continue();
    externalRequests.push(url);
    return route.abort();
  });
  try {
    await page.goto(targetUrl);
    const frame=page.frames().find(candidate=>candidate!==page.mainFrame());
    if(!frame)throw new Error('Missing design frame');
    await frame.locator('#whale03-island').waitFor();
    await frame.waitForLoadState('load');
    await page.waitForTimeout(500);
    const iconCount=await frame.locator('.w3-phone svg').count();
    if(iconCount===0)throw new Error('Export icons not available offline: '+JSON.stringify({externalRequests,placeholders:await frame.locator('i[data-lucide]').count(),scriptSources:await frame.locator('script[src]').evaluateAll(elements=>elements.map(element=>element.getAttribute('src')))}));
    for(const theme of ['island','aurora','echo']) {
      if(theme!=='island')await frame.getByRole('button',{name:'下一方案',exact:true}).click();
      const phone=frame.locator('#whale03-'+theme);
      await phone.waitFor({state:'visible'});
      await phone.locator('[data-action="react"]').first().click();
      const responseNote=await phone.locator('[data-reaction-note]').innerText();
      if(!responseNote.includes('回应'))throw new Error('Touch response missing: '+JSON.stringify({theme,responseNote,phase:await phone.locator('.w3-scene').getAttribute('data-phase')}));
      await phone.locator('nav').getByRole('button',{name:'对话',exact:true}).click();
      await phone.getByRole('button',{name:'查看并确认',exact:true}).click();
      await phone.getByRole('dialog',{name:'创建提醒确认'}).waitFor();
      await phone.getByRole('button',{name:'关闭确认',exact:true}).click();
      await phone.locator('nav').getByRole('button',{name:'音乐',exact:true}).click();
      await phone.getByRole('button',{name:'播放',exact:true}).click();
      await phone.getByRole('button',{name:'暂停',exact:true}).waitFor();
      await phone.locator('nav').getByRole('button',{name:'我的',exact:true}).click();
      await phone.getByRole('checkbox',{name:'减少动效',exact:true}).check();
      if(await phone.getAttribute('data-motion')!=='quiet')throw new Error('Quiet mode failed');
      results.push({theme,schemeSwitch:'passed',touch:'passed',confirmation:'passed',music:'passed',quietMode:'passed'});
    }
    if(errors.length)throw new Error(errors.join(' | '));
    const report={status:'passed',url:targetUrl,pageTitle:await page.title(),schemes:results.length,iconCount,blockedExternalRequests:externalRequests,consoleErrors:errors,results,scope:'UI和动效演示，非真实AI或音频播放'};
    await fs.writeFile(path.join(__dirname,fileMode?'export-file-validation.json':'export-demo-validation.json'),JSON.stringify(report,null,2));
    console.log(JSON.stringify(report));
  } finally {await browser.close();}
}

checkExportedDemo().catch(error=>{console.error(error.message);process.exitCode=1;});
