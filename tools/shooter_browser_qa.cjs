const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const fs=require('fs'),path=require('path'),assert=require('assert');
const base=process.env.SHOOTER_TEST_URL||'http://127.0.0.1:8784',out=path.resolve(__dirname,'../docs/evidence/shooter');
(async()=>{
 const browser=await chromium.launch({headless:false}),page=await browser.newPage({viewport:{width:1560,height:1100}}),checks=[],errors=[];
 const check=(ok,test)=>{checks.push({test,passed:!!ok});console.log(test,ok);assert(ok,test)};
 page.on('pageerror',e=>errors.push(String(e)));page.on('console',m=>{if(m.type()==='error'&&!m.location().url.endsWith('/favicon.ico'))errors.push(m.text())});
 await page.addInitScript(()=>{window.__qaAudio=[];const A=window.AudioContext;if(A)window.AudioContext=class extends A{constructor(...a){super(...a);window.__qaAudio.push(this)}}});
 const snapshot=async()=>await(await page.request.get(base+'/api/state')).json();
 async function until(fn,ms=30000){const start=Date.now();while(Date.now()-start<ms){const d=await snapshot();if(fn(d.state,d))return d.state;await page.waitForTimeout(100)}throw Error('Timeout '+fn)}
 async function command(c){const d=await snapshot(),r=await page.request.post(base+'/api/command',{data:{instance_id:d.instance_id,run_id:d.state.run_id,...c}}),q=await r.json();assert(r.ok(),JSON.stringify(q));for(let i=0;i<100;i++){const a=await(await page.request.get(base+'/api/result/'+q.id)).json();if('accepted'in a){assert(a.accepted,JSON.stringify(a));return a}await page.waitForTimeout(100)}throw Error('ack timeout')}
 try{
  await page.goto(base+'/?view=execution');let s=await until(s=>s?.build_id===require('../data/build-info.json').id&&s.shooter);await page.waitForFunction(()=>live&&sessionCurrent);
  await command({action:'pause',value:true});
  for(const faction of ['green','red','blue']){await command({action:'control',faction,mode:'player'});await command({action:'hold',faction})}
  await command({action:'control',faction:'green',mode:'player'});
  await page.locator('[data-camera="top"]').click();await until(s=>s.camera==='top');await page.waitForTimeout(600);
  const frame=await(await page.locator('#game').elementHandle()).contentFrame(),canvas=frame.locator('#canvas');await canvas.scrollIntoViewIfNeeded();
  s=(await snapshot()).state;const u=s.units.find(u=>u.id==='green-2'),b=await canvas.boundingBox();
  await canvas.click({position:{x:u.screen_position[0]*b.width/s.viewport[0],y:u.screen_position[1]*b.height/s.viewport[1]}});await until(s=>s.units.find(u=>u.id==='green-2').selected);
  await command({action:'pause',value:false});await page.waitForFunction(()=>state&&!state.paused);await page.locator('#possessThird').click();s=await until(s=>s.shooter.active&&s.shooter.perspective==='third');check(s.shooter.unit_id==='green-2','browser button possesses the selected infantry');
  await page.bringToFront();await canvas.click({position:{x:450,y:300}});await page.waitForTimeout(500);await until(s=>s.shooter.mouse_captured);await frame.waitForFunction(()=>window.__qaAudio.some(c=>c.state==='running'));check(true,'real click captures pointer and unlocks audio');
  await page.waitForTimeout(450);await canvas.screenshot({path:path.join(out,'third-person.png')});
  const before=(await snapshot()).state.units.find(u=>u.id==='green-2').position;
  await page.keyboard.down('Shift');await page.keyboard.down('w');await page.waitForTimeout(750);await page.keyboard.up('w');await page.keyboard.up('Shift');
  s=await until(s=>Math.hypot(...s.units.find(u=>u.id==='green-2').position.map((v,i)=>v-before[i]))>.03);check(true,'WASD with Shift moves possessed soldier through root motion');
  await until(s=>s.units.find(u=>u.id==='green-2').movement_speed<.001);const stopped=(await snapshot()).state.units.find(u=>u.id==='green-2').position;await page.waitForTimeout(350);s=(await snapshot()).state;check(Math.hypot(...s.units.find(u=>u.id==='green-2').position.map((v,i)=>v-stopped[i]))<.002,'key release stops movement');
  const shots=s.shooter.shots_fired;await page.mouse.down();await page.waitForTimeout(500);await page.mouse.up();await until(s=>s.shooter.shots_fired>shots);check(true,'real left mouse input fires shared combat projectiles');
  await page.keyboard.press('r');await until(s=>s.units.find(u=>u.id==='green-2').reload_remaining>0);check(true,'R starts weapon reload');
  await page.keyboard.press('v');await until(s=>s.shooter.perspective==='first');await page.waitForTimeout(500);await canvas.screenshot({path:path.join(out,'first-person.png')});check(true,'V switches to first person inside running battle');
  await page.keyboard.press('Escape');await until(s=>!s.shooter.mouse_captured&&s.shooter.active);check(true,'Escape releases pointer without losing possession');
  await page.bringToFront();await canvas.click({position:{x:450,y:300}});await until(s=>s.shooter.mouse_captured);await page.keyboard.press('Tab');await until(s=>!s.shooter.active&&!s.units.some(u=>u.direct_controlled));check(true,'Tab restores RTS and unit authority');
  check(errors.length===0,'no browser or Godot runtime errors');s=(await snapshot()).state;
  fs.writeFileSync(path.join(out,'web.json'),JSON.stringify({passed:true,checks,errors,build_id:s.build_id,fps:s.fps,audio:await frame.evaluate(()=>window.__qaAudio.map(c=>c.state))},null,2));
 }catch(e){fs.writeFileSync(path.join(out,'web.json'),JSON.stringify({passed:false,checks,errors,error:String(e),state:(await snapshot()).state},null,2));await page.screenshot({path:path.join(out,'failure.png')});throw e}finally{await browser.close()}
})();
