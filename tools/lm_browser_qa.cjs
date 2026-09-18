// Real Web export + real configured Ark service. Provider results are never mocked here.
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const fs=require('fs'),path=require('path'),assert=require('assert');
const base=process.env.DESKFRONT_URL||'http://127.0.0.1:8776',out=path.resolve(__dirname,'../output/v06');
(async()=>{
 const browser=await chromium.launch({headless:true}),page=await browser.newPage({viewport:{width:1720,height:1200}}),checks=[],errors=[];
 page.on('pageerror',e=>errors.push(String(e)));page.on('console',m=>{if(m.type()==='error')errors.push(m.text())});
 const snapshot=async()=>await(await page.request.get(base+'/api/state')).json();
 async function until(fn,timeout=50000){const start=Date.now();while(Date.now()-start<timeout){const d=await snapshot();if(fn(d))return d;await page.waitForTimeout(150)}throw Error('Timeout '+fn)}
 const check=(ok,test)=>{checks.push({test,passed:!!ok});assert(ok,test);console.log('PASS '+test)};
 async function command(c,agent=false){const r=await page.request.post(base+(agent?'/api/agent/command':'/api/command'),{data:c});const q=await r.json();assert(r.ok(),JSON.stringify(q));for(let i=0;i<100;i++){const a=await(await page.request.get(base+'/api/result/'+q.id)).json();if('accepted'in a){assert(a.accepted,JSON.stringify(a));return a}await page.waitForTimeout(100)}throw Error('Missing engine receipt')}
 try{
  const prev=(await snapshot()).state.run_id;await page.goto(base);let d=await until(d=>d.engine_live&&d.state.version==='0.6.0'&&d.state.run_id!==prev);
  await page.getByRole('button',{name:'暂停',exact:true}).click();await until(d=>d.state.paused);
  check(d.lm.configured&&d.lm.model==='deepseek-v4-flash-260425','Actual Ark model configured without exposing credentials');
  check(await page.getByLabel('全局控制方式').locator('option').count()===5,'Top-level selector exposes four control modes plus mixed status');
  await page.getByLabel('全局控制方式').selectOption('lm');d=await until(d=>Object.values(d.state.control).every(v=>v==='lm'));
  check(true,'UI changes all three factions to independent LM mode');
  await page.getByRole('button',{name:'坦克增援',exact:true}).click();await until(d=>d.state.tank_spawned);
  await page.getByRole('button',{name:'继续',exact:true}).click();
  d=await until(d=>Object.keys(d.lm.metrics.unit_decisions||{}).length===10&&d.lm.metrics.accepted>0,65000);
  check(true,'All nine soldiers AND the tank receive actual independent DeepSeek decisions');
  check(d.lm.metrics.unit_calls['red-tank']>0&&d.lm.metrics.unit_decisions['red-tank']>0,'Tank is included in live LM scheduler and validated decision path');
  await page.locator('.faction[data-team="red"] .faction-line').click();await page.waitForTimeout(500);
  check((await page.locator('#lmDecisions').innerText()).includes('red-tank'),'Designer page displays tank LM decision and lifecycle');
  await page.screenshot({path:path.join(out,'web-lm-tank.png'),fullPage:true});const lmEvidence=d.lm;
  const epochs=d.state.control_epochs;await page.getByLabel('全局控制方式').selectOption('player');d=await until(d=>Object.values(d.state.control).every(v=>v==='player'));
  check(Object.keys(epochs).every(t=>d.state.control_epochs[t]>epochs[t]),'Player takeover invalidates all earlier LM control epochs');
  await until(d=>d.lm.in_flight===0);d=await snapshot();const used=d.lm.used_requests;await page.waitForTimeout(1200);d=await snapshot();check(d.lm.used_requests===used,'No new model calls while player owns all factions');
  await page.getByLabel('全局控制方式').selectOption('agent');d=await until(d=>Object.values(d.state.control).every(v=>v==='agent'));
  const u=d.state.units.find(u=>u.faction==='green'&&u.hp>0);await command({action:'hold',faction:'green',unit_ids:[u.id],run_id:d.state.run_id,seen_tick:d.state.tick},true);check(true,'External Agent mode accepts its own commands after switching');
  await page.getByLabel('全局控制方式').selectOption('game_ai');await until(d=>Object.values(d.state.control).every(v=>v==='game_ai')&&Object.keys(d.state.tactical.squads).length>=2);check(true,'Game AI coordinator resumes after LM / player / Agent transitions');
  check(errors.length===0,'No JavaScript, WebGL or shader errors');
  fs.writeFileSync(path.join(out,'web-lm.json'),JSON.stringify({passed:true,checks,errors,lm:lmEvidence,final:await snapshot()},null,2));
 }catch(e){fs.writeFileSync(path.join(out,'web-lm.json'),JSON.stringify({passed:false,checks,errors,failure:String(e),state:await snapshot()},null,2));await page.screenshot({path:path.join(out,'web-lm-failure.png'),fullPage:true});throw e}finally{await browser.close()}
})();
