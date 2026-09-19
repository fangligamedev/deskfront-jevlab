// Final exported game's asset/map controls; real WebGL, input and engine acknowledgements.
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const fs=require('fs'),path=require('path');
const out=path.resolve(__dirname,'../output/asset-application');
(async()=>{
 const browser=await chromium.launch({headless:true,args:['--use-angle=metal','--enable-gpu']});
 const page=await browser.newPage({viewport:{width:1720,height:1120}});
 const base=process.env.DESKFRONT_URL||'http://127.0.0.1:8774',checks=[],errors=[];
 page.on('pageerror',e=>errors.push(String(e)));page.on('console',m=>{if(m.type()==='error')errors.push(m.text())});
 const state=async()=> (await(await page.request.get(base+'/api/state')).json()).state;
 const check=(ok,test)=>{checks.push({test,passed:!!ok});if(!ok)throw Error(test);console.log('PASS '+test)};
 async function until(fn,timeout=25000){const start=Date.now();while(Date.now()-start<timeout){const s=await state();if(fn(s))return s;await page.waitForTimeout(150)}throw Error('Timeout '+fn)}
 async function command(c){const session=await(await page.request.get(base+'/api/state')).json();c={instance_id:session.instance_id,run_id:session.state.run_id,...c};const r=await page.request.post(base+'/api/command',{data:c});const q=await r.json();if(!r.ok())throw Error(JSON.stringify(q));for(let i=0;i<100;i++){const a=await(await page.request.get(base+'/api/result/'+q.id)).json();if('accepted'in a){if(!a.accepted)throw Error(JSON.stringify(a));return a}await page.waitForTimeout(150)}throw Error('No engine ack')}
 try{
  const prev=(await state()).run_id;await page.goto(base);let s=await until(s=>s.run_id!==prev&&s.units?.length===9);
  check(s.units.length===9&&s.units.every(u=>u.bone_count===50),'Final Web export loads nine 50-bone soldiers');
  const start=s.worker_animation_time;s=await until(s=>s.worker_animation_time>start+.2);check(true,'New office worker typing advances in Web');
  check(s.build_id===JSON.parse(fs.readFileSync(path.resolve(__dirname,'../data/build-info.json'),'utf8')).id,'Loaded Web build matches current main-game source fingerprint');
  await page.screenshot({path:path.join(out,'web-main-office.png'),fullPage:true});
  for(const [index,id] of [[1,'river'],[2,'outpost'],[0,'crossroads']]){
   const prior=s.run_id;await page.getByLabel('战场地图').selectOption(String(index));s=await until(s=>s.map===id&&s.run_id!==prior);
   await page.waitForFunction(run=>state.run_id===run,s.run_id);
   check(s.units.length===9&&!s.tank_spawned,'Map selector resets battle into '+id);
  }
  await page.getByRole('button',{name:'暂停',exact:true}).click();s=await until(s=>s.paused);
  await page.getByLabel('装备武器').selectOption('pistol');s=await until(s=>s.units.filter(u=>u.faction==='green').every(u=>u.weapon==='pistol'&&u.ammo===12));check(true,'Pistol asset and magazine selected through designer UI');
  await page.getByLabel('装备武器').selectOption('rocket');await until(s=>s.units.filter(u=>u.faction==='green').every(u=>u.weapon==='rocket'));check(true,'Rocket loadout replacement reaches live engine');
  await page.getByLabel('装备武器').selectOption('rifle');await until(s=>s.units.filter(u=>u.faction==='green').every(u=>u.weapon==='rifle'));
  for(const faction of ['green','blue','red']){
   await command({action:'control',faction,mode:'player'});await command({action:'hold',faction});
   // Controlled asset fixture: approach inside grenade range but outside pistol
   // range, so survival AI correctly refusing under heavy fire is not a flaky test.
   if(faction!=='green')await command({action:'equip',faction,weapon:'pistol'});
  }
  await command({action:'config',key:'damage',value:1});await command({action:'config',key:'speed',value:.3});await command({action:'speed',value:3});
  await command({action:'move',faction:'green',unit_ids:['green-1'],position:[1.08,1.75]});
  const initial=s.units.find(u=>u.id==='green-1').position;
  await command({action:'pause',value:false});
  s=await until(s=>{const u=s.units.find(u=>u.id==='green-1');return u.hp>0&&s.units.some(e=>e.faction!=='green'&&e.hp>0&&Math.hypot(e.position[0]-u.position[0],e.position[1]-u.position[1])<.59)},45000);
  check(s.units.find(u=>u.id==='green-1').root_distance>.3&&Math.hypot(...s.units.find(u=>u.id==='green-1').position.map((v,i)=>v-initial[i]))>.3,'Web movement uses root distance over long route');
  await page.locator('.faction[data-team="green"] .faction-line').click();
  // Freeze only after eligibility, then re-read: real combat may suppress a unit
  // between an observed snapshot and command execution. Never bypass that rejection.
  let grenadeReady=false;
  for(let attempt=0;attempt<8&&!grenadeReady;attempt++){
   await until(s=>s.units.find(u=>u.id==='green-1').available_actions.includes('grenade'));
   await command({action:'pause',value:true});s=await until(s=>s.paused);
   grenadeReady=s.units.find(u=>u.id==='green-1').available_actions.includes('grenade');
   if(!grenadeReady)await command({action:'pause',value:false});
  }
  if(!grenadeReady)throw Error('No stable eligible grenade state');
  await command({action:'grenade',faction:'green',unit_ids:['green-1']});
  await command({action:'pause',value:false});s=await until(s=>(s.combat_fx.launched.grenade||0)>0);
  check(s.units.filter(u=>u.faction==='green').some(u=>u.grenades===1),'Grenade command consumes inventory after release');
  s=await until(s=>s.combat_fx.impacts>0&&s.combat_fx.visuals>0);check(true,'Final Web effects and impacts remain active');
  await page.getByRole('button',{name:'坦克增援',exact:true}).click();s=await until(s=>s.tank_spawned);check(s.units.some(u=>u.kind==='tank'),'T2 reinforcement appears in final Web export');
  await page.getByRole('button',{name:'正俯视',exact:true}).click();await until(s=>s.camera==='top');
  await page.screenshot({path:path.join(out,'web-assets.png'),fullPage:true});
  check(errors.length===0,'No final Web console/shader errors');
  fs.writeFileSync(path.join(out,'web-assets.json'),JSON.stringify({passed:true,checks,errors,final:await state()},null,2));
 }catch(e){fs.writeFileSync(path.join(out,'web-assets.json'),JSON.stringify({passed:false,checks,errors,failure:String(e),state:await state()},null,2));await page.screenshot({path:path.join(out,'web-assets-failure.png'),fullPage:true});throw e}
 finally{await browser.close()}
})();
