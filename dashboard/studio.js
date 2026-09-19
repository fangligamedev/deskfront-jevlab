/* AI creates data, Godot plays it, and the analyst reports against recorded facts. */
(()=>{
 const $s=s=>document.querySelector(s),dialog=$s('#studio'),status=$s('#studioStatus');
 let selectedScenario=null,selectedReport=null,busy=false,lastIndex='',knownReport='';
 const pretty=v=>JSON.stringify(v,null,2),node=(tag,text)=>{const n=document.createElement(tag);n.textContent=text;return n};
 const errors={provider_account_overdue:'火山引擎账户欠费，请充值后重试；可先使用游戏 AI',llm_not_configured:'请先配置 LLM 连接',studio_busy:'已有任务运行，请稍候',studio_rate_limited:'请求过快，请稍后重试',battle_not_finished_use_analyze:'对局尚未结束，请使用态势分析',engine_offline:'请等待游戏引擎连接',stale_run:'对局已变化，请重新发起',scenario_not_found:'未找到关卡'};
 async function api(path,payload){const r=await fetch('/api/studio/'+path,payload?{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)}:undefined);const d=await r.json();if(!r.ok)throw Error(errors[d.error]||d.error||'请求失败');return d}
 function download(name,value){const u=URL.createObjectURL(new Blob([pretty(value)],{type:'application/json'}));const a=node('a','');a.href=u;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(u),1000)}
 function setBusy(v){busy=v;for(const id of ['#studioGenerate','#studioImport','#studioAnalyze','#studioReport','#studioPlay'])$s(id).disabled=v; if(!v)$s('#studioPlay').disabled=!selectedScenario}
 async function job(kind,payload){
  setBusy(true);status.textContent=kind==='generate'?'LLM 正在设计关卡，并调用 Godot 检查通路…':'正在读取真实数据，请稍候…';
  try{const task=await api(kind,payload);const until=Date.now()+150000;let d=task;
   while(d.phase==='running'&&Date.now()<until){await new Promise(r=>setTimeout(r,900));d=await api('jobs/'+task.id)}
   if(d.phase==='error')throw Error(errors[d.error]||d.error);if(d.phase!=='complete')throw Error('任务仍在后台运行，可稍后在历史记录中查看');
   if(['generate','import'].includes(kind))await showScenario(d.artifact_id);else await showReport(d.artifact_id);
   status.textContent=['generate','import'].includes(kind)?'Godot 校验通过：可查看布阵并进入关卡。':'报告已保存；引用事实可在报告下方核对。';await refresh(true);
  }catch(e){status.textContent='未完成：'+e.message}finally{setBusy(false)}
 }
 function preview(level){
  const c=$s('#studioPreview'),ctx=c.getContext('2d'),b=level.bounds,w=c.width,h=c.height;
  const point=p=>[24+(p[0]-b[0])/(b[2]-b[0])*(w-48),24+(p[1]-b[1])/(b[3]-b[1])*(h-48)];
  ctx.fillStyle='#1b291f';ctx.fillRect(0,0,w,h);ctx.strokeStyle='#3e4b36';ctx.strokeRect(24,24,w-48,h-48);
  for(const o of level.objects){const p=point(o.position),sx=o.size[0]/(b[2]-b[0])*(w-48),sz=o.size[2]/(b[3]-b[1])*(h-48);ctx.save();ctx.translate(...p);ctx.rotate(o.yaw*Math.PI/180);ctx.fillStyle=o.kind==='water'?'#426878':o.kind==='road'?'#39442e':o.color;ctx.fillRect(-sx/2,-sz/2,sx,sz);ctx.restore()}
  const flag=point(level.objective);ctx.beginPath();ctx.ellipse(...flag,.17/(b[2]-b[0])*(w-48),.17/(b[3]-b[1])*(h-48),0,0,Math.PI*2);ctx.strokeStyle='#d3ba77';ctx.stroke();ctx.fillStyle='#ead79c';ctx.font='18px sans-serif';ctx.fillText('⚑',flag[0]-5,flag[1]+5);
  for(let i=0;i<3;i++){ctx.fillStyle=['#91ac76','#79a8bb','#bc7b67'][i];for(let j=-1;j<=1;j++){const p=point([level.spawns[i][0]+j*.064,level.spawns[i][1]]);ctx.beginPath();ctx.arc(...p,5,0,Math.PI*2);ctx.fill()}}
 }
 async function showScenario(id){
  const d=await api('scenarios/'+id);selectedScenario=d;$s('#studioScenarioTitle').textContent=d.name;$s('#studioBriefing').textContent=d.spec.briefing;
  const ul=$s('#studioPlan');ul.replaceChildren(...d.spec.tactical_plan.map(t=>node('li',t)));
  $s('#studioValidation').textContent=`Godot 已验证 · 9 个出生点可达 · ${d.validation.open_approaches} 个开阔接近方向 · 守旗 ${d.spec.hold_seconds} 秒（不等同于平衡性证明）`;
  $s('#studioJSON').value=pretty(d.spec);$s('#studioPlay').disabled=false;$s('#studioExportScenario').disabled=false;preview(d.level);
 }
 async function showReport(id){
  const d=await api('reports/'+id);selectedReport=d;const box=$s('#studioReportBody');box.replaceChildren();
  box.append(node('h3',d.kind==='report'?'战后报告':'战局态势分析'),node('p',`局次 ${d.run_id} · ${d.kind==='report'?'结局：'+(names[d.winner]||d.winner):'截至 '+d.evidence_input.duration+' 秒'} · ${d.model}`),node('p',d.analysis.summary));
  box.append(node('p','以下为模型分析；引用 Tick 已核对，但方位、因果与战术评价仍需结合底部引擎事实判断。'));
  function section(title,items){box.append(node('h4',title));const ul=node('ul','');ul.append(...items.map(v=>node('li',v)));box.append(ul)}
  for(const f of d.analysis.factions){section((names[f.faction]||f.faction)+' · 优势',f.strengths);section('风险与不足',f.weaknesses)}
  section('取胜关键',d.analysis.winning_keys);section('证据引用',d.analysis.evidence.map(e=>`Tick ${e.tick}：${e.fact}`));section('不确定性',d.analysis.uncertainties);
  const facts=node('details','');facts.append(node('summary','核对引擎事实与采样记录'),node('pre',pretty(d.evidence_input)));box.append(facts);$s('#studioExportReport').disabled=false;
 }
 async function refresh(force=false){
  if(!dialog.open&&!force)return;
  try{const d=await api('status'),key=pretty([d.scenarios,d.reports]);$s('#studioModel').textContent=d.configured?'创作 / 文本报告：'+d.model+' · 战斗：'+(d.combat_model||d.model):'未配置 LLM；仍可导入 JSON 并使用游戏 AI';
   if(key!==lastIndex){lastIndex=key;const scenarios=$s('#studioScenarios');scenarios.replaceChildren(new Option('选择已保存的关卡',''),...d.scenarios.map(v=>new Option(v.name,v.id)));if(selectedScenario)scenarios.value=selectedScenario.id;
    const reports=$s('#studioReports');reports.replaceChildren(new Option('选择态势 / 战后报告',''),...d.reports.map(v=>new Option(`${v.kind==='report'?'战后':'态势'} · ${new Date(v.created_at*1000).toLocaleTimeString()} · ${v.run_id.slice(-8)}`,v.id)));if(selectedReport)reports.value=selectedReport.id;
    const newest=d.reports.find(v=>v.run_id===state.run_id&&v.kind==='report');if(newest&&newest.id!==knownReport){knownReport=newest.id;$s('#studioReportNotice').textContent='本局战后报告已生成，可在报告列表中查看。'}
   }
   const failed=d.jobs.find(j=>j.kind==='report'&&j.run_id===state.run_id&&j.phase==='error');if(failed)$s('#studioReportNotice').textContent='战后分析失败：'+(errors[failed.error]||failed.error)+'；可点击生成战后报告重试。';
  }catch(e){status.textContent=e.message}
 }
 $s('#openStudio').onclick=()=>{dialog.showModal();refresh(true)};$s('#closeStudio').onclick=()=>dialog.close();
 $s('#studioGenerate').onclick=()=>job('generate',{brief:$s('#studioPrompt').value});
 $s('#studioImport').onclick=()=>{try{job('import',{scenario:JSON.parse($s('#studioJSON').value)})}catch{status.textContent='JSON 格式有误，请修正后校验'}};
 $s('#studioExample').onclick=async()=>{$s('#studioJSON').value=pretty((await api('catalog')).example);status.textContent='已填入示例，可编辑后点击「校验并保存 JSON」。'};
 $s('#studioScenarios').onchange=e=>{if(e.target.value)showScenario(e.target.value).catch(e=>status.textContent=e.message)};
 $s('#studioReports').onchange=e=>{if(e.target.value)showReport(e.target.value).catch(e=>status.textContent=e.message)};
 $s('#studioAnalyze').onclick=()=>job('analyze',{run_id:state.run_id});$s('#studioReport').onclick=()=>job('report',{run_id:state.run_id});
 $s('#studioExportScenario').onclick=()=>{if(selectedScenario)download('scenario-'+selectedScenario.id+'.json',selectedScenario.spec)};
 $s('#studioExportReport').onclick=()=>{if(selectedReport)download('report-'+selectedReport.id+'.json',selectedReport)};
 $s('#studioPlay').onclick=async()=>{
  if(!selectedScenario||busy)return;setBusy(true);status.textContent='正在等待引擎校验并加载关卡…';
  try{const old=state.run_id,q=await api('play',{scenario_id:selectedScenario.id,player_faction:$s('#studioPlayer').value,opponent_mode:$s('#studioOpponent').value,instance_id:instanceId,run_id:old});await awaitReceipt(q);
   const until=Date.now()+15000;while((state.run_id===old||state.scenario?.id!==selectedScenario.id)&&Date.now()<until)await new Promise(r=>setTimeout(r,200));
   if(state.run_id===old||state.scenario?.id!==selectedScenario.id)throw Error('关卡加载尚未确认，请检查引擎连接');
   if($s('#studioPlayer').value!=='none')team=$s('#studioPlayer').value;dialog.close();toast('关卡已载入并暂停。点击「继续」开始，玩家右键移动/攻击。');
  }catch(e){status.textContent='加载失败：'+e.message}finally{setBusy(false)}
 };
 setInterval(()=>{refresh();const mission=state.scenario;$s('#activeMission').textContent=mission?.id?`${mission.name} · ${mission.briefing}`:'AI 创造关卡 · 玩家与模型对抗 · 依据事实复盘';},2000);
})();
