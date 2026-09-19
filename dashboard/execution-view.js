/* Uses the same authoritative state and command receipt path as the planning view. */
$('#executionTeam').onchange=e=>{team=e.target.value;lastFactions='';render()};
$('#executionControl').onchange=e=>command({action:'control',mode:e.target.value});
$$('[data-execute]').forEach(b=>b.onclick=async()=>{
 const action=b.dataset.execute;
 const source=document.querySelector(`[data-action="${action}"]`);
 source.click();
});
$('#executionLog').onclick=()=>$('#openLLMLog').click();
setInterval(()=>{
 $('#executionTeam').value=team;
 $('#executionControl').value=state.control?.[team]||'game_ai';
 $('#executionClock').textContent=live?clock(state.time)+(state.paused?' · 暂停':' · 实时'):'等待引擎';
 $('#executionReceipt').textContent=$('#receipt').textContent;
 const units=(state.units||[]).filter(u=>u.faction===team),root=$('#executionUnits');
 root.replaceChildren(...units.map(u=>{
  const card=document.createElement('div');card.className='execution-unit';
  const title=document.createElement('b');title.textContent=u.id+' · '+Math.ceil(u.hp)+' HP';
  const status=document.createElement('p');status.textContent=(states[u.state]||u.state)+' · '+(orders[u.order_mode]||u.order_mode)+' · '+(u.in_cover?'掩体内':'开阔');
  const intent=document.createElement('p');intent.className='caption';intent.textContent=u.survival_reason||u.last_command?.reason||'';
  card.append(title,status,intent);return card;
 }));
},350);
