const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const fs=require('fs'),path=require('path'),assert=require('assert');
const base='http://127.0.0.1:8784',out=path.resolve(__dirname,'../docs/evidence/office-battlefield');
(async()=>{
 const browser=await chromium.launch({headless:false}),page=await browser.newPage({viewport:{width:1560,height:1100}}),checks=[],errors=[],warnings=[];
 const check=(ok,test)=>{checks.push({test,passed:!!ok});assert(ok,test)};
 page.on('pageerror',e=>errors.push(String(e)));page.on('console',m=>{if(m.type()==='error'){const e={text:m.text(),url:m.location().url};(e.url.endsWith('/favicon.ico')?warnings:errors).push(e)}});
 await page.addInitScript(()=>{window.__qaAudio=[];const A=window.AudioContext;if(A)window.AudioContext=class extends A{constructor(...a){super(...a);window.__qaAudio.push(this)}}});
 const snapshot=async()=>await(await page.request.get(base+'/api/state')).json();
 async function until(fn,ms=60000){const start=Date.now();while(Date.now()-start<ms){const d=await snapshot();if(fn(d.state,d))return d.state;await page.waitForTimeout(150)}throw Error('Timeout '+fn)}
 async function command(c){const d=await snapshot(),r=await page.request.post(base+'/api/command',{data:{instance_id:d.instance_id,run_id:d.state.run_id,...c}}),q=await r.json();assert(r.ok(),JSON.stringify(q));for(let i=0;i<100;i++){const a=await(await page.request.get(base+'/api/result/'+q.id)).json();if('accepted'in a){assert(a.accepted,JSON.stringify(a));return a}await page.waitForTimeout(100)}throw Error('ack timeout')}
 try{
  assert.equal((await snapshot()).lm.model,'deterministic-flag-test-client');
  await page.goto(base);let s=await until(s=>s?.build_id===require('../data/build-info.json').id&&s.map==='office-front');await page.waitForFunction(()=>live&&sessionCurrent);
  check(s.map_index===3&&s.bounds[2]>3,'new office is the default exported map');check(s.covers.length===16&&s.building&&Object.keys(s.building).length===0,'office props replace sandbox fortifications');
  await page.getByLabel('全局控制方式').selectOption('player');await until(s=>Object.values(s.control).every(m=>m==='player'));
  await command({action:'control',faction:'green',mode:'player'});
  await page.getByRole('button',{name:'正俯视',exact:true}).click();await until(s=>s.camera==='top');
  await page.waitForTimeout(900);
  const frame=await(await page.locator('#game').elementHandle()).contentFrame(),canvas=frame.locator('#canvas');
  const point=async p=>{const box=await canvas.boundingBox(),s=(await snapshot()).state;return{x:p[0]*box.width/s.viewport[0],y:p[1]*box.height/s.viewport[1]}};
  s=(await snapshot()).state;const id='green-2',u=s.units.find(u=>u.id===id),origin=u.position;
  await canvas.click({position:await point(u.screen_position)});await until(s=>s.units.filter(u=>u.selected).length===1&&s.units.find(u=>u.id===id).selected);
  await frame.waitForFunction(()=>window.__qaAudio.some(c=>c.state==='running'));
  s=(await snapshot()).state;await canvas.click({button:'right',position:await point(s.objective.screen_position)});
  s=await until(s=>s.objective.flag.owner==='green');
  check(s.units.find(u=>u.id===id).root_distance>1,'real mouse selection and ground order move soldier around office props');
  check(s.objective.flag.countdown_seconds>0&&s.objective.flag.countdown_seconds<=30,'real movement into office flag starts countdown');
  await command({action:'pause',value:true});await page.screenshot({path:path.join(out,'web-top.png')});await canvas.screenshot({path:path.join(out,'web-top-game.png')});
  await page.getByRole('button',{name:'战术近景',exact:true}).click();await until(s=>s.camera==='battle');await page.waitForTimeout(900);await canvas.screenshot({path:path.join(out,'web-battle-game.png')});
  await page.getByRole('button',{name:'坦克增援',exact:true}).click();await command({action:'pause',value:false});await until(s=>s.tank_reserve?.deployment_phase==='active');
  check(true,'tank drives onto expanded desktop in exported game');
  await page.getByLabel('全局控制方式').selectOption('game_ai');await until(s=>Object.values(s.control).every(m=>m==='game_ai'));await page.waitForTimeout(2500);
  s=(await snapshot()).state;check(errors.length===0,'no game script shader or browser errors');
  fs.writeFileSync(path.join(out,'web.json'),JSON.stringify({passed:true,checks,errors,warnings,build_id:s.build_id,map:s.map,fps:s.fps,origin,final_position:s.units.find(u=>u.id===id).position,audio:await frame.evaluate(()=>window.__qaAudio.map(c=>c.state)),provider:'isolated deterministic test LM, no cloud calls'},null,2));console.log(JSON.stringify({passed:true,checks,build_id:s.build_id,fps:s.fps}));
 }catch(e){fs.writeFileSync(path.join(out,'web.json'),JSON.stringify({passed:false,checks,errors,warnings,error:String(e)},null,2));await page.screenshot({path:path.join(out,'web-failure.png')});throw e}
 finally{await browser.close()}
})();
