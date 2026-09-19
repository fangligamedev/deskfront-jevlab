// End-to-end on the real exported game. Commands use normal designer APIs; no state injection.
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const fs=require('fs'),path=require('path'),assert=require('assert');
const base=process.env.DESKFRONT_URL||'http://127.0.0.1:8783';
const out=path.resolve(__dirname,'../docs/evidence/flag-warning');
(async()=>{
 const browser=await chromium.launch({headless:true}),page=await browser.newPage({viewport:{width:1440,height:1050}}),checks=[],errors=[];
 page.on('pageerror',e=>errors.push(String(e)));page.on('console',m=>{if(m.type()==='error')errors.push(m.text())});
 await page.addInitScript(()=>{window.__qaAudio=[];const A=window.AudioContext;if(A)window.AudioContext=class extends A{constructor(...a){super(...a);window.__qaAudio.push(this)}}});
 const snapshot=async()=>await(await page.request.get(base+'/api/state')).json();
 async function until(fn,ms=90000){const start=Date.now();while(Date.now()-start<ms){const d=await snapshot();if(fn(d.state,d))return d.state;await page.waitForTimeout(150)}throw Error('Timeout '+fn)}
 const check=(ok,test)=>{checks.push({test,passed:!!ok});assert(ok,test);console.log('PASS '+test)};
 async function command(c){const d=await snapshot();const r=await page.request.post(base+'/api/command',{data:{instance_id:d.instance_id,run_id:d.state.run_id,...c}});const q=await r.json();assert(r.ok(),JSON.stringify(q));for(let i=0;i<150;i++){const a=await(await page.request.get(base+'/api/result/'+q.id)).json();if('accepted'in a){assert(a.accepted,JSON.stringify(a));return a}await page.waitForTimeout(100)}throw Error('Missing ack '+JSON.stringify(c))}
 try{
  assert.equal((await snapshot()).lm.model,'deterministic-flag-test-client','Use tests/flag_warning_server.py, never a live cloud provider');
  await page.goto(base);await until(s=>s.version===require('../package.json').version&&s.units.length===9);
  await page.waitForFunction(()=>live&&sessionCurrent);
  const frame=await(await page.locator('#game').elementHandle()).contentFrame();await frame.locator('#canvas').click({position:{x:300,y:260}});
  await frame.waitForFunction(()=>window.__qaAudio.some(a=>a.state==='running'));
  await page.getByLabel('全局控制方式').selectOption('player');await until(s=>Object.values(s.control).every(c=>c==='player'));
  await command({action:'pause',value:true});
  for(const faction of ['green','blue','red']){await command({action:'hold',faction});await command({action:'equip',faction,weapon:'pistol'})}
  await command({action:'config',key:'damage',value:1});await command({action:'config',key:'cooldown',value:4});await command({action:'config',key:'speed',value:.30});await command({action:'speed',value:3});
  await page.getByRole('button',{name:'战术近景',exact:true}).click();await until(s=>s.camera==='battle');
  await command({action:'capture',faction:'green',unit_ids:['green-2']});await command({action:'pause',value:false});
  let s=await until(s=>s.objective.flag.owner==='green');await command({action:'pause',value:true});s=await until(s=>s.paused);
  await page.waitForFunction(()=>state.paused&&state.objective.flag.owner==='green');
  check(await page.locator('#flagAlarm').isVisible(),'Real movement into flag displays countdown banner');
  const before=s.objective.flag.remaining_seconds;
  const text=await page.locator('#flagCountdown').innerText();check(text==='00:'+String(s.objective.flag.countdown_seconds).padStart(2,'0'),'Displayed countdown equals authoritative engine value');
  check(s.objective.flag.alerts.red.active&&s.objective.flag.alerts.blue.active&&!s.objective.flag.alerts.green.active,'Both opposing factions receive explicit defeat warning');
  await until((s,d)=>d.lm.flag_alerts?.red?.active);
  await page.waitForTimeout(1100);s=(await snapshot()).state;check(s.objective.flag.remaining_seconds===before,'Pausing the game freezes the countdown');
  await page.screenshot({path:path.join(out,'countdown.png'),fullPage:true});
  await command({action:'hold',faction:'green',unit_ids:['green-2']});
  await command({action:'control',faction:'red',mode:'lm'});
  await command({action:'pause',value:false});s=await until(s=>s.objective.flag.contested||s.objective.flag.owner==='red');
  check((await snapshot()).lm.metrics.responses>0,'Test LM received the warning and issued real counterattack commands');
  if(s.objective.flag.contested){
   check(s.objective.flag.alerts.red.contested,'Physical overlap reports the paused contested warning');
   await page.screenshot({path:path.join(out,'contested.png'),fullPage:true});
  }
  s=await until(s=>s.objective.flag.owner==='red');
  check(s.objective.flag.capture_epoch>1&&s.objective.flag.alerts.green.active&&!s.objective.flag.alerts.red.active,'Retaking starts a new capture epoch and reverses the threatened factions');
  // Clearing the holder before entering is also a valid counterattack: a contested
  // interval is not guaranteed in real combat. Its exact freeze is covered in Godot.
  s=await until(s=>s.winner==='red');
  check(s.objective.flag.countdown_seconds===0,'Countdown reaching zero produces an actual red victory');
  check(errors.length===0,'No browser or shader errors');
  await page.screenshot({path:path.join(out,'victory.png'),fullPage:true});
  fs.writeFileSync(path.join(out,'browser.json'),JSON.stringify({passed:true,lm_provider:'deterministic test client, no cloud calls',checks,errors,build_id:s.build_id,version:s.version,final_flag:s.objective.flag},null,2));
 }catch(e){fs.writeFileSync(path.join(out,'browser.json'),JSON.stringify({passed:false,checks,errors,error:String(e),state:(await snapshot()).state},null,2));await page.screenshot({path:path.join(out,'failure.png'),fullPage:true});throw e}
 finally{await browser.close()}
})();
