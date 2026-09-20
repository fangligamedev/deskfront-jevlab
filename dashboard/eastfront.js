/* A presentation of authoritative streamed sectors; generation runs on the server. */
(()=>{
 const $e=id=>document.getElementById(id);
 const phase={building:'正在构筑',ready:'前方待命',combat:'交战中',cleared:'已夺取'};
 let last='',starting=false;
 const status=t=>$e('eastStatus').textContent=t;
 $e('eastStart').onclick=async()=>{
  if(starting)return;starting=true;$e('eastStart').disabled=true;
  try{
   const mode=$e('eastControl').value;
   if(mode==='lm'&&!lm.configured)throw Error('请先在服务端配置战斗模型，或选择游戏 AI。');
   const seed=Number($e('eastSeed').value);if(!Number.isInteger(seed)||seed<0||seed>2147483647)throw Error('种子须为 0–2147483647 的整数。');
   const result=await command({action:'eastfront_start',backend:$e('eastBuilder').value,mode,seed});
   if(result){team='green';status('东线任务已排队，等待引擎载入。');}
  }catch(e){status(e.message)}finally{starting=false;$e('eastStart').disabled=false}
 };
 $e('eastTakeover').onclick=async()=>{team='green';await command({action:'control',faction:'green',mode:$e('eastControl').value});status('已提交绿色远征队控制权切换。')};
 $e('eastFollow').onclick=()=>command({action:'eastfront_follow',value:!state.eastfront?.follow});
 document.querySelectorAll('[data-east-action]').forEach(b=>b.onclick=async()=>{team='green';await command({action:'control',faction:'green',mode:'player'});await command({action:b.dataset.eastAction,faction:'green'});});
 $e('eastReport').onclick=()=>{
  if(!state.eastfront)return status('先开始一次东线任务。');
  const data={exported_at:new Date().toISOString(),run_id:state.run_id,frontier:state.eastfront,units:state.units,shots:state.shots};
  const url=URL.createObjectURL(new Blob([JSON.stringify(data,null,2)],{type:'application/json'}));const a=document.createElement('a');a.href=url;a.download='eastfront-'+state.run_id+'.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),10000);
 };
 setInterval(()=>{
  const f=state.eastfront||{};
  $e('eastModel').textContent='战斗模型：'+(lm.display_name||'未连接')+' / '+(lm.model||'—')+'；生成有独立预算，失败明确使用本地防线。';
  if(!f.enabled){$e('eastProgress').textContent='选择控制方式，开启向东推进';return}
  $e('eastProgress').textContent='已突破 '+f.cleared+' 段 · 当前 E'+String(f.active_sector).padStart(3,'0')+' · 守点 '+Number(f.hold_seconds).toFixed(1)+' / 5 秒';
  $e('eastFollow').textContent=f.follow?'镜头跟随中 · 点击自由观察':'自由观察中 · 点击跟随';
  const key=JSON.stringify([state.run_id,f.chunks,f.request?.sequence,f.stopped]);if(key===last)return;last=key;
  $e('eastSectors').replaceChildren(...f.chunks.map(c=>{const row=document.createElement('div');row.className='east-sector';const b=document.createElement('b');b.textContent='E'+String(c.index).padStart(3,'0')+' · '+(phase[c.phase]||c.phase);const small=document.createElement('small');small.textContent=c.template+' · '+c.source;row.append(b,small);return row}));
  const r=f.request;status(f.stopped?'远征结束：小队失去战斗力。可更换策略重新出发。':r?.sequence?'前沿请求 #'+r.sequence+'：等待下一段防线；超时后使用经校验的本地方案。':'前方保持有限库存。接近东侧边界自动构筑，占领后补给并向下一旗点推进。');
  $e('eastMemory').textContent='在场 '+f.chunks.length+' / '+f.max_chunks+' 段 · 累计构筑 '+f.built+' · 已回收 '+f.retired;
 },450);
})();
