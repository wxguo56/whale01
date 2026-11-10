"use strict";
const directions=[
  {id:"a",letter:"A",name:"版式",english:"EDITORIAL",brand:"鲸鱼。",defaultTheme:"light",tabs:["现在","留下的","我的"],replyLabel:"鲸鱼 / 回应",voiceClass:"editorial-voice",summary:"大文字、编号与细线建立层次。<strong>适合阅读和日常办事。</strong>"},
  {id:"b",letter:"B",name:"折光",english:"PRISM",brand:"WHALE",defaultTheme:"dark",tabs:["对话","任务","设置"],replyLabel:"鲸鱼 · 任务回应",voiceClass:"prism-voice",summary:"几何光片与分层材质形成空间感。<strong>科技辨识度最强。</strong>"},
  {id:"c",letter:"C",name:"涂鸦",english:"DOODLE",brand:"小鲸鱼",defaultTheme:"light",tabs:["聊聊","小事","偏好"],replyLabel:"鲸鱼在这",voiceClass:"doodle-voice",summary:"原创手绘角色、卡带和纸张形成识别。<strong>更适合亲切交流。</strong>"}
];
const pages=[{id:"home",name:"主界面"},{id:"chat",name:"找店与对话"},{id:"voice",name:"语音"},{id:"music",name:"音乐"},{id:"records",name:"记录"},{id:"profile",name:"偏好设置"},{id:"content",name:"内容摘要"},{id:"confirm",name:"提醒确认"},{id:"unknown",name:"结果待核对"},{id:"empty",name:"空曲库"}];
const places=[{name:"清木炭火",distance:"680m",price:88},{name:"小巷烧烤",distance:"1.2km",price:96},{name:"晚风烤串",distance:"1.7km",price:null}];
const tracks=[{title:"午后窗边",artist:"示例曲目 · 器乐",duration:"3:25"},{title:"慢慢走",artist:"示例曲目 · 轻音乐",duration:"4:12"},{title:"留一盏灯",artist:"示例曲目 · 吉他",duration:"3:48"}];
const qs=new URLSearchParams(location.search);
const state={page:pages.some(p=>p.id===qs.get("page"))?qs.get("page"):"home",theme:["light","dark"].includes(qs.get("theme"))?qs.get("theme"):"default",focus:directions.some(d=>d.id===qs.get("design"))?qs.get("design"):"all",large:qs.get("text")==="large",keyboard:qs.get("keyboard")==="show",modal:null,place:0,budget:false,chatMode:"places",userText:"",draft:"",voice:"listening",muted:false,playing:false,musicStarted:false,track:0,prefs:["不吃辣","回答简短"],prefDraft:"",saved:null,editing:false,reminder:{title:"取快递",date:"2026-11-10",time:"15:00"},routinePaused:false,toast:"",choice:""};
let voiceTimer,toastTimer;
state.voiceOrigin={page:"home",modal:null};
try{const savedChoice=localStorage.getItem("whale.ui.v4.choice");if(directions.some(d=>d.id===savedChoice))state.choice=savedChoice;}catch{}
if(qs.get("mode")==="app"){document.body.dataset.mode="app";if(state.focus==="all")state.focus="a";}
if(state.page==="confirm"){state.modal="reminder";state.chatMode="pending";}
const $=selector=>document.querySelector(selector);
function effectiveTheme(d){return state.theme==="default"?d.defaultTheme:state.theme;}
const composerPages=["home","chat","content","confirm","unknown"];
function keyboardVisible(s){return s.keyboard&&s.page!=="voice"&&(composerPages.includes(s.page)||["reminder","preferences"].includes(s.modal));}
function pageView(d,s){return ({home:homeView,chat:chatView,voice:voiceView,music:musicView,records:recordsView,profile:profileView,content:contentView,confirm:chatView,unknown:unknownView,empty:emptyView})[s.page](d,s);}
function render(){
  for(const d of directions){
    const card=$(`#card-${d.id}`),phone=$(`#phone-${d.id}`),app=$(`#app-${d.id}`);card.hidden=state.focus!=="all"&&state.focus!==d.id;card.classList.toggle("chosen",state.choice===d.id);phone.dataset.theme=effectiveTheme(d);phone.classList.toggle("large",state.large);
    const voice=state.page==="voice",keyboardOn=keyboardVisible(state);
    app.innerHTML=appHeader(d,state)+`<main class="app-content">${pageView(d,state)}</main>`+(voice?voiceFooter(d,state):"")+(!voice&&state.musicStarted&&state.page!=="music"&&!keyboardOn?miniPlayer(d,state):"")+(composerPages.includes(state.page)?composer(d,state):"")+(!voice&&!keyboardOn?tabs(d,state):"")+(keyboardOn?keyboardView():"")+modalView(d,state)+(state.toast?`<div class="toast" role="status">${e(state.toast)}</div>`:"");
    [...app.children].forEach(child=>{child.inert=Boolean(state.modal)&&!child.classList.contains("overlay")&&!child.classList.contains("keyboard-mock")&&!child.classList.contains("toast");});
    const pick=card.querySelector(".pick-button");pick.textContent=state.choice===d.id?"已暂选":"暂选这套";pick.setAttribute("aria-pressed",String(state.choice===d.id));
  }
  $("#designGrid").classList.toggle("single",state.focus!=="all");
  document.querySelectorAll("[data-focus]").forEach(b=>b.setAttribute("aria-pressed",String(b.dataset.focus===state.focus)));
  $("#pageSelect").value=state.page;$("#themeSelect").value=state.theme;$("#largeText").checked=state.large;$("#keyboardToggle").checked=state.keyboard;
  $("#choiceStatus").textContent=state.choice?`当前倾向：${directions.find(d=>d.id===state.choice).letter} ${directions.find(d=>d.id===state.choice).name} · 仅用于比较`:"尚未暂选方案";
  fitScales();
}
function fitScales(){for(const d of directions){const card=$(`#card-${d.id}`);if(card.hidden)continue;const width=card.clientWidth;const scale=Math.min(state.focus==="all"?.90:1,(width-4)/418);card.querySelector(".phone-stage").style.setProperty("--scale",Math.max(.3,scale).toFixed(3));}}
function go(page){clearTimeout(voiceTimer);if(page==="voice"&&state.page!=="voice")state.voiceOrigin={page:state.page,modal:state.modal};state.page=page;state.modal=page==="confirm"?"reminder":null;if(page==="confirm"){state.chatMode="pending";state.editing=false;state.reminder={title:"取快递",date:"2026-11-10",time:"15:00"};}if(page==="chat"){state.chatMode="places";state.budget=false;}if(page==="voice"){state.voice="listening";state.muted=false;}render();}
function returnToText(){clearTimeout(voiceTimer);state.page=state.voiceOrigin.page;state.modal=state.voiceOrigin.modal;state.muted=false;render();}
function openReminder(editing=false,custom=null){clearTimeout(voiceTimer);state.editing=editing;state.reminder=custom||(editing&&state.saved?{...state.saved}:{title:"取快递",date:"2026-11-10",time:"15:00"});state.page="confirm";state.chatMode="pending";state.modal="reminder";render();}
function announce(text){clearTimeout(toastTimer);state.toast=text;render();toastTimer=setTimeout(()=>{state.toast="";render();},1700);}
function send(design){if(!state.draft.trim()){if(design!=="b")go("voice");return;}state.userText=state.draft.trim();state.draft="";state.chatMode="text";state.page="chat";state.modal=null;render();}
$("#pageSelect").innerHTML=pages.map(p=>`<option value="${p.id}">${p.name}</option>`).join("");
$("#designGrid").innerHTML=directions.map(d=>`<article class="design-card" id="card-${d.id}"><header class="card-heading"><div class="direction-name"><span class="direction-letter">${d.letter}</span><div><h2>${d.name}</h2><p>${d.english}</p></div></div><button class="pick-button" data-pick="${d.id}" aria-label="暂选${d.letter} ${d.name}">暂选这套</button></header><div class="phone-stage"><div class="device"><div class="phone" id="phone-${d.id}" data-design="${d.id}" data-theme="${d.defaultTheme}"><div class="system-bar" aria-hidden="true"><b>9:41</b><span class="island"></span><span class="system-signal">▮▮▮ ▰</span></div><div class="app" id="app-${d.id}"></div><div class="home-bar" aria-hidden="true"></div></div></div></div><p class="direction-summary">${d.summary}</p></article>`).join("");
document.addEventListener("click",event=>{
  const focus=event.target.closest("[data-focus]");if(focus){state.focus=focus.dataset.focus;render();return;}
  const pick=event.target.closest("[data-pick]");if(pick){state.choice=state.choice===pick.dataset.pick?"":pick.dataset.pick;try{if(state.choice)localStorage.setItem("whale.ui.v4.choice",state.choice);else localStorage.removeItem("whale.ui.v4.choice");}catch{}render();return;}
  const page=event.target.closest("[data-page]");if(page){go(page.dataset.page);return;}
  const button=event.target.closest("[data-action]");if(!button||button.disabled)return;const action=button.dataset.action;
  if(action==="return-text"){returnToText();return;}
  if(["home","chat","voice","music","records","profile","content","unknown","empty"].includes(action)){go(action);return;}
  if(action==="confirm"){openReminder();return;}
  if(action==="edit-reminder"){openReminder(true);return;}
  if(action==="content-reminder"){openReminder(false,{title:"报名摄影分享会",date:"2026-11-13",time:"18:00"});return;}
  if(action==="place"||action==="source"){state.place=Number(button.dataset.place);state.modal=action;render();return;}
  if(action==="budget"){state.budget=!state.budget;render();return;}
  if(action==="close-modal"){state.modal=null;render();return;}
  if(action==="cancel-reminder"){state.modal=null;state.page="home";render();announce("这次安排已取消 · 示例");return;}
  if(action==="save-reminder"){
    if(!state.reminder.title.trim()||!state.reminder.date||!state.reminder.time){const dialog=button.closest(".sheet");let error=dialog.querySelector('[role="alert"]');if(!error){error=document.createElement("p");error.className="caption";error.setAttribute("role","alert");dialog.querySelector(".sheet-actions").prepend(error);}error.textContent="请补齐事项、日期和时间。";return;}
    state.saved={...state.reminder,title:state.reminder.title.trim()};state.chatMode="saved";state.modal=null;state.page="chat";render();return;
  }
  if(action==="preferences"){state.prefDraft=state.prefs.join("，");state.modal="preferences";render();return;}
  if(["permissions","routine","attachment","import"].includes(action)){state.modal=action;render();return;}
  if(action==="save-preferences"){state.prefs=state.prefDraft.split(/[，,]/).map(p=>p.trim()).filter(Boolean).slice(0,6);state.modal=null;render();return;}
  if(action==="pause-routine"){state.routinePaused=!state.routinePaused;render();return;}
  if(action==="theme"){const d=directions.find(d=>d.id===button.closest(".phone").dataset.design);state.theme=effectiveTheme(d)==="dark"?"light":"dark";render();return;}
  if(action==="play"){state.musicStarted=true;state.playing=!state.playing;render();return;}
  if(action==="next"||action==="previous"||action==="track"){state.track=action==="track"?Number(button.dataset.track):(state.track+(action==="next"?1:tracks.length-1))%tracks.length;state.musicStarted=true;state.playing=true;render();return;}
  if(action==="finish-import"){state.modal=null;state.page="music";render();announce("3首示例曲目已加入");return;}
  if(action==="map"){state.modal=null;render();announce("地点交给地图 · 交接反馈示例");return;}
  if(action==="mute"){state.muted=!state.muted;render();return;}
  if(action==="voice-step"){clearTimeout(voiceTimer);if(state.muted){state.muted=false;state.voice="listening";render();return;}if(state.voice==="listening"){state.voice="thinking";render();voiceTimer=setTimeout(()=>{if(state.page==="voice"){state.voice="speaking";render();}},900);}else{state.voice="listening";render();}return;}
  if(action==="hide-keyboard"){state.keyboard=false;render();}
});
document.addEventListener("input",event=>{
  const target=event.target;
  if(target.dataset.field==="message"){state.draft=target.value;document.querySelectorAll('[data-field="message"]').forEach(input=>{if(input!==target)input.value=state.draft;const button=input.closest("form").querySelector('[type="submit"]');if(input.closest(".phone").dataset.design==="b"){button.hidden=!state.draft.trim();return;}button.classList.toggle("send",!!state.draft);button.setAttribute("aria-label",state.draft?"发送消息":"开始语音");button.innerHTML=i(state.draft?"arrow":"mic");});}
  if(target.dataset.reminder){state.reminder[target.dataset.reminder]=target.value;document.querySelectorAll(`[data-reminder="${target.dataset.reminder}"]`).forEach(input=>{if(input!==target)input.value=target.value;});}
  if(target.dataset.field==="preferences"){state.prefDraft=target.value;document.querySelectorAll('[data-field="preferences"]').forEach(input=>{if(input!==target)input.value=target.value;});}
});
document.addEventListener("submit",event=>{if(event.target.dataset.form==="message"){event.preventDefault();send(event.target.closest(".phone").dataset.design);}});
document.addEventListener("keydown",event=>{if(event.key==="Escape"&&state.modal){state.modal=null;render();}});
$("#pageSelect").addEventListener("change",event=>go(event.target.value));
$("#themeSelect").addEventListener("change",event=>{state.theme=event.target.value;render();});
$("#largeText").addEventListener("change",event=>{state.large=event.target.checked;render();});
$("#keyboardToggle").addEventListener("change",event=>{state.keyboard=event.target.checked;render();});
window.addEventListener("resize",fitScales);
render();
