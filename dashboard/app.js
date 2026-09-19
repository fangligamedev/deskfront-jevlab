const $=s=>document.querySelector(s), $$=s=>[...document.querySelectorAll(s)];
if(new URLSearchParams(location.search).has('native')){$('#game').outerHTML='<div class="native-placeholder" style="height:55vh;display:grid;place-content:center;border:1px solid #3a4234;border-radius:6px;padding:32px;text-align:center"><h2>原生游戏窗口</h2><p class="muted">此控制台仅连接原生实例，不启动第二个 Web 游戏。<br>在 Godot 中运行工程，或启动已导出的 macOS 应用。</p></div>'}
const names={green:'苔绿侦察队',blue:'钴蓝机动队',red:'砖红守备队'}, colors={green:'#91ac76',blue:'#79a8bb',red:'#bc7b67'};
const actions={wait:'继续当前任务',man_at_gun:'接管反坦克炮',leave_gun:'弃炮',garrison:'进驻小楼',leave_building:'撤出小楼',grenade:"投掷手雷",capture:'占领中央目标',cover:'寻找方向掩体',flank:'向侧翼推进',retreat:'撤回出生阵地',hold:'原地防守',move:'移动到指定位置',attack:'攻击指定目标'};
const modes={game_ai:'游戏 AI',lm:'模型 AI',player:'玩家接管',agent:'外部 Agent'},states={idle:'待机',move:'移动',cover:'掩护',aim:'瞄准',fire:'射击',reload:'换弹',suppressed:'受压制',dead:'失去战斗力',melee:'刺刀近战'};
const equipmentPhases={parked:'停放',approaching:'前往就位',towing:'推炮',deploying:'架炮',ready:'火力位就绪',abandoned:'已弃炮',destroyed:'已摧毁',stationed:'驻守窗口',exiting:'排队撤离',falling:'坠落'};
const phases={defend:'守旗防御',take_cover:'占据掩体',suppress:'建立压制',bound:'交替推进',advance:'队形行军',retreat:'撤退'};
const roles={overwatch:'火力掩护',assault:'突击',anti_armor:'反装甲',armor:'装甲支援'},stances={open:'开阔',hide:'隐蔽',peek:'探头',crouch:'低姿'},orders={self_preserve:'自保转移',pinned:'就地卧倒',formation:'队形移动',bound:'掩护推进',cqb_flank:'绕侧清理',reverse:'倒车脱离',reposition:'调整站位',fire_support:'定点支援',retreat:'撤退',overwatch:'掩护',take_cover:'入位',hold:'待命'};
let instanceId=null,sessionReady=false,sessionCurrent=false;
let lm={},state={},live=false,team='green',toastTimer,pendingIds=new Set(),lastFactions='';
function toast(text){$('#toast').textContent=text;$('#toast').classList.add('visible');clearTimeout(toastTimer);toastTimer=setTimeout(()=>$('#toast').classList.remove('visible'),3000)}
async function command(c){try{if(!sessionReady||!sessionCurrent)throw Error('session_replaced');if(!live)throw Error('engine_offline');const r=await fetch('/api/command',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({faction:team,...c,instance_id:instanceId,run_id:state.run_id})});const d=await r.json();if(!r.ok)throw Error(d.error);pendingIds.add(d.id);$('#receipt').textContent='指令已排队，等待引擎回执…';return d}catch(e){toast('指令未执行：'+messageText(e.message))}}
function escapeHTML(s){return String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
function clock(t){return `${Math.floor(t/60).toString().padStart(2,'0')}:${Math.floor(t%60).toString().padStart(2,'0')}`}
function factions(){const key=JSON.stringify([team,state.control,state.units?.map(u=>[u.id,u.hp>0])]);if(key===lastFactions)return;lastFactions=key;$('#factions').innerHTML=Object.keys(names).map(t=>`<div class="faction ${t===team?'selected':''}" data-team="${t}"><div class="faction-line"><b style="color:${colors[t]}">● ${names[t]}</b><span>${state.units.filter(u=>u.faction===t&&u.hp>0).length} UNITS</span></div><select aria-label="${names[t]}控制方式" data-team="${t}">${Object.entries(modes).map(([k,v])=>`<option value="${k}" ${state.control[t]===k?'selected':''}>${v}</option>`).join('')}</select></div>`).join('');$$('.faction').forEach(el=>el.onclick=e=>{if(e.target.tagName!=='SELECT'){team=el.dataset.team;render()}});$$('.faction select').forEach(el=>el.onchange=()=>{team=el.dataset.team;command({action:'control',mode:el.value})})}
function drawMap(){const canvas=$('#map'),ctx=canvas.getContext('2d'),w=canvas.width,h=canvas.height,b=state.bounds;if(!b)return;const point=p=>[(p[0]-b[0])/(b[2]-b[0])*w,(p[1]-b[1])/(b[3]-b[1])*h];ctx.clearRect(0,0,w,h);ctx.fillStyle='#1c281f';ctx.fillRect(0,0,w,h);ctx.strokeStyle='#2d3a2b';ctx.lineWidth=1;for(let x=0;x<w;x+=48){ctx.beginPath();ctx.moveTo(x,0);ctx.lineTo(x,h);ctx.stroke()}for(let y=0;y<h;y+=42){ctx.beginPath();ctx.moveTo(0,y);ctx.lineTo(w,y);ctx.stroke()}
for(const c of [...state.covers,...state.obstacles]){const p=point(c.position),sw=c.size[0]/(b[2]-b[0])*w,sh=c.size[1]/(b[3]-b[1])*h;ctx.fillStyle=c.alive===false?'#393b2b':c.kind==='sandbag'?'#8a7c51':'#46523c';ctx.fillRect(p[0]-sw/2,p[1]-sh/2,sw,sh)}
const o=point(state.objective.position);ctx.strokeStyle='#c2ae7188';ctx.setLineDash([4,5]);ctx.beginPath();ctx.arc(...o,state.objective.radius/(b[2]-b[0])*w,0,Math.PI*2);ctx.stroke();ctx.setLineDash([]);ctx.fillStyle='#c2ae71';ctx.beginPath();ctx.moveTo(o[0],o[1]-7);ctx.lineTo(o[0]+6,o[1]);ctx.lineTo(o[0],o[1]+7);ctx.lineTo(o[0]-6,o[1]);ctx.fill();
for(const u of state.units){if(u.hp<=0)continue;const p=point(u.position);ctx.fillStyle=colors[u.faction];if(state.debug_visualize?.enabled){const route=state.debug_visualize.units.find(r=>r.unit_id===u.id);if(route){ctx.strokeStyle=colors[u.faction];ctx.beginPath();ctx.moveTo(...p);for(const n of route.waypoints)ctx.lineTo(...point([n[0],n[2]]));ctx.stroke()}}if(u.kind==='tank')ctx.fillRect(p[0]-8,p[1]-11,16,22);else{ctx.beginPath();ctx.arc(...p,5,0,Math.PI*2);ctx.fill()}if(u.selected){ctx.strokeStyle='#e1d6a9';ctx.beginPath();ctx.arc(...p,9,0,Math.PI*2);ctx.stroke()}}
}
function render(){if(!state.units)return;renderFlagWarning();window.renderDebugConsole?.();
$("#buildVersion").textContent=state.version||"等待版本";$("#buildVersion").title=state.build_id||"";
const infantry=state.units.filter(u=>u.faction===team&&u.hp>0&&u.kind!=='tank');
for(const [id,key] of [['#weaponSelect','weapon'],['#postureSelect','posture_order']]){const values=[...new Set(infantry.map(u=>u[key]))];if(document.activeElement!==$(id))$(id).value=values.length===1?values[0]:'mixed'}
$("#levelSelect").value=state.map_index??0;factions();drawMap();$('#clock').textContent=clock(state.time);$('#population').textContent=state.units.filter(u=>u.hp>0).length+' 单位';const d=state.decisions[team]||{};const squad=state.tactical?.squads?.[team];const llmControl=state.control[team]==='lm';$('#tacticalPhase').textContent=llmControl?'LLM 独立战术':phases[squad?.phase]||'外部指令';$('#squadDetail').textContent=squad?`队长 ${squad.leader} · 推进者 ${squad.mover||'无'} · 可提供火力 ${squad.support_ids?.length||0} 人`:llmControl?modes.lm+' 逐单位决策，Godot 执行战术与紧急自保':'由玩家或 Agent 指挥';$('#decision').textContent=state.winner?state.winner==='draw'?'战斗结束 · 平局':names[state.winner]+'获胜':actions[d.action]||'等待战术评估';$('#reason').textContent=d.reason||'AI 将在首个决策周期分配行动。';$('#verified').textContent=live?'● 状态已同步':'○ 状态已过期';$('#source').textContent=modes[state.control[team]];$('#tick').textContent=state.tick;$('#shots').textContent=state.shots;$('#score').textContent=Number(state.scores[team]).toFixed(1)+' / '+state.objective.score_to_win+' 秒';$('#teamLabel').textContent=team.toUpperCase();$('#navrev').textContent='NAV '+state.navigation_revision+' · 已毁 '+(state.destruction_count||0);$('#reserve').textContent=Object.keys(state.reservations).length+' 站位预约';$('#candidates').innerHTML=(d.candidates||[]).map(c=>`<div class="candidate">${actions[c.action]}<span>${Number(c.score).toFixed(2)}</span></div>`).join('')||`<p class="caption">${squad?'协调器按战术条件切换阶段，无模型概率评分。':'当前由外部指令控制。'}</p>`;$('#units').innerHTML=state.units.filter(u=>u.faction===team).map(u=>`<div class="unit"><span style="color:${colors[team]}">${u.kind==='tank'?'▰':'◆'} ${u.id}</span><div>${u.gun_id?'反坦克炮炮手':u.weapon_name||''} · ${equipmentPhases[u.state]||states[u.state]||u.state} · ${{stand:'站姿',crouch:'蹲姿',prone:'趴姿',armored:'装甲'}[u.posture]||''}<small> · ${u.in_cover?'掩体内':stances[u.cqb_stance]||''}</small><div class="caption">${{sprint:'冲锋',run:'跑动',crawl:'爬行',crouch_run:'低姿移动',cover_step:'贴墙短步',idle:'停止',tracks:'行驶',reverse:'倒车'}[u.locomotion]||''} · ${roles[u.tactical_role]||''} · ${orders[u.order_mode]||u.order_mode||''}${u.kind==='tank'?' · 炮塔 '+Math.round(u.turret_yaw*180/Math.PI)+'°':''}</div><div class="bar"><i style="width:${100*u.hp/u.max_hp}%;background:${colors[team]}"></i></div></div><b>${Math.ceil(u.hp)} HP<br><small>${u.kind==='tank'?(u.deployment_phase==='entering'?'驶入中，禁止开火':'炮弹'):u.ammo+' 发'}</small></b></div>`).join('');$('#events').innerHTML=state.events.slice(0,12).map(e=>`<div class="event"><time>${clock(e.time)}</time><span>${escapeHTML(e.text)}</span></div>`).join('');$('#pause').textContent=(state.demo?.enabled&&state.demo.phase!=='battle'?!state.demo.running:state.paused)?'继续':'暂停';$('#tank').disabled=state.tank_spawned||Boolean(state.demo?.enabled);const flag=state.objective.flag;$('#flagStatus').textContent=flag?`${flag.owner?names[flag.owner]+'守旗，剩余 '+flag.countdown_seconds+' 秒':'旗点中立，守旗 '+flag.required_seconds+' 秒获胜'}${flag.contested?' · 争夺中，计时暂停':''}`:'';$('#phase').textContent=state.winner?'04 / 战斗结束':state.tank_spawned?(state.tank_reserve?.deployment_phase==='entering'?'03 / 红方坦克正从上方桌面驶入':'03 / 坦克已进入战场'):state.time>8?'02 / 桌面上的掩护与交战':'01 / 办公桌上的小小前线';$('#stage2').classList.toggle('on',state.time>8);$('#stage3').classList.toggle('on',state.tank_spawned);$('#fps').textContent=state.fps+' FPS';$$('[data-camera]').forEach(el=>el.classList.toggle('active',el.dataset.camera===state.camera));}
async function poll(){try{const r=await fetch('/api/state');const d=await r.json();if(sessionReady&&instanceId!==d.instance_id&&d.engine_live&&window.DeskfrontViews){window.DeskfrontViews.setRemote(true);const frame=$('#game');if(frame)frame.src='about:blank';$('#viewStatus').textContent='已连接另一窗口中的游戏，此页面继续作为控制台。';}if(sessionReady&&(window.DeskfrontViews?.remote||(instanceId===null&&new URLSearchParams(location.search).has('native'))))instanceId=d.instance_id;sessionCurrent=sessionReady&&instanceId===d.instance_id;live=d.engine_live&&sessionCurrent;state=sessionCurrent?d.state:{};lm=sessionCurrent?(d.lm||{}):{};renderLM();$('#led').classList.toggle('live',live);$('#connection').textContent=!sessionCurrent?'此页面已断开：另一游戏页面接管了服务，刷新可重新连接':live?'引擎实时连接':d.age_seconds?'引擎已离线 · 保留最后状态':'等待游戏引擎';for(const id of [...pendingIds]){const result=await (await fetch('/api/result/'+id)).json();if('accepted'in result){$('#receipt').textContent=result.accepted?'✓ 已由引擎执行':'× 指令未执行：'+messageText(result.message);toast(result.accepted?'已执行':'未执行：'+messageText(result.message));pendingIds.delete(id)}else if(result.status==='unknown'){pendingIds.delete(id);$('#receipt').textContent='回执已失效，请重新操作'}}render()}catch(e){live=false;$('#connection').textContent='控制服务未连接'}finally{setTimeout(poll,350)}}
$$('[data-action]').forEach(el=>el.onclick=()=>{const action=el.dataset.action;if(action==='grenade'){const ids=(state.units||[]).filter(u=>u.faction===team&&u.available_actions?.includes('grenade')).map(u=>u.id);if(!ids.length)return toast('当前没有可投掷手雷的士兵');return command({action,unit_ids:ids})}return command({action})});$$('[data-camera]').forEach(el=>el.onclick=()=>command({action:'camera',mode:el.dataset.camera}));$('#auto').onclick=()=>command({action:'control',mode:'lm'});$('#pause').onclick=()=>command({action:'pause',value:state.demo?.enabled&&state.demo.phase!=='battle'?state.demo.running:!state.paused});$('#tank').onclick=()=>command({action:'reinforce'});$('#reset').onclick=()=>command({action:'reset'});$('#speed').onchange=e=>command({action:'speed',value:Number(e.target.value)});$$('[data-param]').forEach(el=>{el.oninput=()=>el.nextElementSibling.value=el.value;el.onchange=()=>command({action:'config',key:el.dataset.param,value:Number(el.value)})});$('#map').onclick=e=>{if(!live||!state.bounds)return;const r=e.currentTarget.getBoundingClientRect(),b=state.bounds;command({action:'move',position:[b[0]+(e.clientX-r.left)/r.width*(b[2]-b[0]),b[1]+(e.clientY-r.top)/r.height*(b[3]-b[1])]})};$('#download').onclick=()=>{const url=URL.createObjectURL(new Blob([JSON.stringify(state,null,2)],{type:'application/json'}));const a=document.createElement('a');a.href=url;a.download='deskfront-state.json';a.click();URL.revokeObjectURL(url)};

$("#levelSelect").onchange=e=>command({action:"map",index:Number(e.target.value)});
$("#weaponSelect").onchange=e=>command({action:"equip",weapon:e.target.value});
$("#postureSelect").onchange=e=>{const unit_ids=(state.units||[]).filter(u=>u.faction===team&&u.hp>0&&u.kind!=="tank").map(u=>u.id);if(!unit_ids.length)return toast("当前阵营没有存活的步兵");command({action:"posture",posture:e.target.value,unit_ids})};

const lmPhases={thinking:'思考中',submitted:'等待回执',executing:'执行中',waiting:'保持意图',rejected:'引擎拒绝',stale:'旧回复已丢弃',fallback:'本地自保',inactive:'已交出控制',dead:'阵亡'};
const intents={survive:'保命',support:'掩护',advance:'推进',flank:'绕侧',engage:'交火',withdraw:'撤离',capture:'占点',observe:'观察'};
function renderLM(){
 const label=lm.display_name||(lm.provider==='typesafe_jev'?'TypeSafe JEV':'DeepSeek LLM');
 if(modes.lm!==label){modes.lm=label;lastFactions='';factions()}
 for(const option of $$('select option[value="lm"]'))option.textContent=label;
 $('#startLLM').textContent='开始 '+label+' 对战';

 const values=Object.values(state.control||{}),shared=values.length&&values.every(v=>v===values[0])?values[0]:'mixed';$('#globalControl').value=shared;$('#controlBadge').textContent=shared==='mixed'?'混合控制':modes[shared]||'等待连接';
 const statusText={running:'正在指挥战斗',paused:'游戏已暂停，模型暂停请求',budget_exhausted:'本局模型预算已耗尽，仅本地自保；点击开始按钮可重开',backoff:'模型请求失败，正在重试；当前为本地自保',finished:'本局已结束',idle:'尚未选择 LLM 控制',offline:'游戏已离线',unconfigured:'模型未配置'}[lm.status]||'等待状态';
 $('#lmStatus').textContent=lm.configured?`${label} · ${statusText} · ${lm.model} · 本局调用 ${lm.used_requests||0}/${lm.max_requests} · 并发 ${lm.in_flight||0}`:'LLM 未配置：服务端需要 Key 与模型 ID';
 if(lm.metrics?.last_error==='provider_account_overdue')$('#lmStatus').textContent='LLM 服务账户欠费（provider_account_overdue）· 当前仅本地自保，请在火山方舟处理账户后继续';
 $('#lmMetrics').textContent=`模型返回 ${lm.metrics?.responses||0} · 回执成功 ${lm.metrics?.accepted||0} · 引擎拦截 ${lm.metrics?.rejected||0} · 过期 ${lm.metrics?.discarded||0}`;
 const rows=Object.values(lm.units||{}).filter(u=>u.unit_id.startsWith(team));
 $('#lmDecisions').innerHTML=rows.map(u=>`<div class="lm-decision"><div><b>${escapeHTML(u.unit_id)}</b><span>${lmPhases[u.phase]||escapeHTML(u.phase)}</span></div><p>${u.origin==='local_fallback'?'本地自保（非模型指令）':escapeHTML(label)} · ${intents[u.intent]||'观察'} · ${actions[u.action]||escapeHTML(u.action||'等待结果')}${u.latency_ms?' · '+u.latency_ms+' ms':''}</p><small>${escapeHTML(u.reason||'正在读取该单位的真实战场状态')}${u.receipt&&!u.receipt.accepted?' · '+escapeHTML(messageText(u.receipt.message)):''}</small></div>`).join('')||'<p class="caption">该阵营尚无 LLM 决策。每个单位单独请求，回执以引擎为准。</p>';
}
$('#globalControl').onchange=async e=>{
 const mode=e.target.value;if(mode==='mixed')return;
 if(mode==='lm'&&!lm.configured){toast('LLM 尚未配置，现有控制方式保持不变');renderLM();return}
 for(const faction of ['green','blue','red'])await command({action:'control',faction,mode});
};

async function equipmentOrder(action,extra={}){const members=(state.units||[]).filter(u=>u.faction===(extra.faction||team)&&u.hp>0&&u.available_actions?.includes(action));if(!members.length)return toast('当前没有可执行此操作的士兵');for(const u of (action==='man_at_gun'?members.slice(0,1):members))await command({action,unit_ids:[u.id],...extra})}
$('#garrison1').onclick=()=>equipmentOrder('garrison',{faction:'blue',floor:1});$('#garrison2').onclick=()=>equipmentOrder('garrison',{faction:'blue',floor:2});$('#exitBuilding').onclick=()=>equipmentOrder('leave_building',{faction:'blue'});$('#manGun').onclick=()=>equipmentOrder('man_at_gun');$('#leaveGun').onclick=()=>equipmentOrder('leave_gun');
setInterval(()=>{if(!state.units)return;const houses=state.building;$('#equipmentStatus').textContent=(houses?.id?`蓝方小楼：${houses.collapsed?'已坍塌':Object.values(houses.stations).map(s=>s.floor+'楼 '+(equipmentPhases[s.phase]||s.phase)).join(' / ')||'等待进驻'} · `:'')+(state.at_guns||[]).filter(g=>g.faction===team).map(g=>`${g.id}：${equipmentPhases[g.phase]||g.phase} · 牵引 ${g.distance_pushed.toFixed(2)}m · ${g.shots}炮 · ${g.reason}`).join('');},600);

const errorMessages={flag_state_changed:'旗点归属已变化，已丢弃旧指令，正在重新决策',session_replaced:'另一游戏页面已接管服务，请在当前使用的页面操作；刷新此页可重新连接',stale_run:'对局已更换，请等待新战场连接后重试',expired_or_new_run:'旧对局指令已失效，请重新操作',command_timeout:'引擎未在 10 秒内回应，请检查游戏是否正常运行',engine_offline:'游戏引擎尚未连接，请等待画面加载',lm_not_configured:'请在本地服务配置当前模型供应商的 Key 和模型 ID',match_finished:'本局已经结束，请先重新开始',action_busy:'士兵正在完成投掷或掩体动作，请稍后重试',infantry_required:'此指令只能用于步兵',no_living_units:'当前阵营没有存活单位',authority_denied:'当前控制方式没有此单位的操作权限',survival_override:'单位正在紧急自保，暂缓危险指令',invalid_target:'目标已阵亡或失效，等待模型重新选目标',stale_observation:'战况已变化，旧决策不再执行',stale_control_epoch:'控制权已变化，旧决策不再执行',action_unavailable:'动作当前不可用，等待重新决策',anti_armor_required:'需要反装甲武器，轻武器不能攻击坦克'};
function messageText(code){return errorMessages[code]||code}
async function startSession(forceNew=false){
 try{
  const native=new URLSearchParams(location.search).has('native');
  const existing=await (await fetch('/api/state')).json();
  const previousOwner=sessionStorage.getItem('deskfront-engine-owner');
  const attach=native||(!forceNew&&window.DeskfrontViews?.mode!=='game'&&existing.engine_live&&previousOwner!==existing.instance_id);
  const response=await fetch(attach?'/api/state':'/api/session',attach?{}:{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'});
  if(!response.ok)throw Error('session_start_failed');
  const data=await response.json();instanceId=data.instance_id;sessionReady=true;
  window.DeskfrontViews?.setRemote(attach);
  if(attach)sessionStorage.removeItem('deskfront-engine-owner');else sessionStorage.setItem('deskfront-engine-owner',instanceId);
  if(!attach)$('#game').src='/play/index.html?instance_id='+encodeURIComponent(instanceId);
  if(!attach&&window.DeskfrontViews?.mode==='game'&&window.opener)window.opener.postMessage({type:'deskfront-game-ready'},location.origin);
  if(!window.deskfrontPolling){window.deskfrontPolling=true;poll();}
 }catch(e){$('#connection').textContent='控制服务未连接，请刷新重试';toast(messageText(e.message))}
}
startSession();
window.addEventListener('deskfront-new-embedded',()=>{window.DeskfrontViews.setView('overview');startSession(true)});

async function awaitReceipt(queued){
 if(!queued)throw Error('command_not_queued');
 const deadline=Date.now()+15000;
 while(Date.now()<deadline){
  const result=await(await fetch('/api/result/'+queued.id)).json();
  if('accepted' in result){if(!result.accepted)throw Error(result.message);return result}
  await new Promise(resolve=>setTimeout(resolve,150));
 }
 throw Error('command_timeout');
}
$('#startLLM').onclick=async()=>{
 const button=$('#startLLM');button.disabled=true;
 try{
  if(!lm.configured)throw Error('lm_not_configured');
  if(state.winner||lm.budget_remaining===0){
   const oldRun=state.run_id;await awaitReceipt(await command({action:'reset'}));
   const deadline=Date.now()+12000;
   while(state.run_id===oldRun&&Date.now()<deadline)await new Promise(resolve=>setTimeout(resolve,150));
   if(state.run_id===oldRun)throw Error('command_timeout');
  }
  for(const faction of ['green','blue','red'])await awaitReceipt(await command({action:'control',faction,mode:'lm'}));
  await awaitReceipt(await command({action:'pause',value:false}));
  toast(modes.lm+' 对战已启动：每名士兵和坦克独立决策');
 }catch(e){toast('未能启动 LLM 对战：'+messageText(e.message))}
 finally{button.disabled=false}
};

function renderFlagWarning(){
 const flag=state.objective?.flag,alarm=$('#flagAlarm');
 alarm.hidden=!flag?.owner;
 if(alarm.hidden)return;
 const seconds=flag.countdown_seconds??Math.ceil(flag.remaining_seconds);
 $('#flagCountdown').textContent=clock(seconds);
 $('#flagAlarmTitle').textContent=state.winner?(state.winner==='draw'?'本局平局':(names[state.winner]||state.winner)+'获胜'):names[flag.owner]+'夺旗 · 距胜利';
 $('#flagAlarmMessage').textContent=state.winner?(state.winner==='draw'?'无人完成守旗，本局结束。':'守旗完成，本局结束。'):state.paused?'游戏已暂停，倒计时停止。':flag.contested?'旗点争夺中，倒计时暂停。保持圈内兵力，清除守军夺回旗帜！':'其余阵营必须立即反攻夺旗，不惜伤亡；倒计时归零即战败！进入旗圈可暂停倒计时。';
 alarm.classList.toggle('critical',seconds<=10&&!state.winner);
 alarm.classList.toggle('contested',!!flag.contested||state.paused);
}
