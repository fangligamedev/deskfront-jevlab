/* The director chooses only engine-provided legal steps. No staged fake model output. */
(()=>{
 const phaseNames={building:'01 / 编辑器搭建关卡',deploying:'02 / 桌边兵力入场',ready:'03 / 双方就位',battle:'04 / 夺旗博弈',finished:'05 / 战后复盘'};
 let busy=false,auto=false,modelInfo={},recorder=null,chunks=[],recordStream=null,recordStart=0,lastError='',events=[];
 const status=t=>$('#demoStatus').textContent=t;
 async function api(path,data){const r=await fetch(path,data?{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)}:{});const d=await r.json();if(!r.ok)throw Error(messageText(d.error||'请求失败'));return d}
 async function job(kind,payload){let d=await api('/api/studio/'+kind,payload);const until=Date.now()+150000;while(d.phase==='running'&&Date.now()<until){await new Promise(r=>setTimeout(r,900));d=await api('/api/studio/jobs/'+d.id)}if(d.phase!=='complete')throw Error(d.error||'任务仍在后台运行');return d.artifact_id}
 function save(name,data,mime='application/json'){const url=URL.createObjectURL(data instanceof Blob?data:new Blob([JSON.stringify(data,null,2)],{type:mime}));const a=document.createElement('a');a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),10000)}
 async function load(id,rehearsal=false){
  const previous=state.run_id,q=await api('/api/studio/play',{scenario_id:id,player_faction:'none',opponent_mode:$('#demoCombat').value,demo:true,demo_driver:rehearsal?'local':$('#demoDriver').value,instance_id:instanceId,run_id:state.run_id});
  await awaitReceipt(q);const until=Date.now()+20000;while((state.run_id===previous||!state.demo?.enabled)&&Date.now()<until)await new Promise(r=>setTimeout(r,200));
  if(!state.demo?.enabled||state.run_id===previous)throw Error('演示场景尚未连接');
  if(rehearsal)$('#demoDriver').value='local';$('#demoSetup').open=false;window.DeskfrontViews.setView('demo');status('双人桌面已准备；可以开始录制，再连续执行导演步骤。');
 }
 async function guard(fn){if(busy)return;busy=true;try{await fn()}catch(e){auto=false;lastError=e.message;status('未完成：'+e.message)}finally{busy=false}}
 $('#demoGenerate').onclick=()=>guard(async()=>{status('模型正在根据意图设计并校验关卡…');await load(await job('generate',{brief:$('#demoIntent').value}))});
 $('#demoRehearse').onclick=()=>guard(async()=>{status('正在校验本地示例，排练不会调用模型…');const c=await api('/api/studio/catalog');await load(await job('import',{scenario:c.example}),true)});
 async function step(){
  if(!state.demo?.steps?.length)return;
  let choice={step_id:state.demo.steps[0].id,reason:'本地步骤排练'};
  if($('#demoDriver').value==='model'){
   try{choice=await api('/api/demo/choose',{instance_id:instanceId,run_id:state.run_id})}
   catch(e){if(['demo_no_available_step','demo_rate_limited','demo_state_changed'].includes(e.message)){status('等待引擎更新可执行步骤或士兵完成入场…');return}throw e}
  }
  const receipt=await awaitReceipt(await command({action:'demo_step',step_id:choice.step_id}));
  events.push({at:new Date().toISOString(),run_id:state.run_id,step:choice.step_id,reason:choice.reason,call_id:choice.call_id||null,receipt});
  status(choice.reason+' · 已由引擎执行');
 }
 $('#demoStep').onclick=()=>guard(step);
 $('#demoAuto').onclick=()=>{auto=!auto;status(auto?'连续执行已开启；每一步等待引擎确认。':'连续执行已停止。')};
 $('#demoNext').onclick=()=>guard(async()=>{
  if(!state.winner)throw Error('请先完成当前夺旗对局');
  auto=false;status('生成本局复盘，并用战术优缺点设计下一关…');
  const report=await job('report',{run_id:state.run_id});
  const id=await job('generate',{brief:$('#demoIntent').value+' 下一关应针对上一局的不足增加反制机会，改变掩体或部署，并解释变化。',previous_report_id:report});await load(id);
 });
 $('#demoExport').onclick=()=>save('deskfront-demo-timeline.json',{recording_started_at:recordStart,run_id:state.run_id,scenario:state.scenario,director:state.demo,operations:events,model_sources:modelInfo});
 $('#demoRecord').onclick=async()=>{
  try{
   if(!navigator.mediaDevices?.getDisplayMedia||!window.MediaRecorder)throw Error('当前浏览器不支持窗口录制，请在 Chrome/Edge 打开本页并使用录制按钮，或用系统录屏。');
   recordStream=await navigator.mediaDevices.getDisplayMedia({video:{frameRate:30},audio:true});
   const mime=['video/webm;codecs=vp9,opus','video/webm;codecs=vp8,opus','video/mp4'].find(t=>MediaRecorder.isTypeSupported(t));
   recorder=new MediaRecorder(recordStream,mime?{mimeType:mime}:undefined);chunks=[];recordStart=Date.now();
   recorder.ondataavailable=e=>{if(e.data.size)chunks.push(e.data)};
   recorder.onstop=()=>{const type=recorder.mimeType;save('deskfront-demo-'+recordStart+(type.includes('mp4')?'.mp4':'.webm'),new Blob(chunks,{type}));recordStream.getTracks().forEach(t=>t.stop());$('#demoStopRecord').disabled=true;$('#demoRecord').disabled=false;$('#demoExport').click();status('录像与事件时间线已下载；可导入 Premiere Pro，WebM 如不兼容请先转为 H.264 MP4。')};
   recordStream.getVideoTracks()[0].onended=()=>{if(recorder.state!=='inactive')recorder.stop()};recorder.start(1000);$('#demoStopRecord').disabled=false;$('#demoRecord').disabled=true;status('正在录制所选窗口；声音是否包含取决于浏览器与所选音轨。');
  }catch(e){recordStream?.getTracks().forEach(t=>t.stop());status(e.name==='NotAllowedError'?'录屏权限未获允许。请在 Chrome/Edge 中选择游戏窗口，或使用系统录屏；当前尚未开始录像。':e.message)}
 };
 $('#demoStopRecord').onclick=()=>{if(recorder?.state!=='inactive')recorder?.stop()};
 setInterval(async()=>{
  if(document.body.dataset.view!=='demo')return;
  $('#demoModels').textContent=`关卡与报告：${modelInfo.configured?modelInfo.model+'（已配置）':'未配置'} · 导演与战斗：${lm.configured?lm.model+'（已配置）':'未配置'}。当前建场：${$('#demoDriver').value==='local'?'本地步骤排练':'模型选择'}；${state.demo?.enabled?'当前战斗：'+['green','red'].map(f=>(f==='green'?'绿方':'红方')+' '+(modes[state.control?.[f]]||state.control?.[f]||'待连接')).join(' / '):'待开局战斗：'+$('#demoCombat').selectedOptions[0].textContent}。`;
  const d=state.demo||{};$('#demoPhase').textContent=phaseNames[d.phase]||'等待准备';$('#demoProgress').textContent=d.enabled?`已放置 ${d.completed.length} 项 · 已入场 ${d.deployed}/6 · ${d.clock}s`:'尚未载入双人演示';$('#demoAuto').textContent=auto?'停止连续执行':'连续执行步骤';
  $('#demoTimeline').replaceChildren(...(d.timeline||[]).slice(-30).map(e=>{const p=document.createElement('p');p.textContent=e.at+'s · '+e.message;return p}));
  if(auto&&!busy&&d.running&&d.steps?.length)await guard(step);
  if(d.phase==='battle'||d.phase==='finished')auto=false;
 },1200);
 api('/api/studio/status').then(d=>{modelInfo=d;$('#demoModels').textContent=`关卡与报告：${d.configured?d.model+'（已配置）':'未配置'} · 导演与战斗：${lm.configured?(d.combat_model||lm.model)+'（已配置）':'未配置'}。实际控制以所选模式为准。`}).catch(e=>status(e.message));
})();
