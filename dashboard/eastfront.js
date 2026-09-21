/* A presentation of authoritative streamed sectors; generation runs on the server. */
(()=>{
 const $e=id=>document.getElementById(id);
 const phase={building:'正在构筑',ready:'前方待命',combat:'交战中',cleared:'已夺取'};
 let last='',starting=false;
 const status=t=>$e('eastStatus').textContent=t;
 const modelModes=['typesafe_jev','deepseek_logprobs','laya'];
 const dual=backend=>['dual_brain','dual_brain_laya'].includes(backend);
 const opening=f=>f?.enabled&&dual(f.backend)&&!f.cleared&&!(f.chunks||[]).some(c=>['combat','ready'].includes(c.phase));
 function openingStatus(f){
  const brain=lm.frontier||{},pending=(brain.in_flight||[]).includes('slow');
  const building=(f.chunks||[]).find(c=>c.phase==='building');
  if(!live)return '游戏引擎连接已中断，请返回游戏窗口或刷新页面恢复连接。';
  if(building)return '首段战场施工中 · '+Math.round((building.construction?.progress||0)*100)+'%，完成后自动开始交战。';
  if(pending)return '首段战场正在由 DeepSeek 规划 · 本次请求已等待 '+Math.floor(brain.in_flight_seconds?.slow||0)+' 秒。返回并通过校验后自动施工，无需重复开始。';
  const error=brain.latest?.slow_error?.error||brain.latest?.slow?.error;
  if(brain.disabled?.includes('slow'))return '首段规划已停止：'+(error||'模型服务不可用')+'。请检查模型配置或账户状态后重新开始。';
  if(brain.used?.slow>=brain.budgets?.slow)return '本局规划请求额度已用完，请重新开始。';
  if(error)return '首段方案校验或请求失败，'+Math.ceil(brain.retry_in_seconds||0)+' 秒后自动重试：'+error+'。';
  return '首段方案正在交给游戏引擎校验，随后自动施工并开始交战。';
 }

 async function selectCombat(backend=state.eastfront?.backend){
  const value=$e('eastControl').value;
  if(!modelModes.includes(value))return value;
  if(dual(backend)){
   const director=backend==='dual_brain_laya'?'laya':'typesafe_jev';
   if(value!==director)throw Error('快慢脑模式请选对应的 '+(director==='laya'?'Laya 本地':'JEV')+' 战术指挥，或玩家 / 游戏 AI / Agent。');
   if(!lm.providers?.[director]?.configured)throw Error('本局战术模型尚未配置。');
   return 'lm'; // The frontier director owns the squad; no competing per-unit request loop.
  }
  if(!lm.providers?.[value]?.configured)throw Error('该模型未配置，请在服务端配置对应 Key 与模型 ID。');
  if(lm.provider!==value){
   const previous=Object.entries(state.control||{}).filter(([,m])=>m==='lm').map(([f])=>f);
   for(const faction of previous)await awaitReceipt(await command({action:'control',faction,mode:'game_ai'}));
   const r=await fetch('/api/lm/provider',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({provider:value,instance_id:instanceId,run_id:state.run_id})});
   const result=await r.json();if(!r.ok)throw Error(result.error);
   lm=result;
   for(const faction of previous)await awaitReceipt(await command({action:'control',faction,mode:'lm'}));
  }
  return 'lm';
 }

 $e('eastStart').onclick=async()=>{
  if(starting)return;
  if(opening(state.eastfront)&&live&&(lm.frontier?.used?.slow||0)<(lm.frontier?.budgets?.slow||64)&&!(lm.frontier?.disabled||[]).includes('slow')&&state.eastfront.backend===$e('eastBuilder').value&&state.eastfront.seed===Number($e('eastSeed').value)){status(openingStatus(state.eastfront));return}
  starting=true;$e('eastStart').disabled=true;
  try{
   const builder=$e('eastBuilder').value;
   if(['dual_brain','dual_brain_laya'].includes(builder)&&(!lm.providers?.[builder==='dual_brain_laya'?'laya':'typesafe_jev']?.configured||!lm.providers?.volcengine_ark?.configured))throw Error('快慢脑需要 DeepSeek 和对应的快脑配置。');
   if(!['local','dual_brain','dual_brain_laya'].includes(builder)&&!lm.providers?.[builder]?.configured)throw Error('防线构筑模型尚未配置。');
   const seed=Number($e('eastSeed').value);if(!Number.isInteger(seed)||seed<0||seed>2147483647)throw Error('种子须为 0–2147483647 的整数。');
   const mode=await selectCombat(builder);
   const result=await awaitReceipt(await command({action:'eastfront_start',backend:$e('eastBuilder').value,mode,seed}));
   if(result){team='green';status('新东线已载入，首段规划完成后自动施工并开战。');}
  }catch(e){status(e.message)}finally{starting=false;$e('eastStart').disabled=false}
 };
 $e('eastTakeover').onclick=async()=>{
  if(starting)return;starting=true;$e('eastTakeover').disabled=true;
  try{team='green';const mode=await selectCombat();await awaitReceipt(await command({action:'control',faction:'green',mode}));status('已应用绿色远征队控制方式。')}
  catch(e){status(e.message)}finally{starting=false;$e('eastTakeover').disabled=false}
 };
 $e('eastFollow').onclick=()=>command({action:'eastfront_follow',value:!state.eastfront?.follow});
 document.querySelectorAll('[data-east-action]').forEach(b=>b.onclick=async()=>{team='green';await command({action:'control',faction:'green',mode:'player'});await command({action:b.dataset.eastAction,faction:'green'});});
 $e('eastReport').onclick=()=>{
  if(!state.eastfront)return status('先开始一次东线任务。');
  const data={exported_at:new Date().toISOString(),run_id:state.run_id,frontier:state.eastfront,units:state.units,shots:state.shots};
  const url=URL.createObjectURL(new Blob([JSON.stringify(data,null,2)],{type:'application/json'}));const a=document.createElement('a');a.href=url;a.download='eastfront-'+state.run_id+'.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),10000);
 };
 setInterval(()=>{
  const f=state.eastfront||{};
  const squad=state.tactical?.squads?.green;
  const execution={game_ai:'小队协同执行器',lm:dual(f.backend)?(f.backend==='dual_brain_laya'?'Laya 本地指挥':'JEV 指挥')+' → 小队协同执行':'独立逐兵模型',player:'玩家接管',agent:'外部 Agent'}[state.control?.green]||'等待战场';
  const stages={take_cover:'分配并进入掩体',suppress:'建立掩护火力',bound:'交替跃进',advance:'安全接近',defend:'守住旗点',retreat:'撤退重整'};
  const members=(state.units||[]).filter(u=>u.faction==='green'&&u.hp>0&&u.kind!=='tank');
  const guards=(state.units||[]).filter(u=>u.faction==='red'&&u.hp>0&&u.kind!=='tank'&&u.deployment_phase==='active');
  $e('eastTactical').textContent='实际控制：'+execution+' · '+(stages[squad?.phase]||'连续行军')+' · 掩体内 '+members.filter(u=>u.in_cover).length+'/'+members.length+' · 推进者 '+(squad?.mover||'无')+' · 有效掩护 '+(squad?.support_ids?.length||0)+' 人。'+(squad?.reason||'模型下达小队意图，引擎连续执行靠掩体与交替掩护。')+'；守军掩体内 '+guards.filter(u=>u.in_cover).length+'/'+guards.length+' · '+({entrench:'分工据壕',crossfire:'交叉火力',fallback:'后撤工位'}[f.defense]||'等待部署')+' / '+(f.defense_source||'—');
  $e('eastModel').textContent=['dual_brain','dual_brain_laya'].includes(f.backend)?'慢脑 DeepSeek：每次规划三段；快脑 '+(f.backend==='dual_brain_laya'?'Laya 本地':'JEV')+'：约每 2 秒调度；边打边建右侧下一段。规划 '+(lm.frontier?.used?.slow||0)+' 次 / 调度 '+(lm.frontier?.used?.fast||0)+' 次。'+(lm.frontier?.latest?.slow?.strategy||'')+(lm.frontier?.planning_ahead?' · 下一批关卡后台预规划中。':'')+((lm.frontier?.latest?.fast?.error||lm.frontier?.latest?.slow?.error)?' · 模型暂不可用，已建战场继续执行，新段等待慢脑：'+(lm.frontier?.latest?.fast?.error||lm.frontier?.latest?.slow?.error):''): '战斗模型：'+(lm.display_name||'未连接')+' / '+(lm.model||'—')+'；模型指挥选择为全局模型配置，影响所有模型控制阵营。构筑可独立选择，失败明确使用本地防线。';
  if(!f.enabled){$e('eastProgress').textContent='选择控制方式，开启向东推进';return}
  $e('eastStart').textContent=opening(f)?'首段准备中 · 查看进度':'开始新东线';
  $e('eastProgress').textContent=opening(f)?'正在准备第一段战场':'第 '+(f.wave||1)+' 波 · 已突破 '+f.cleared+' 段 · 当前 E'+String(f.active_sector).padStart(3,'0')+' · 守点 '+Number(f.hold_seconds).toFixed(1)+' / 5 秒';
  $e('eastFollow').textContent=f.follow?'镜头跟随中 · 点击自由观察':'自由观察中 · 点击跟随';
  if(opening(f))status(openingStatus(f));
  const key=JSON.stringify([state.run_id,f.chunks,f.request?.sequence,f.stopped,f.reinforcement_in,f.armor]);if(key===last)return;last=key;
  $e('eastSectors').replaceChildren(...f.chunks.map(c=>{const row=document.createElement('div');row.className='east-sector';const b=document.createElement('b');b.textContent='E'+String(c.index).padStart(3,'0')+' · '+(phase[c.phase]||c.phase);const small=document.createElement('small');small.textContent=(c.battle_plan?.layout?'组合地形 · '+c.battle_plan.layout.theme:c.template)+' · '+c.source+(c.phase==='building'?' · '+Math.round((c.construction?.progress||0)*100)+'% · '+(c.construction?.workers||[]).map(w=>({survey:'勘测',dig:'挖战壕',carry_sandbag:'搬沙包',stack_sandbag:'堆砌',carry_material:'搬建材',assemble_structure:'搭建筑',secure:'完工'})[w.action]||w.action).join(' / '):'');row.append(b,small);if(c.components?.length){const parts=document.createElement('small');parts.textContent='地形：'+[...new Set(c.components.map(p=>f.component_catalog?.[p.kind]?.name||p.kind))].join(' / ');row.append(parts)}if(c.battle_plan?.defenders){const plan=document.createElement('small');plan.textContent='慢脑部署：'+c.battle_plan.defenders.map(d=>d.weapon+' → 工位 '+d.station).join(' / ')+'；'+c.battle_plan.reason;row.append(plan)}for(const a of (f.armor||[]).filter(a=>a.sector===c.index)){const tank=document.createElement('small');tank.textContent=(a.team==='green'?'我方':'守方')+'坦克 · '+({parked:'可见待命',entering:'正在驶入',active:'已投入战斗',destroyed:'已被摧毁'}[a.phase]||a.phase)+(a.ready?' · 等待快脑放行':a.phase==='parked'?' · '+Math.ceil(a.delay_remaining)+' 秒后就绪':'');row.append(tank)}return row}));
  const r=f.request;status(opening(f)?openingStatus(f):f.reinforcement_in>0?'小队覆灭，新一波远征队将在 '+Number(f.reinforcement_in).toFixed(1)+' 秒后从左侧入场。':r?.sequence?'前沿请求 #'+r.sequence+(dual(f.backend)?'：右侧下一段后台规划中，当前战斗继续。':'：等待下一段防线；超时后使用经校验的本地方案。'):(f.chunks.some(c=>c.index>f.active_sector&&c.phase==='building')?'右侧下一段施工中，当前战斗照常进行。':f.chunks.some(c=>c.index>f.active_sector&&c.phase==='ready')?'右侧下一段已就绪，攻下当前阵地后直接推进。':'当前战斗继续；下一段在后台提前准备。'));
  $e('eastMemory').textContent='在场 '+f.chunks.length+' / '+f.max_chunks+' 段 · 累计构筑 '+f.built+' · 已回收 '+f.retired;
 },450);
})();
