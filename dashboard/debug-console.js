/* Correlated live audit. Model content is text, never executable markup. */
(()=>{
 const el=id=>document.getElementById(id),pretty=v=>typeof v==='string'?v:JSON.stringify(v,null,2);
 const phase={requesting:'请求中',returned:'已返回',submitted:'等待引擎',executed:'引擎已执行',waiting:'保持当前行动',rejected:'拒绝',error:'调用失败',discarded:'旧回复已丢弃'};
 const node=(tag,text)=>{const n=document.createElement(tag);n.textContent=text;return n};
 let debugBusy=false;
 let run='',busy=false,chosen='',detailStamp='',generation=0,lastUnits='',lastDebug='';
 const selector=el('debugUnit'),calls=el('liveLogCalls'),follow=el('liveLogFollow'),toggle=el('debugToggle');
 el('liveLogFull').onclick=()=>el('openLLMLog').click();
 async function get(url){const r=await fetch(url);if(!r.ok)throw Error('HTTP '+r.status);return r.json()}
 async function applyDebug(){const value=toggle.checked,unit=selector.value;debugBusy=true;toggle.disabled=true;try{await awaitReceipt(await command({action:'debug_visualize',value,unit}));const deadline=Date.now()+5000;while(Date.now()<deadline&&(state.debug_visualize?.enabled!==value||state.debug_visualize?.unit!==unit))await new Promise(r=>setTimeout(r,100))}catch(e){toast(messageText(e.message))}finally{debugBusy=false;window.renderDebugConsole()}}
 const drawer=el('debugVersionPanel'),openButton=el('openDebugVersion');
 const sections=[document.querySelector('.debug-controls'),el('liveLLM')];
 const homes=sections.map(section=>{const home=document.createComment('debug home');section.before(home);return home});
 async function debugVersion(open){
  drawer.hidden=!open;document.body.classList.toggle('debug-version',open);
  openButton.setAttribute('aria-expanded',String(open));openButton.textContent=open?'关闭 Debug Version':'打开 Debug Version';
  sections.forEach((section,i)=>open?el('debugVersionContent').append(section):homes[i].after(section));
  if(live&&state.debug_visualize?.enabled!==open){toggle.checked=open;await applyDebug()}
 }
 openButton.onclick=()=>debugVersion(drawer.hidden);
 el('closeDebugVersion').onclick=()=>debugVersion(false);
 el('resetCamera').onclick=async()=>{
  try{await awaitReceipt(await command({action:'camera',mode:'battle'}));
  if(state.eastfront?.enabled)await awaitReceipt(await command({action:'eastfront_follow',value:true}));}catch(e){toast(messageText(e.message))}
 };
 toggle.onchange=applyDebug;
 selector.onchange=()=>{generation++;chosen='';detailStamp='';calls.replaceChildren(new Option('正在筛选…',''));el('liveLogBody').replaceChildren(node('p','正在读取该单位本局日志…'));if(toggle.checked)applyDebug();refresh()};
 calls.onchange=()=>{follow.checked=false;chosen=calls.value;detailStamp='';refresh()};
 follow.onchange=()=>{if(follow.checked){chosen='';detailStamp='';refresh()}};
 function renderRow(row){
  const body=el('liveLogBody');const scroll=body.scrollTop;const opens=[...body.querySelectorAll('details')].map(d=>d.open);body.replaceChildren();
  el('liveLogMeta').textContent=`#${row.id} · ${row.unit_id} · Tick ${row.tick} · ${new Date(row.started_at*1000).toLocaleTimeString()}\n${row.model} · ${phase[row.phase]||row.phase} · ${row.latency_ms??'—'} ms\n局次 ${row.run_id}`;
  function section(title,value){body.append(node('h4',title),node('pre',pretty(value)))}
  const obs=row.request?.state??row.request?.messages?.find(m=>m.role==='user')?.content;let input=obs;try{input=JSON.parse(obs)}catch{}
  section('IN / 发送给 LLM 的战场状态',input??'请求尚未记录');
  const full=node('details','');full.append(node('summary','完整输入（含 system 与参数）'),node('pre',pretty(row.request)));body.append(full);
  if(row.request?.questions)section('模型 / 结构化问题',row.request.questions);
  if(row.jev_evaluation)section('JEV / 概率与判断',row.jev_evaluation);
  section('OUT / 模型返回的行动与理由',row.parsed_response??row.error??'等待模型返回…');
  const raw=node('details','');raw.append(node('summary','原始返回正文'),node('pre',row.response_text??'尚无返回正文'));body.append(raw);
  section('ACK / 引擎校验与执行',{phase:row.phase,command_id:row.command_id??null,decision:row.decision??null,receipt:row.receipt??null,error:row.error??null,discard_reason:row.discard_reason??null});
  [...body.querySelectorAll('details')].forEach((d,i)=>d.open=opens[i]||false);body.scrollTop=scroll;
 }
 async function refresh(){
  if(busy||!state.run_id||!sessionCurrent)return;busy=true;const g=generation,localRun=state.run_id;
  try{
   const q=new URLSearchParams({run:localRun});if(selector.value)q.set('unit',selector.value);
   const data=await get('/api/lm/calls?'+q);if(g!==generation||localRun!==state.run_id)return;
   const items=data.items;
   if(follow.checked)chosen=String((items.find(r=>r.phase!=='requesting')||items[0])?.id||'');
   if(!chosen&&items.length)chosen=String(items[0].id);
   const pinned=[...calls.options].find(o=>o.value===chosen);
   calls.replaceChildren(...items.map(r=>new Option(`#${r.id} · ${r.unit_id} · ${phase[r.phase]||r.phase}`,String(r.id))));
   if(chosen&&!items.some(r=>String(r.id)===chosen)&&pinned)calls.append(pinned);
   if(!items.length)calls.append(new Option('本局暂无调用',''));calls.value=chosen;
   el('liveLogStatus').dataset.error='false';el('liveLogStatus').textContent=!live?'引擎离线 · 保留最后日志':!lm.configured&&!lm.frontier?.fast_provider?'LLM 未配置 · 当前只能本地自保':items.length?'真实输入 → 模型指令 → 引擎回执':'等待本局 LLM 请求；旧局日志在「完整日志」中';
   if(lm.metrics?.last_error==='provider_account_overdue'){el('liveLogStatus').dataset.error='true';el('liveLogStatus').textContent='火山方舟账户欠费 · 已记录真实错误返回；本地自保不是模型决策'}
   if(chosen){
    const row=await get('/api/lm/calls/'+chosen);if(g!==generation||localRun!==state.run_id||String(row.id)!==chosen)return;
    const stamp=row.id+':'+row.updated_at;if(stamp!==detailStamp){renderRow(row);detailStamp=stamp}
   }else{el('liveLogBody').replaceChildren(node('p','本局尚未收到模型调用。'));el('liveLogMeta').textContent=''}
  }catch(e){el('liveLogStatus').dataset.error='true';el('liveLogStatus').textContent='日志读取失败：'+e.message}finally{busy=false}
 }
 window.renderDebugConsole=()=>{
  if(run!==state.run_id){run=state.run_id;generation++;chosen='';detailStamp='';calls.replaceChildren();el('liveLogBody').replaceChildren(node('p','新对局，等待 LLM 输入输出…'));el('liveLogMeta').textContent=''}
  const key=(state.units||[]).map(u=>u.id).join(',');if(key!==lastUnits){lastUnits=key;const selected=selector.value;selector.replaceChildren(new Option('全部单位',''),...(state.units||[]).map(u=>new Option(u.id,u.id)));selector.value=[...selector.options].some(o=>o.value===selected)?selected:''}
  const debug=state.debug_visualize||{};toggle.disabled=debugBusy||!live;if(!debugBusy)toggle.checked=!!debug.enabled;
  el('debugDecisions').hidden=!debug.enabled;
  const stamp=JSON.stringify([debug,lm.units]);if(stamp===lastDebug)return;lastDebug=stamp;
  el('debugDecisions').replaceChildren();
  for(const row of debug.units||[]){
   const c=node('div','');c.className='debug-unit';
   const faction=(state.units||[]).find(u=>u.id===row.unit_id)?.faction;
   const squad=state.tactical?.squads?.[faction];
   const cmd=row.command||{},source=cmd.source==='local_fallback'?'本地自保':cmd.source==='lm'||cmd.source==='deepseek_lm'?'LLM':cmd.source||controlLabel(faction,row.control);
   c.append(node('strong',`${row.unit_id} · ${row.state} · ${row.order}`));
   c.append(node('p',row.waypoints.length?`下一步 1 / ${row.waypoints.length} → [${row.next.map(n=>n.toFixed(3)).join(', ')}]`:'没有待走路点 · 当前原地行动'));
   c.append(node('p',`${source} · ${actions[cmd.action]||cmd.action||'等待指令'}${cmd.command_id?' · #'+cmd.command_id:''}`));
   c.append(node('small',`最近已执行指令依据：${cmd.reason||squad?.reason||'暂无已接受指令'}${row.control==='lm'&&cmd.source==='console'?'（现已交还 LLM）':''}`));
   const latest=lm.units?.[row.unit_id];if(latest)c.append(node('p',`${latest.origin==='local_fallback'?'本地自保记录':'最新模型决策'} · ${lmPhases[latest.phase]||latest.phase}：${latest.reason||'正在根据输入规划'}${latest.phase==='thinking'?'（上次理由，等待新返回）':''}`));
   if(row.safety||row.path_failure)c.append(node('p',`执行约束：${row.safety||''} ${row.path_failure||''}`));
   c.append(node('p',`压制 ${Math.round(row.suppression*100)}% · 掩体 ${row.cover_id||'无'} · 目标 ${row.target_id||'无'}`));el('debugDecisions').append(c);
  }
 };
 setInterval(refresh,1500);
})();
