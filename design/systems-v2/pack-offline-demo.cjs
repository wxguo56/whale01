const fs = require('node:fs/promises');
const path = require('node:path');

async function packOfflineDemo() {
  const exportRoot = 'F:/VS_t/代号鲸鱼01/web/design-v2';
  try {
    await fs.access(path.join(exportRoot,'DEPRECATED.json'));
    throw new Error('本批UI方案已废弃，禁止重新打包或恢复旧演示；见13_UI方案废弃决定.md。');
  } catch(error) {
    if(error.code!=='ENOENT')throw error;
  }
  const indexPath = path.join(exportRoot,'index.html');
  let document = await fs.readFile(indexPath,'utf8');
  const dependencies = [
    {name:'floating-ui-core-1.7.3.js',url:'https://unpkg.com/@floating-ui/core@1.7.3/dist/floating-ui.core.umd.min.js'},
    {name:'floating-ui-dom-1.7.4.js',url:'https://unpkg.com/@floating-ui/dom@1.7.4/dist/floating-ui.dom.umd.min.js'},
    {name:'lucide-1.17.0.js',url:'https://unpkg.com/lucide@1.17.0/dist/umd/lucide.js'}
  ];
  const cacheRoot = path.join(exportRoot,'vendor');
  await fs.mkdir(cacheRoot,{recursive:true});
  const downloaded = await Promise.all(dependencies.map(async dependency=>{
    const cachedPath = path.join(cacheRoot,dependency.name);
    let source;
    try {source=await fs.readFile(cachedPath);}
    catch(error) {
      if(error.code!=='ENOENT')throw error;
      const response=await fetch(dependency.url,{signal:AbortSignal.timeout(25000)});
      if(!response.ok)throw new Error('Dependency download failed: '+dependency.name+' HTTP '+response.status);
      source=Buffer.from(await response.arrayBuffer());
      await fs.writeFile(cachedPath,source);
    }
    return {...dependency,bytes:source.length,dataUrl:'data:application/javascript;base64,'+source.toString('base64')};
  }));
  for(const dependency of downloaded)document=document.split(dependency.url).join(dependency.dataUrl);
  await fs.writeFile(indexPath,document,'utf8');
  const manifest={purpose:'独立HTML演示资源打包；保留固定版本第三方库及原有许可证说明',dependencies:downloaded.map(({name,url,bytes})=>({name,url,bytes})),singleFileBytes:Buffer.byteLength(document),indexPath};
  await fs.writeFile(path.join(exportRoot,'export-manifest.json'),JSON.stringify(manifest,null,2));
  console.log(JSON.stringify(manifest));
}

packOfflineDemo().catch(error=>{console.error(error.message);process.exitCode=1;});
