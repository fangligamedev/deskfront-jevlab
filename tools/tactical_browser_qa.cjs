// Real exported WebGL, UI inputs and engine receipts. No substitute game state.
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const fs=require('fs'),path=require('path'),assert=require('assert');
const base=process.env.DESKFRONT_URL||'http://127.0.0.1:8774',out=path.resolve(__dirname,'../output/v05');
(async()=>{
 const browser=await chromium.launch({headless:true});const page=await browser.newPage({viewport:{width:1720,height:1120}}),checks=[],errors=[];
 page.on('pageerror',e=>errors.push(String(e)));page.on('console',m=>{if(m.type()==='error')errors.push(m.text())});
 const state=async()=> (await(await page.request.get(base+'/api/state')).json()).state;
 const check=(ok,name)=>{checks.push({name,passed:!!ok});assert(ok,name);console.log('PASS',name)};
 async function until(fn,timeout=30000){const start=Date.now();while(Date.now()-start<timeout){const s=await state();if(fn(s))return s;await page.waitForTimeout(150)}throw Error('Timeout '+fn)}
 async function command(c){const r=await page.request.post(base+'/api/command',{data:{faction:'green',...c}}),q=await r.json();assert(r.ok(),JSON.stringify(q));for(let i=0;i<100;i++){const a=await(await page.request.get(base+'/api/result/'+q.id)).json();if('accepted'in a){assert(a.accepted,JSON.stringify(a));return a}await page.waitForTimeout(100)}throw Error('Missing receipt')}
 try{
  const prior=(await state()).run_id;await page.goto(base);let s=await until(s=>s.version==='0.5.0'&&s.run_id!==prior);
  await page.getByRole('button',{name:'暂停',exact:true}).click();await until(s=>s.paused);
  for(const faction of ['green','blue','red']){await command({action:'control',faction,mode:'player'});await command({action:'hold',faction})}
  await command({action:'control',faction:'green',mode:'player'});
  await command({action:'config',key:'damage',value:1});
  await page.locator('.faction[data-team="green"] .faction-line').click();
  const catalog=await(await page.request.get(base+'/api/action-catalog')).json();check(catalog.game_version==='0.5.0'&&catalog.commands.posture,'Machine-readable Agent action catalog served');
  await page.getByLabel('作战姿态').selectOption('prone');await until(s=>s.units.filter(u=>u.faction==='green').every(u=>u.posture_order==='prone'));
  await page.getByRole('button',{name:'正俯视',exact:true}).click();await until(s=>s.camera==='top');
  await page.getByRole('button',{name:'继续',exact:true}).click();s=await until(s=>s.units.find(u=>u.id==='green-1').asset_animation==='prone_idle');check(true,'Designer posture control produces actual prone animation');
  const canvas=page.frameLocator('#game').locator('canvas');await canvas.scrollIntoViewIfNeeded();await page.waitForTimeout(700);s=await state();let bounds=await canvas.boundingBox();const u=s.units.find(u=>u.id==='green-1');
  await canvas.click({position:{x:u.screen_position[0]/s.viewport[0]*bounds.width,y:u.screen_position[1]/s.viewport[1]*bounds.height}});await until(s=>s.units.find(u=>u.id==='green-1').selected);
  s=await state();bounds=await canvas.boundingBox();const v=s.units.find(u=>u.id==='green-1');const start=v.root_distance,positionBefore=v.position;
  await canvas.click({button:'right',position:{x:v.screen_position[0]/s.viewport[0]*bounds.width+55,y:v.screen_position[1]/s.viewport[1]*bounds.height}});
  s=await until(s=>{const u=s.units.find(u=>u.id==='green-1');return u.locomotion==='crawl'&&u.asset_animation==='crawl'&&u.root_distance>start+.025&&Math.hypot(...u.position.map((p,i)=>p-positionBefore[i]))>.02});
  check(s.decisions.green.action==='move','RTS right-click ground executes crawl with actual root displacement');
  await page.screenshot({path:path.join(out,'web-prone-crawl.png'),fullPage:true});
  await page.getByLabel('作战姿态').selectOption('auto');s=await until(s=>s.units.find(u=>u.id==='green-1').asset_animation==='rifle_jog_rm');check(true,'Returning to auto posture switches clear-ground movement to combat jog');
  await command({action:'control',mode:'agent'});s=await state();
  const q=await(await page.request.post(base+'/api/agent/command',{data:{action:'posture',posture:'crouch',faction:'green',unit_ids:['green-1'],run_id:s.run_id,seen_tick:s.tick}})).json();
  await until(s=>s.units.find(u=>u.id==='green-1').posture_order==='crouch');
  const receipt=await(await page.request.get(base+'/api/result/'+q.id)).json();check(receipt.accepted,'External Agent posture executes through authenticated ownership/freshness contract');
  check(errors.length===0,'No WebGL, JavaScript or shader errors');
  fs.writeFileSync(path.join(out,'web-tactics.json'),JSON.stringify({passed:true,checks,errors,state:await state()},null,2));
 }catch(e){fs.writeFileSync(path.join(out,'web-tactics.json'),JSON.stringify({passed:false,checks,errors,failure:String(e),state:await state()},null,2));await page.screenshot({path:path.join(out,'web-tactics-failure.png'),fullPage:true});throw e}finally{await browser.close()}
})();
