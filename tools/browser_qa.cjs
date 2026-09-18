// Real WebGL game input and control-plane acceptance. No simulation substitute.
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const fs=require('fs'),path=require('path'),assert=require('assert');
const root=path.resolve(__dirname,'..'),out=path.join(root,'output/playwright');fs.mkdirSync(out,{recursive:true});
(async()=>{
 const browser=await chromium.launch({headless:true});
 const page=await browser.newPage({viewport:{width:1720,height:1120}});
 const errors=[],checks=[],fps=[];
 // Instrument the real WebAudio destination without replacing the game sound.
 await page.addInitScript(()=>{
  window.__audioMeters=[];
  const original=AudioNode.prototype.connect;
  AudioNode.prototype.connect=function(destination,...args){
   if(destination instanceof AudioDestinationNode){
    const meter=this.context.createAnalyser();meter.fftSize=2048;
    window.__audioMeters.push(meter);original.call(meter,destination);
    return original.call(this,meter,...args);
   }
   return original.call(this,destination,...args);
  };
 });
 page.on('pageerror',e=>errors.push(String(e)));page.on('console',m=>{if(m.type()==='error')errors.push(m.text())});
 const base=process.env.DESKFRONT_URL||'http://127.0.0.1:8768';
 const state=async()=> (await (await page.request.get(base+'/api/state')).json()).state;
 async function until(fn,timeout=15000){const start=Date.now();while(Date.now()-start<timeout){const s=await state();if(await fn(s))return s;await page.waitForTimeout(150)}throw Error('Timed out: '+String(fn))}
 function check(value,name){checks.push({test:name,passed:!!value});assert(value,name)}
 async function submit(c,agent=false){const response=await page.request.post(base+(agent?'/api/agent/command':'/api/command'),{data:c});const queued=await response.json();assert(response.ok(),JSON.stringify(queued));for(let i=0;i<70;i++){const result=await (await page.request.get(base+'/api/result/'+queued.id)).json();if('accepted'in result)return result;await page.waitForTimeout(150)}throw Error('Missing engine acknowledgement')}
 try{
  const previousRun=(await state())?.run_id;const start=Date.now();await page.goto(base);await until(s=>s.run_id!==previousRun&&s.version==='0.2.0'&&s.units?.length===9);checks.push({test:'WebGL boots with nine units',passed:true,milliseconds:Date.now()-start});
  await page.getByRole('button',{name:'暂停',exact:true}).click();let s=await until(s=>s.paused);
  const frozen=s.time;await page.waitForTimeout(700);check((await state()).time===frozen,'Pause button freezes actual game');
  await page.getByRole('button',{name:'战术近景',exact:true}).click();await until(s=>s.camera==='battle');
  await page.getByLabel('苔绿侦察队控制方式').selectOption('player');await until(s=>s.control.green==='player');
  await page.locator('#map').click({position:{x:128,y:220}});s=await until(s=>s.decisions.green?.action==='move');
  const before=s.units.find(u=>u.id==='green-1').position;
  await page.getByRole('button',{name:'继续',exact:true}).click();await until(s=>!s.paused);
  s=await until(s=>Math.hypot(...s.units.find(u=>u.id==='green-1').position.map((v,i)=>v-before[i]))>.04);
  check(s.control.green==='player','Minimap movement reaches Godot and AI does not steal control');
  const frame=page.frameLocator('#game');const canvas=frame.locator('#canvas');await canvas.click({position:{x:300,y:260}});await page.keyboard.press('Digit2');s=await until(s=>s.control.blue==='player');
  check(s.selected_faction==='blue','Real keyboard 2 takes over blue squad');
  await page.keyboard.press('KeyC');await until(s=>s.decisions.blue?.action==='cover');
  check(true,'Real keyboard C issues cover command');
  await page.getByRole('button',{name:'坦克增援',exact:true}).click();s=await until(s=>s.tank_spawned);check(s.units.filter(u=>u.kind==='tank').length===1,'Tank button adds exactly one tank');
  await page.getByRole('button',{name:'暂停',exact:true}).click();await until(s=>s.paused);
  await page.screenshot({path:path.join(out,'dashboard.png'),fullPage:true});
  await page.getByRole('button',{name:'正俯视',exact:true}).click();await until(s=>s.camera==='top');await page.waitForTimeout(700);await page.locator('#game').screenshot({path:path.join(out,'top-down.png')});
  // Real RTS mouse/camera paths, measured using the engine's viewport projection.
  let bounds=await canvas.boundingBox();s=await state();
  await canvas.click({position:{x:bounds.width*.50,y:bounds.height*.55}});
  await page.keyboard.press('Home');await page.waitForTimeout(650);s=await state();
  const cameraBefore=s.camera_target;
  await page.mouse.move(bounds.x+bounds.width*.5,bounds.y+bounds.height*.5);
  await page.mouse.down({button:'middle'});await page.waitForTimeout(300);await page.mouse.move(bounds.x+bounds.width*.65,bounds.y+bounds.height*.55,{steps:12});await page.waitForTimeout(350);await page.mouse.up({button:'middle'});
  s=await until(s=>Math.hypot(...s.camera_target.map((v,i)=>v-cameraBefore[i]))>.04);
  check(true,'Middle-mouse drag pans actual RTS camera');
  const afterDrag=s.camera_target;
  await page.keyboard.down('ArrowLeft');await page.waitForTimeout(450);await page.keyboard.up('ArrowLeft');
  await until(s=>Math.hypot(...s.camera_target.map((v,i)=>v-afterDrag[i]))>.015);check(true,'Arrow keys pan camera');
  const size=(await state()).camera_size;await page.mouse.wheel(0,-120);await until(s=>s.camera_size<size);check(true,'Mouse wheel zoom works after pan');
  await page.keyboard.press('Home');s=await until(s=>Math.abs(s.camera_target[0]-.61)<.01&&Math.abs(s.camera_target[1]+.01)<.01);await page.waitForTimeout(700);
  check(Math.abs(s.camera_target[0]-.61)<.01,'Home recenters camera');
  await page.keyboard.press('Digit2');await until(s=>s.selected_faction==='blue');
  s=await state();bounds=await canvas.boundingBox();
  const pixels=s.units.filter(u=>u.faction==='blue'&&u.hp>0).map(u=>[u.screen_position[0]/s.viewport[0]*bounds.width,u.screen_position[1]/s.viewport[1]*bounds.height]);
  assert(pixels.length>=2,'Need live blue units for box selection');
  await canvas.click({position:{x:pixels[0][0],y:pixels[0][1]}});await until(s=>s.units.filter(u=>u.selected).length===1);
  const x1=Math.min(...pixels.map(p=>p[0]))-15,y1=Math.min(...pixels.map(p=>p[1]))-16,x2=Math.max(...pixels.map(p=>p[0]))+15,y2=Math.max(...pixels.map(p=>p[1]))+16;
  await page.mouse.move(bounds.x+x1,bounds.y+y1);await page.mouse.down();await page.waitForTimeout(300);await page.mouse.move(bounds.x+x2,bounds.y+y2,{steps:10});await page.waitForTimeout(350);await page.mouse.up();
  s=await until(s=>s.units.filter(u=>u.selected&&u.faction==='blue').length>=2);check(true,'Real left drag box-selects multiple soldiers');
  const at=s.objective.screen_position;await canvas.click({button:'right',position:{x:at[0]/s.viewport[0]*bounds.width,y:at[1]/s.viewport[1]*bounds.height}});
  s=await until(s=>s.decisions.blue?.action==='move'&&s.command_feedback.startsWith('MOVE'));
  check(s.combat_fx.visuals>0,'Right-click ground produces move order and world feedback ring');
  await page.keyboard.press('KeyM');await until(s=>s.combat_fx.muted);await page.keyboard.press('KeyM');await until(s=>!s.combat_fx.muted);check(true,'M toggles actual audio voices');
  await page.getByRole('button',{name:'继续',exact:true}).click();await until(s=>!s.paused);
  let pcmPeak=0,audioRunning=false;
  const gameFrame=page.frames().find(f=>f.url().includes('/play/'));
  for(let i=0;i<25;i++){
   const meter=await gameFrame.evaluate(()=>{let peak=0,running=false;for(const a of window.__audioMeters){running ||= a.context.state==='running';const data=new Float32Array(a.fftSize);a.getFloatTimeDomainData(data);for(const v of data)peak=Math.max(peak,Math.abs(v))}return {peak,running}});
   pcmPeak=Math.max(pcmPeak,meter.peak);audioRunning ||= meter.running;
   if(pcmPeak>.00001)break;await page.waitForTimeout(250);
  }
  check(audioRunning&&pcmPeak>.00001,'User gesture unlocks WebAudio and actual nonzero PCM reaches destination');
  await page.getByRole('button',{name:'暂停',exact:true}).click();await until(s=>s.paused);
  await page.getByLabel('钴蓝机动队控制方式').selectOption('agent');s=await until(s=>s.control.blue==='agent');
  let a=await submit({action:'capture',faction:'blue',run_id:s.run_id,seen_tick:s.tick},true);check(a.accepted,'External Agent action round-trip has engine acknowledgement');
  a=await submit({action:'capture',faction:'blue',run_id:'stale',seen_tick:s.tick},true);check(!a.accepted&&a.message==='stale_run','Stale Agent run rejected through HTTP');
  a=await submit({action:'capture',faction:'red',run_id:s.run_id,seen_tick:s.tick},true);check(!a.accepted,'Agent cannot hijack red faction');
  await page.locator('summary').click();await page.locator('input[data-param="damage"]').fill('14');await page.locator('input[data-param="damage"]').dispatchEvent('change');s=await until(s=>s.parameters.damage===14);check(true,'Designer parameter reaches runtime');
  const previous=s.run_id;await page.getByRole('button',{name:'重新开始',exact:true}).click();s=await until(s=>s.run_id!==previous&&s.units?.length===9);check(!s.tank_spawned&&s.parameters.damage===9,'Reset restores data and removes reinforcement');
  await page.getByRole('button',{name:'战术近景',exact:true}).click();await until(s=>s.camera==='battle');
  for(let i=0;i<8;i++){await page.waitForTimeout(500);fps.push((await state()).fps)}
  await page.locator('#game').screenshot({path:path.join(out,'gameplay.png')});
  await page.setViewportSize({width:1000,height:900});await page.waitForTimeout(500);check(await page.locator('#game').isVisible(),'Responsive tablet layout preserves playable iframe');await page.screenshot({path:path.join(out,'responsive.png'),fullPage:true});
  check(errors.length===0,'No browser or game console errors');
  fs.writeFileSync(path.join(out,'browser-report.json'),JSON.stringify({passed:true,checks,errors,headless_fps:fps,audio_pcm_peak:pcmPeak,audio_context_running:audioRunning},null,2));
  console.log(JSON.stringify({passed:true,checks:checks.length,headless_fps:fps}));
 }catch(e){await page.screenshot({path:path.join(out,'failure.png'),fullPage:true});fs.writeFileSync(path.join(out,'browser-report.json'),JSON.stringify({passed:false,checks,errors,failure:String(e)},null,2));throw e}
 finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});
