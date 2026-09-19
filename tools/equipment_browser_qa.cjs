const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const fs=require('fs'),path=require('path'),assert=require('assert');
const base=process.env.DESKFRONT_URL||'http://127.0.0.1:8768',out=path.resolve(__dirname,'../output/v06');
(async()=>{const browser=await chromium.launch({headless:true}),page=await browser.newPage({viewport:{width:1720,height:1150}}),checks=[],errors=[];
page.on('pageerror',e=>errors.push(String(e)));page.on('console',m=>{if(m.type()==='error')errors.push(m.text())});
const snapshot=async()=>await(await page.request.get(base+'/api/state')).json();
async function until(fn,timeout=75000){const start=Date.now();while(Date.now()-start<timeout){const d=await snapshot();if(fn(d))return d;await page.waitForTimeout(180)}throw Error('Timeout '+fn)}
const check=(ok,test)=>{checks.push({test,passed:!!ok});assert(ok,test);console.log('PASS '+test)};
async function command(c){const session=await(await page.request.get(base+'/api/state')).json();c={instance_id:session.instance_id,run_id:session.state.run_id,...c};const r=await page.request.post(base+'/api/command',{data:c});const q=await r.json();assert(r.ok(),JSON.stringify(q));for(let i=0;i<300;i++){const a=await(await page.request.get(base+'/api/result/'+q.id)).json();if('accepted'in a){assert(a.accepted,JSON.stringify(a));return a}await page.waitForTimeout(100)}throw Error('Missing receipt')}
try{const before=(await snapshot()).state.run_id;await page.goto(base);let d=await until(d=>d.engine_live&&d.state.run_id!==before&&d.state.time>1.0);await command({action:'pause',value:true});
await page.getByLabel('全局控制方式').selectOption('player');await until(d=>Object.values(d.state.control).every(v=>v==='player'));
// Authorized design controls provide a safe route-inspection fixture. No state injection.
for(const faction of ['green','blue','red'])await command({action:'equip',faction,weapon:'rifle'});
await command({action:'move',faction:'red',position:[-.15,1.0]});
await page.getByRole('button',{name:'战术近景',exact:true}).click();
await page.locator('#garrison2').click();await until(d=>d.state.units.filter(u=>u.faction==='blue').every(u=>u.building_phase==='approaching'));
await command({action:'speed',value:2});await command({action:'pause',value:false});
d=await until(d=>d.state.units.filter(u=>u.faction==='blue').every(u=>u.building_phase==='stationed'));
await command({action:'pause',value:true});check(d.state.units.filter(u=>u.faction==='blue').every(u=>u.elevation>.17),'Real UI orders all three blue soldiers up stairs to second floor');
check(d.state.building.position[0]>.8&&d.state.building.position[1]<1.4,'Prepared building is at northeast tabletop position');
await page.screenshot({path:path.join(out,'web-building-garrison.png'),fullPage:true});
await page.locator('#exitBuilding').click();await command({action:'pause',value:false});d=await until(d=>d.state.units.filter(u=>u.faction==='blue').every(u=>u.building_phase===''));
check(d.state.units.filter(u=>u.faction==='blue').every(u=>u.elevation<.03),'Real UI evacuation goes back down to tabletop');
await command({action:'pause',value:true});await command({action:'reinforce'});await page.locator('.faction[data-team="green"] .faction-line').click();await page.locator('#manGun').click();await until(d=>d.state.at_guns.find(g=>g.faction==='green').crew_id!=='');
await command({action:'pause',value:false});d=await until(d=>d.state.at_guns.find(g=>g.faction==='green').distance_pushed>.15);
await command({action:'pause',value:true});check(true,'Designer button assigns a real crew member who physically hauls the gun');
await page.screenshot({path:path.join(out,'web-gun-hauling.png'),fullPage:true});await page.locator('#leaveGun').click();d=await until(d=>d.state.at_guns.find(g=>g.faction==='green').crew_id==='');check(true,'Designer button releases gun ownership');
check(errors.length===0,'No browser errors during building and field-gun interaction');fs.writeFileSync(path.join(out,'web-equipment.json'),JSON.stringify({passed:true,checks,errors,state:d.state},null,2));
}catch(e){fs.writeFileSync(path.join(out,'web-equipment.json'),JSON.stringify({passed:false,checks,errors,failure:String(e),snapshot:await snapshot()},null,2));await page.screenshot({path:path.join(out,'web-equipment-failure.png'),fullPage:true});throw e}finally{await browser.close()}})();
