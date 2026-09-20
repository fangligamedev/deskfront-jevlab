/* A presentation of authoritative streamed sectors; generation runs on the server. */
(()=>{
 const $e=id=>document.getElementById(id);
 const phase={building:'正在构筑',ready:'前方待命',combat:'交战中',cleared:'已夺取'};
 let last='',starting=false;
 const status=t=>$e('eastStatus').textContent=t;
 const modelModes=['typesafe_jev','deepseek_logprobs'];
 async function selectCombat(){
  const value=$e('eastControl').value;
  if(!modelModes.includes(value))return value;
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
  if(starting)return;starting=true;$e('eastStart').disabled=true;
  try{
   const builder=$e('eastBuilder').value;
   if(builder==='dual_brain'&&(!lm.providers?.typesafe_jev?.configured||!lm.providers?.volcengine_ark?.configured))throw Error('快慢脑需要同时配置 DeepSeek 和 JEV。');
   if(!['local','dual_brain'].includes(builder)&&!lm.providers?.[builder]?.configured)throw Error('防线构筑模型尚未配置。');
   const seed=Number($e('eastSeed').value);if(!Number.isInteger(seed)||seed<0||seed>2147483647)throw Error('种子须为 0–2147483647 的整数。');
   const mode=await selectCombat();
   const result=await command({action:'eastfront_start',backend:$e('eastBuilder').value,mode,seed});
   if(result){team='green';status('东线任务已排队，等待引擎载入。');}
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
  $e('eastModel').textContent=f.backend==='dual_brain'?'慢脑 DeepSeek：每次规划三段；快脑 JEV：约每 2 秒调度；游戏 AI 连续执行。规划 '+(lm.frontier?.used?.slow||0)+' 次 / 调度 '+(lm.frontier?.used?.fast||0)+' 次。'+(lm.frontier?.latest?.slow?.strategy||'')+((lm.frontier?.latest?.fast?.error||lm.frontier?.latest?.slow?.error)?' · 模型暂不可用，游戏执行器继续运行：'+(lm.frontier?.latest?.fast?.error||lm.frontier?.latest?.slow?.error):''): '战斗模型：'+(lm.display_name||'未连接')+' / '+(lm.model||'—')+'；模型指挥选择为全局模型配置，影响所有模型控制阵营。构筑可独立选择，失败明确使用本地防线。';
  if(!f.enabled){$e('eastProgress').textContent='选择控制方式，开启向东推进';return}
  $e('eastProgress').textContent='第 '+(f.wave||1)+' 波 · 已突破 '+f.cleared+' 段 · 当前 E'+String(f.active_sector).padStart(3,'0')+' · 守点 '+Number(f.hold_seconds).toFixed(1)+' / 5 秒';
  $e('eastFollow').textContent=f.follow?'镜头跟随中 · 点击自由观察':'自由观察中 · 点击跟随';
  const key=JSON.stringify([state.run_id,f.chunks,f.request?.sequence,f.stopped,f.reinforcement_in]);if(key===last)return;last=key;
  $e('eastSectors').replaceChildren(...f.chunks.map(c=>{const row=document.createElement('div');row.className='east-sector';const b=document.createElement('b');b.textContent='E'+String(c.index).padStart(3,'0')+' · '+(phase[c.phase]||c.phase);const small=document.createElement('small');small.textContent=c.template+' · '+c.source+(c.phase==='building'?' · '+Math.round((c.construction?.progress||0)*100)+'% · '+(c.construction?.workers||[]).map(w=>({survey:'勘测',dig:'挖战壕',carry_sandbag:'搬沙包',stack_sandbag:'堆砌',secure:'完工'})[w.action]||w.action).join(' / '):'');row.append(b,small);return row}));
  const r=f.request;status(f.reinforcement_in>0?'小队覆灭，新一波远征队将在 '+Number(f.reinforcement_in).toFixed(1)+' 秒后从左侧入场。':r?.sequence?'前沿请求 #'+r.sequence+'：等待下一段防线；超时后使用经校验的本地方案。':'前方保持有限库存。接近东侧边界自动构筑，占领后补给并向下一旗点推进。');
  $e('eastMemory').textContent='在场 '+f.chunks.length+' / '+f.max_chunks+' 段 · 累计构筑 '+f.built+' · 已回收 '+f.retired;
 },450);
})();
