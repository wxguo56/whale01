import { readFile, writeFile, mkdir, stat } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { taskReviews, caseReviews, scenarioReviews, findings } from './curated.mjs';

const projectRoot = resolve(import.meta.dirname, '../..');
const reviewRoot = import.meta.dirname;
const outputRoot = join(projectRoot, 'web', 'checklist-audit');
await mkdir(outputRoot, { recursive: true });
const readText = (relative) => readFile(join(projectRoot, relative), 'utf8');
const plain = (value) => value.replace(/`|\*\*/g, '').trim();

function rows(text, idPattern) {
  return text.split(/\r?\n/).filter(line => line.trim().startsWith('|')).map(line => line.split('|').slice(1,-1).map(plain)).filter(columns => idPattern.test(columns[0] || ''));
}

const tasksText = await readText('02_执行任务清单.md');
const casesText = await readText('03_验收用例.md');
const providerText = await readText('05_DeepSeek与讯飞接入说明.md');
const taskRows = rows(tasksText, /^(W01-\d{3}|UI-\d{2}|MU-\d{2}|NAV-\d{2}|NL-\d{2})$/);
const providerRows = rows(providerText, /^(DS|XF)-\d{2}$/);
const groupFor = (id) => id.startsWith('W01-') ? '主任务' : /^(DS|XF)-/.test(id) ? '模型与语音' : id.startsWith('UI-') ? '废弃UI' : /^(MU|NAV)-/.test(id) ? '音乐与导航' : '自然对话';
const tasks = [...taskRows.map(columns => ({id:columns[0],title:columns[1],expected:columns[4] || columns[3],group:groupFor(columns[0]),source:'02_执行任务清单.md'})),...providerRows.map(columns => ({id:columns[0],title:columns[1],expected:columns[3],group:groupFor(columns[0]),source:'05_DeepSeek与讯飞接入说明.md'}))].map(task => {
  if(!taskReviews[task.id])throw new Error('Missing task audit: '+task.id);
  return {...task,...taskReviews[task.id]};
});
const cases = rows(casesText, /^[ABCDFG]\d{2}$/).map(columns => {
  if(!caseReviews[columns[0]])throw new Error('Missing acceptance audit: '+columns[0]);
  return {id:columns[0],title:columns[1],expected:columns[2],group:columns[0][0],...caseReviews[columns[0]]};
});
if(tasks.length!==59 || cases.length!==76)throw new Error('Unexpected checklist cardinality: '+tasks.length+'/'+cases.length);
if(new Set(tasks.map(task=>task.id)).size!==tasks.length)throw new Error('Duplicate task IDs');

const stripAnsi = (text) => text.replace(/\u001b\[[0-9;]*m/g,'');
const testRun = async (name, env) => {
  const result=spawnSync(process.execPath,['--test'],{cwd:join(projectRoot,'backend'),env,encoding:'utf8',timeout:60000,maxBuffer:5_000_000});
  const output=stripAnsi((result.stdout || '')+'\n'+(result.stderr || ''));
  await writeFile(join(reviewRoot,name+'.txt'),output,'utf8');
  const number=(key)=>Number(output.match(new RegExp('(?:#|ℹ) '+key+' (\\d+)'))?.[1] || 0);
  return {exitCode:result.status,total:number('tests'),passed:number('pass'),failed:number('fail'),scope:'受控模型/Mock执行与接口测试，不是手机系统验收',path:'review/checklist-audit-2026-11-09/'+name+'.txt'};
};
const defaultTests=await testRun('backend-tests-default',{...process.env});
const isolatedTests=await testRun('backend-tests-isolated',{...process.env,MODEL_MODE:'mock',EXECUTION_MODE:'mock'});
const quality=JSON.parse(await readText('quality/reports/conversation-eval.latest.json'));
const commit=spawnSync('git',['rev-parse','--short','HEAD'],{cwd:projectRoot,encoding:'utf8'}).stdout.trim();
const dirty=spawnSync('git',['status','--porcelain'],{cwd:projectRoot,encoding:'utf8'}).stdout.trim().split(/\r?\n/).filter(Boolean).length;
const packageScript='import sys,zipfile,plistlib,struct,hashlib,json; package_path=sys.argv[1]; archive=zipfile.ZipFile(package_path); names=archive.namelist(); info_path=next(name for name in names if name.startswith("Payload/") and name.endswith(".app/Info.plist")); info=plistlib.loads(archive.read(info_path)); app_root=info_path.rsplit("/",1)[0]; binary=archive.read(app_root+"/"+info["CFBundleExecutable"]); cpu_type=struct.unpack("<II",binary[:8])[1]; print(json.dumps({"version":info.get("CFBundleShortVersionString"),"build":info.get("CFBundleVersion"),"platform":info.get("DTPlatformName"),"architecture":"arm64" if cpu_type==0x0100000c else hex(cpu_type),"profileEmbedded":app_root+"/embedded.mobileprovision" in names,"webFileCount":len([name for name in names if name.endswith((".html",".css",".js"))]),"environmentFileCount":len([name for name in names if name.endswith((".env",".p8",".p12"))]),"sha256":hashlib.sha256(open(package_path,"rb").read()).hexdigest()}))';
const packageResult=spawnSync('C:/Users/hzwangxiuguo/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe',['-c',packageScript,join(projectRoot,'release/WhaleAgent-Sideload.ipa')],{encoding:'utf8'});
if(packageResult.status!==0)throw new Error('IPA metadata check failed');
const packageInfo=JSON.parse(packageResult.stdout);
const sourceFiles=['02_执行任务清单.md','03_验收用例.md','00_执行看板.md','13_UI方案废弃决定.md','ios/project.yml','backend/src/server.mjs','backend/test/helpers.mjs','ios/WhaleAgent/Execution/LocationExecutor.swift','ios/WhaleAgent/Execution/PermissionCenter.swift','ios/WhaleAgent/Execution/OperationLedger.swift','ios/WhaleAgent/Execution/MessageExecutor.swift','ios/WhaleAgent/Networking/AgentClient.swift','quality/reports/conversation-eval.latest.json'];
const sourceSnapshot=[];
for(const relative of sourceFiles){const content=await readFile(join(projectRoot,relative));const metadata=await stat(join(projectRoot,relative));sourceSnapshot.push({path:relative,sha256:createHash('sha256').update(content).digest('hex'),modifiedAt:metadata.mtime.toISOString()});}

const evidence = [
  {id:'source',title:'任务与当前看板',kind:'源码/执行记录',path:'00_执行看板.md',note:'旧行与后续追加冲突，以当前源码、构建、设备反馈分层判断。'},
  {id:'contracts',title:'工具/事件契约',kind:'源码+测试',path:'contracts/v1/tools.v1.json',note:'15个工具与输入Schema；无当前位置模式/半径/价格服务字段。'},
  {id:'tests',title:'本次后端复跑',kind:'本次执行',path:isolatedTests.path,note:`默认环境 ${defaultTests.passed}/${defaultTests.total}；隔离Mock环境 ${isolatedTests.passed}/${isolatedTests.total}。含helpers文件条目，不能当76项验收。`},
  {id:'test-env',title:'默认测试失败与环境隔离',kind:'本次执行+源码',path:defaultTests.path,note:'测试继承本地EXECUTION_MODE，HTTP测试未带defer。隔离后通过；测试夹具需固定执行模式。'},
  {id:'eval',title:'既有真实DeepSeek基准',kind:'结构化执行报告',path:'quality/reports/conversation-eval.latest.json',note:`模型 ${quality.model}；执行 ${quality.executionMode}；确定性 ${quality.deterministicPassed}/${quality.total}；manualNotes并非签收结果。`},
  {id:'stream',title:'流式适配与网页恢复',kind:'源码+测试+执行记录',path:'backend/src/adapters.mjs',note:'上游SSE参数组装有本次测试；网页轮询恢复有记录；iOS客户端仍使用JSON。'},
  {id:'build',title:'原生源码与云构建',kind:'本地产物+CI记录',path:'.github/workflows/ios-sideload-ipa.yml',note:'iPhoneOS未签名IPA已生成；当前0.2.1(5)；远端CI本轮未重新运行/登录核验。'},
  {id:'package',title:'当前固定IPA',kind:'本地包检查',path:'release/WhaleAgent-Sideload.ipa',note:'仅报告版本/平台/签名状态，不公开设备ID、证书或密钥。'},
  {id:'ios',title:'原生UI与执行路由',kind:'源码/编译记录',path:'ios/WhaleAgent/Execution/NativeToolRouter.swift',note:'14个设备工具路由；不能以编译成功代替系统操作验收。'},
  {id:'eventkit',title:'真实EventKit保存逻辑',kind:'源码',path:'ios/WhaleAgent/Execution/EventKitExecutor.swift',note:'保存提醒/事件，并为带日期提醒增加EKAlarm；当前Build系统结果仍需核对。'},
  {id:'ledger',title:'手机幂等与崩溃窗',kind:'源码',path:'ios/WhaleAgent/Execution/OperationLedger.swift',note:'仅outcome缓存与成功后record；无完整执行前日志/崩溃核对。'},
  {id:'auth',title:'后端身份与会话检查',kind:'源码',path:'backend/src/server.mjs',note:'无认证与所有权校验；不同会话历史分开不等于访问控制。'},
  {id:'location',title:'定位与地图',kind:'源码',path:'ios/WhaleAgent/Execution/LocationExecutor.swift',note:'只用near/region，未实际取当前定位；regions为偏好而非严格半径；见16整改。'},
  {id:'health',title:'健康读取许可',kind:'源码',path:'ios/WhaleAgent/Execution/PermissionCenter.swift',note:'正式构建的请求成功标granted不可靠；当前免费包已禁用。'},
  {id:'limitations',title:'免费构建边界',kind:'构建配置/源码',path:'ios/project.yml',note:'FREE_SIGNING禁用get_weather/get_activity_summary；不是原需求验收通过或永久取消。'},
  {id:'message',title:'联系人与MessageUI',kind:'源码',path:'ios/WhaleAgent/Execution/MessageExecutor.swift',note:'首个联系人/号码；回调仅dismiss，未返回发送/取消业务结果。'},
  {id:'music',title:'真实音乐实现',kind:'源码/编译',path:'ios/WhaleAgent/Execution/MusicExecutor.swift',note:'MusicKit授权/搜索/控制已有，真实曲目条件和队列边界未登记。'},
  {id:'voice',title:'0.2.1系统语音输入',kind:'源码/构建',path:'ios/WhaleAgent/Input/VoiceInputController.swift',note:'Apple Speech + AVAudioEngine；不是讯飞，当前版本真实授权/转写待复验。'},
  {id:'supplier',title:'讯飞原定路线',kind:'任务与源码检索',path:'05_DeepSeek与讯飞接入说明.md',note:'未发现讯飞ASR/TTS实现；产品/鉴权缺，系统Speech为替代偏差。'},
  {id:'share',title:'分享与正文交接',kind:'模块检索',path:'ios/project.yml',note:'未发现Share Extension/App Group；后端摘要与真实分享入口不同。'},
  {id:'intents',title:'Siri/快捷指令',kind:'模块检索',path:'ios/',note:'未发现AppIntents实现。'},
  {id:'recovery',title:'手机恢复实现范围',kind:'源码',path:'ios/WhaleAgent/App/AppModel.swift',note:'activeTurnId/results在内存；无完整场景持久化与重传，URLSession等待连接不等于业务恢复。'},
  {id:'navigation',title:'网页与原生导航差异',kind:'源码/HTML记录',path:'ios/WhaleAgent/UI/RootView.swift',note:'原生TabView无back/forward历史；Web已有对应自测。'},
  {id:'html-review',title:'HTML修正记录',kind:'既有浏览器复核',path:'review/2026-11-09-phase1/修正记录.md',note:'R01–R06、模拟音乐及G06–G12；390px浏览器不是iPhoneSafari或原生证明。'},
  {id:'ui-decision',title:'UI弃用决定',kind:'用户明确决定',path:'13_UI方案废弃决定.md',note:'旧5个风格取消/冻结；不计作欠完成产品，也不恢复旧设计。'},
  {id:'historical-device',title:'旧版提醒系统记录报告',kind:'报告已做/原始证据待补',path:'review/2026-11-09-phase3/真实iOS执行接入.md',note:'文档报告0.1.0曾写入提醒及通知，但未找到对应完整编号记录与原始系统截图；不能转记0.2.1通过。'},
  {id:'device',title:'本对话用户手机运行反馈',kind:'用户提供的设备截图/描述',path:null,note:'能确认原生App曾运行/通信；不公开截图中的个人资料，不当作所有功能已验。'},
  {id:'device-feedback',title:'当前定位与价格失败反馈',kind:'用户截图+源码核对',path:'16_定位与价格任务闭环整改.md',note:'对应当前位置实现缺口、无价格源与超能力预算承诺；未算入原03用例分母。'},
  {id:'acceptance-register',title:'真机编号记录',kind:'验收文档',path:'web/真机验收清单.md',note:'H01–H39结果仍空；03的76项未见当前Build逐项结果表。'},
  {id:'performance',title:'性能验收要求',kind:'要求/未见测量报告',path:'03_验收用例.md',note:'无每场景至少20样本、p50/p95、网络/设备/ASR/模型/工具/TTS分段统计。'},
  {id:'pages',title:'GitHub Pages限制',kind:'执行记录',path:'.github/workflows/pages.yml',note:'工作流存在；当前私有仓库套餐不支持Pages，不能自动改成公开。'},
  {id:'secrets',title:'密钥边界静态检查',kind:'只检查忽略与文件名',path:'.gitignore',note:'backend/.env被忽略未跟踪；未读取/公开实际密钥、配对文件或设备UDID。'}
];
const scenarios=Object.entries(scenarioReviews).map(([id,entry])=>({id,title:{E01:'真实提醒闭环',E02:'日历多步闭环',E03:'地图交接闭环'}[id],...entry}));
const safari=rows(await readText('web/真机验收清单.md'),/^H\d{2}$/).map(columns=>({id:columns[0],title:columns[1],expected:columns[2],status:'unverified',note:'当前文档结果栏仍为空；已有电脑/模拟证据不能转记Safari逐项通过。'}));
const countStatus=(items)=>items.reduce((counts,item)=>{counts[item.status]=(counts[item.status]||0)+1;return counts;},{});
const data={
  project:'代号鲸鱼01',clientDate:'2026-11-09',timezone:'Asia/Shanghai',snapshotAt:new Date().toISOString(),commit,workingTreePendingEntries:dirty,
  package:packageInfo,
  method:'按原任务交付与03最低允许证据层级审计。已实现≠已构建≠已安装≠完整真机验收；未见证据不等于一定没做。',
  verdict:'模块基本沿清单推进，验收未按编号/版本/系统证据完整闭环。当前不支持宣布M1–M4全部验收通过。',
  tasks,cases,scenarios,safari,evidence,findings,sourceSnapshot,
  tests:{default:defaultTests,isolated:isolatedTests},quality:{model:quality.model,executionMode:quality.executionMode,total:quality.total,deterministicPassed:quality.deterministicPassed,finishedAt:quality.finishedAt,semanticSignoff:'未见逐条人工通过判定；manualNotes是复核要求'},
  counts:{tasks:tasks.length,mainTasks:tasks.filter(task=>task.group==='主任务').length,taskStatuses:countStatus(tasks),mainTaskStatuses:countStatus(tasks.filter(task=>task.group==='主任务')),cases:cases.length,caseStatuses:countStatus(cases),scenarios:scenarios.length,safari:safari.length},
  milestones:[
    {name:'M0 盘点/契约',status:'基本具备',note:'原生+云构建+契约已有；旧盘点需刷新，原有能力复用及供应商条件仍有缺项。'},
    {name:'M1 提醒闭环',status:'未完整签收',note:'旧版写入有报告；当前版本E01、拒绝/去重/断网/系统证据未齐。'},
    {name:'M2 系统能力',status:'部分实现',note:'代码多已编译；GPS/地区降级有缺口，天气/健康当前被禁用，系统回归未完成。'},
    {name:'M3 Beta体验',status:'未达完整门槛',note:'系统Speech临时代替讯飞；TTS、分享、AppIntents、角色反馈缺；旧UI仅归档。'},
    {name:'M4 交付/回归',status:'部分交付',note:'后台测试、云构建和侧载IPA已有；性能、全量真机及正式Beta未签收。'}
  ],
  nextSteps:[
    '先核对手机当前Build，补E01同任务的权限→确认→系统记录→回传→去重证据；旧版结果不冒充新版。',
    '修鉴权/会话绑定、执行前日志与原生结果恢复；这几项属于原清单P0缺口。',
    '落实16整改的当前定位/地区降级/半径，价格来源属于新增需求，明确后接入。',
    '补日历、地图、联系人/MessageUI、音乐真实回归，逐个填写03编号。',
    '确认语音供应商：保留系统Speech临时实现，或按原计划补讯飞ASR/TTS；不能混记。',
    '完成分享/AppIntents、性能和适用Beta交付；旧UI不再实施，报告不新建UI方案。'
  ]
};
for(const item of [...tasks,...cases,...scenarios])for(const id of item.evidence)if(!evidence.some(entry=>entry.id===id))throw new Error('Missing evidence '+id);
await writeFile(join(outputRoot,'audit-data.json'),JSON.stringify(data,null,2),'utf8');
await writeFile(join(reviewRoot,'audit-data.json'),JSON.stringify(data,null,2),'utf8');
const template=await readFile(join(reviewRoot,'template.html'),'utf8');
const document=template.replace('__AUDIT_DATA__',JSON.stringify(data).replaceAll('<','\\u003c'));
await writeFile(join(outputRoot,'index.html'),document,'utf8');
await writeFile(join(reviewRoot,'index.html'),document,'utf8');
console.log(JSON.stringify({outputRoot,taskCount:tasks.length,acceptanceCount:cases.length,scenarios:scenarios.length,safari:safari.length,defaultTests,isolatedTests,caseStatuses:data.counts.caseStatuses,mainTaskStatuses:data.counts.mainTaskStatuses}));
