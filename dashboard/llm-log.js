/* On-demand audit viewer: raw model text is always rendered as text, never HTML. */
(()=>{
 const dialog=document.querySelector('#llmLog'),list=document.querySelector('#llmCallList'),unit=document.querySelector('#llmLogUnit'),detail=document.querySelector('#llmCallDetail'),hint=document.querySelector('#llmLogHint');
 const phases={validated:'关卡校验通过',completed:'分析报告已保存',requesting:'请求中',returned:'模型已返回',submitted:'等待引擎',executed:'引擎已执行',rejected:'被拒绝',error:'请求错误',discarded:'返回已过期',waiting:'保持当前行动'};
 let rows=new Map(),selected=null,current=null,cursor=null,busy=false,generation=0,activePanel='input';
 const pretty=v=>typeof v==='string'?v:JSON.stringify(v,null,2);
 async function get(url){const r=await fetch(url);if(!r.ok)throw Error('读取失败：HTTP '+r.status);return r.json()}
 function node(tag,text,cls){const n=document.createElement(tag);n.textContent=text;if(cls)n.className=cls;return n}
 function renderList(){
  list.replaceChildren();
  for(const row of [...rows.values()].sort((a,b)=>b.id-a.id)){
   const b=node('button','', 'llm-call-row');b.type='button';b.dataset.id=row.id;b.setAttribute('aria-pressed',String(row.id===selected));
   b.append(node('strong',`#${row.id} · ${row.unit_id}`),node('span',`${new Date(row.started_at*1000).toLocaleTimeString()} · ${phases[row.phase]||row.phase}`));
   b.onclick=()=>select(row.id);list.append(b);
  }
  if(!rows.size)list.append(node('p','暂无调用。选择模型 AI 并开始对战后，输入和返回会出现在这里。','caption'));
 }
 function renderDetail(row){
  current=row;detail.replaceChildren();
  detail.append(node('h3',`#${row.id} / ${row.unit_id}`),node('p',`${row.model} · ${phases[row.phase]||row.phase} · ${row.latency_ms??'—'} ms · ${row.usage?.total_tokens??'—'} tokens`,'caption'),node('p',`局次 ${row.run_id} · Tick ${row.tick}`,'caption'));
  const tabs=node('nav','', 'llm-log-tabs');tabs.setAttribute('aria-label','调用详情视图');detail.append(tabs);
  const panels={};
  for(const [id,label] of [['input','输入'],['response','模型返回'],['execution','执行回执']]){
   const button=node('button',label);button.type='button';button.setAttribute('aria-pressed',String(activePanel===id));tabs.append(button);
   const panel=node('div','');panel.hidden=activePanel!==id;detail.append(panel);panels[id]=panel;
   button.onclick=()=>{activePanel=id;for(const [key,p] of Object.entries(panels))p.hidden=key!==id;for(const b of tabs.children)b.setAttribute('aria-pressed',String(b===button))};
  }
  function section(parent,title,value){const box=node('section','');box.append(node('h4',title),node('pre',pretty(value)));parent.append(box)}
  for(const message of row.request.messages||[]){let content=message.content;if(message.role==='user'){try{content=JSON.parse(content)}catch{}}section(panels.input,`输入 · ${message.role}`,content)}
  if(row.request.questions){section(panels.input,'输入 · 战场状态',row.request.state);section(panels.input,'输入 · JEV 结构化问题',row.request.questions)}
  const exact=node('details','');exact.append(node('summary','查看完整请求 JSON（含生成参数）'),node('pre',pretty(row.request)));panels.input.append(exact);
  section(panels.response,'返回 · 模型原始响应',row.response_text??(row.phase==='requesting'?'等待模型返回…':'没有收到响应正文；请查看执行回执中的错误信息。'));
  if(row.jev_evaluation)section(panels.response,'JEV 动作概率与危险判断',row.jev_evaluation);
  section(panels.response,row.jev_evaluation?'适配后的游戏指令（代码映射）':'解析后的模型内容',row.parsed_response??'尚无可解析内容');
  section(panels.execution,'校验与执行回执',{decision:row.decision??null,command_id:row.command_id??null,receipt:row.receipt??null,error:row.error??null,discard_reason:row.discard_reason??null,http_status:row.http_status??null,usage:row.usage??null,response_truncated:row.response_truncated??false});
  document.querySelector('#llmLogDownload').disabled=false;
 }
 async function select(id){selected=id;renderList();const g=generation;try{const row=await get('/api/lm/calls/'+id);if(g===generation&&id===selected)renderDetail(row)}catch(e){hint.textContent=e.message}}
 async function refresh(older=false){
  if(busy||!dialog.open)return;busy=true;const g=generation;
  try{
   const q=new URLSearchParams();if(unit.value)q.set('unit',unit.value);if(older&&cursor)q.set('before',cursor);
   const data=await get('/api/lm/calls?'+q);if(g!==generation)return;
   // If browser suspension skipped a whole page, restart the list at the latest
   // page so “older” can fill every gap instead of silently omitting calls.
   if(!older&&rows.size&&data.items.length&&data.items[data.items.length-1].id>Math.max(...rows.keys())+1)rows.clear();
   if(older||!rows.size||cursor===null)cursor=data.next_before;
   for(const row of data.items)rows.set(row.id,row);
   const filter=unit.value;unit.replaceChildren(new Option('全部单位',''),...data.units.map(u=>new Option(u,u)));unit.value=filter;
   renderList();document.querySelector('#llmLogOlder').disabled=!cursor;
   hint.textContent=`已显示 ${rows.size} 次调用 · 每 2 秒更新 · 选中记录保持不跳转 · 历史在本机保存`;
   if(selected===null&&data.items.length)await select(data.items[0].id);
   else if(selected!==null){const row=rows.get(selected);if(!current||current.updated_at!==row?.updated_at)await select(selected)}
  }catch(e){hint.textContent=e.message}finally{busy=false}
 }
 document.querySelector('#openLLMLog').onclick=()=>{generation++;rows.clear();cursor=null;selected=null;current=null;dialog.showModal();document.querySelector('.llm-log-sidebar').scrollTop=0;refresh()};
 document.querySelector('#closeLLMLog').onclick=()=>dialog.close();
 document.querySelector('#llmLogOlder').onclick=()=>refresh(true);
 unit.onchange=()=>{document.querySelector('.llm-log-sidebar').scrollTop=0;generation++;rows.clear();selected=null;current=null;cursor=null;detail.replaceChildren(node('p','选择一次调用查看详情。'));document.querySelector('#llmLogDownload').disabled=true;refresh()};
 document.querySelector('#llmLogDownload').onclick=()=>{if(!current)return;const url=URL.createObjectURL(new Blob([pretty(current)],{type:'application/json'}));const a=document.createElement('a');a.href=url;a.download=`llm-call-${current.id}-${current.unit_id}.json`;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000)};
 setInterval(()=>refresh(),2000);
})();
