// Exercise real browser hardware input against the exported Godot world.
const {chromium}=require('playwright');
const fs=require('fs'),path=require('path'),assert=require('assert');
const base=process.env.RTS_TEST_URL||'http://127.0.0.1:8787';
const out=path.resolve(__dirname,'../docs/evidence/rts-controls');fs.mkdirSync(out,{recursive:true});
(async()=>{
 const browser=await chromium.launch({headless:true,args:['--use-angle=metal','--enable-gpu']});
 const page=await browser.newPage({viewport:{width:1680,height:1100}}),checks=[],errors=[];
 page.on('pageerror',e=>errors.push(String(e)));page.on('console',m=>{if(m.type()==='error'||/SCRIPT ERROR|SHADER ERROR/.test(m.text()))errors.push(m.text())});
 const state=async()=> (await(await page.request.get(base+'/api/state')).json()).state;
 const check=(ok,label)=>{checks.push({test:label,passed:!!ok});assert(ok,label);console.log('PASS',label)};
 async function until(fn,timeout=16000){const end=Date.now()+timeout;while(Date.now()<end){const s=await state();if(fn(s))return s;await page.waitForTimeout(100)}throw Error('Timeout '+fn.toString())}
 async function command(c){const session=await(await page.request.get(base+'/api/state')).json();const res=await page.request.post(base+'/api/command',{data:{faction:'green',...c,instance_id:session.instance_id,run_id:session.state.run_id}});const q=await res.json();assert(res.ok(),JSON.stringify(q));for(let i=0;i<70;i++){const ack=await(await page.request.get(base+'/api/result/'+q.id)).json();if('accepted'in ack){assert(ack.accepted,JSON.stringify(ack));return ack}await page.waitForTimeout(100)}throw Error('No receipt')}
 let canvas;
 async function box(){return canvas.boundingBox()}
 async function point(p,s){s=s||await state();const b=await box();return {x:b.x+p[0]/s.viewport[0]*b.width,y:b.y+p[1]/s.viewport[1]*b.height}}
 async function unitPoint(id){const s=await state();return point(s.units.find(u=>u.id===id).screen_position,s)}
 async function clickUnit(id,button='left'){const p=await unitPoint(id);await page.mouse.click(p.x,p.y,{button})}
 async function centerMouse(){const b=await box();await page.mouse.move(b.x+b.width*.5,b.y+b.height*.55)}
 async function pressMove(key){const before=(await state()).camera_target;await page.keyboard.down(key);await page.waitForTimeout(180);await page.keyboard.up(key);const s=await until(s=>Math.hypot(...s.camera_target.map((v,i)=>v-before[i]))>.03);return {before,after:s.camera_target}}
 async function boot(url){const previous=(await state()).run_id;await page.goto(url);await until(s=>s.run_id&&s.run_id!==previous&&s.rts);await page.waitForFunction(()=>live&&state.units?.length);canvas=page.frameLocator('#game').locator('canvas');await canvas.waitFor();await canvas.scrollIntoViewIfNeeded()}
 async function key(key){await page.keyboard.press(key);await page.waitForTimeout(150)}
 async function restore(){await key('Home');await centerMouse();await page.waitForTimeout(550)}
 async function drag(a,b){await page.mouse.move(a.x,a.y);await page.mouse.down();await page.mouse.move(b.x,b.y,{steps:8});await page.mouse.up()}
 try{
  await boot(base+'/?view=execution');await command({action:'pause',value:true});
  for(const faction of ['green','blue','red']){await command({action:'control',faction,mode:'player'});await command({action:'hold',faction})}
  await command({action:'control',faction:'green',mode:'player'});
  await page.locator('[data-camera="top"]').click();await until(s=>s.camera==='top');await page.waitForTimeout(650);
  await canvas.click({position:{x:250,y:180}});await key('b');await until(s=>!s.edge_pan);
  for(const [k,idx,sign] of [['w',1,-1],['s',1,1],['a',0,-1],['d',0,1],['ArrowUp',1,-1],['ArrowDown',1,1],['ArrowLeft',0,-1],['ArrowRight',0,1]]){
   await restore();const d=await pressMove(k);check((d.after[idx]-d.before[idx])*sign>.02,k+' pans in correct screen direction');
  }
  check(Object.values((await state()).control).every(v=>v==='player'),'WASD never hands control back to LLM');
  await restore();let before=(await state()).camera_target,b=await box();await page.mouse.move(b.x+b.width*.5,b.y+b.height*.5);await page.mouse.down({button:'middle'});await page.mouse.move(b.x+b.width*.5+110,b.y+b.height*.5+60,{steps:8});await page.mouse.up({button:'middle'});
  await until(s=>Math.hypot(...s.camera_target.map((v,i)=>v-before[i]))>.08&&!s.rts.panning);check(true,'middle drag pans camera and releases cleanly');
  await restore();b=await box();await page.mouse.move(b.x+b.width*.55,b.y+b.height*.55);const oldZoom=(await state()).camera_size;const scroll=await page.evaluate(()=>scrollY);await page.mouse.wheel(0,-180);await until(s=>s.camera_size<oldZoom);check(await page.evaluate(()=>scrollY)===scroll,'wheel zoom is captured by game without scrolling page');
  before=(await state()).rts.yaw;await pressMove('d');await page.keyboard.down('q');await page.waitForTimeout(200);await page.keyboard.up('q');await until(s=>Math.abs(s.rts.yaw-before)>.05);check(true,'Q rotates camera');
  b=await box();const oldPitch=(await state()).rts.pitch;await page.keyboard.down('Alt');await page.mouse.move(b.x+b.width*.5,b.y+b.height*.5);await page.mouse.down();await page.mouse.move(b.x+b.width*.5+70,b.y+b.height*.5-70,{steps:8});await page.mouse.up();await page.keyboard.up('Alt');await until(s=>Math.abs(s.rts.pitch-oldPitch)>.05&&!s.rts.rotating);check(true,'Alt drag rotates and tilts without selecting');
  await restore();await key('b');await until(s=>s.edge_pan);
  for(const [name,fx,fy] of [['left',.003,.5],['right',.997,.5],['top',.5,.003],['bottom',.5,.997]]){
   before=(await state()).camera_target;b=await box();await page.mouse.move(b.x+b.width*fx,b.y+b.height*fy);await page.waitForTimeout(230);await centerMouse();await until(s=>Math.hypot(...s.camera_target.map((v,i)=>v-before[i]))>.025);check(true,name+' edge pans, including non-interactive HUD area');
  }
  await key('b');await until(s=>!s.edge_pan);await restore();await key('1');await key('f');await page.waitForTimeout(600);
  for(let i=0;i<7;i++)await key('PageUp');await page.waitForTimeout(250);
  await clickUnit('green-1');await until(s=>s.rts.selected_ids.length===1&&s.rts.selected_ids[0]==='green-1');check(true,'click picks one soldier at current zoom');
  await page.keyboard.down('Shift');await clickUnit('green-2');await page.keyboard.up('Shift');await until(s=>s.rts.selected_ids.length===2);check(true,'Shift-click adds second soldier');
  await page.keyboard.down('Shift');await clickUnit('green-2');await page.keyboard.up('Shift');await until(s=>s.rts.selected_ids.length===1);check(true,'Shift-click toggles soldier off');
  await key('Escape');await until(s=>s.rts.selected_ids.length===0);let p=await unitPoint('green-1');await drag({x:p.x-7,y:p.y-7},{x:p.x+7,y:p.y+7});await until(s=>s.rts.selected_ids.length===1&&s.rts.selected_ids[0]==='green-1');check(true,'tight drag box selects one soldier');
  const pts=await Promise.all(['green-1','green-2','green-3'].map(unitPoint));await drag({x:Math.max(...pts.map(p=>p.x))+10,y:Math.max(...pts.map(p=>p.y))+10},{x:Math.min(...pts.map(p=>p.x))-10,y:Math.min(...pts.map(p=>p.y))-10});await until(s=>s.rts.selected_ids.length===3);check(true,'reverse drag box selects the whole friendly squad');
  await key('Control+4');await key('Escape');await key('4');await until(s=>s.rts.selected_ids.length===3);check(true,'Ctrl-number assignment and recall preserve exact units');
  await pressMove('d');await page.keyboard.press('4');await page.keyboard.press('4');await page.waitForTimeout(500);const focused=await state(),centroid=focused.units.filter(u=>u.selected).reduce((p,u)=>[p[0]+u.position[0]/3,p[1]+u.position[1]/3],[0,0]);check(Math.hypot(...focused.camera_target.map((v,i)=>v-centroid[i]))<.01,'double-tap group centers camera');
  await clickUnit('green-1');await until(s=>s.rts.selected_ids.length===1);await restore();let s=await state();const enemy=s.units.find(u=>u.faction==='red'&&u.kind!=='tank'&&u.hp>0);await clickUnit(enemy.id,'right');s=await until(s=>s.rts.last_order?.action==='attack');check(s.rts.last_order.accepted&&s.rts.last_order.target_id===enemy.id&&s.rts.last_order.unit_ids.length===1,'right-click enemy issues targeted attack for selected soldier only');
  b=await box();await page.mouse.click(b.x+b.width*.55,b.y+b.height*.57,{button:'right'});s=await until(s=>s.rts.last_order?.action==='move');check(s.rts.last_order.accepted,'right-click empty ground dispatches movement');
  const original=s.units.find(u=>u.id==='green-1').position;await command({action:'pause',value:false});await until(s=>Math.hypot(...s.units.find(u=>u.id==='green-1').position.map((v,i)=>v-original[i]))>.025);await command({action:'pause',value:true});check(true,'selected soldier physically follows the right-click move');
  await page.screenshot({path:path.join(out,'sandbox.png')});
  // Loss of iframe keyboard focus must release a held navigation key.
  await centerMouse();await page.keyboard.down('d');await page.waitForTimeout(100);await page.locator('#executionControl').click();await page.keyboard.up('d');await page.keyboard.press('Escape');await page.waitForTimeout(400);before=(await state()).camera_target;await page.waitForTimeout(400);s=await state();check(Math.hypot(...s.camera_target.map((v,i)=>v-before[i]))<.002,'leaving canvas focus does not leave camera drifting');
  await boot(base+'/?view=eastfront');await page.locator('#eastControl').selectOption('player');await page.locator('#eastTakeover').click();await until(s=>s.control.green==='player');await command({action:'pause',value:true});
  await canvas.click({position:{x:240,y:200}});s=await state();if(s.edge_pan)await key('b');await key('1');await key('f');await page.waitForTimeout(600);before=(await state()).camera_target;await pressMove('d');s=await state();check(!s.eastfront.follow&&Math.hypot(...s.camera_target.map((v,i)=>v-before[i]))>.03,'manual RTS camera overrides eastfront follow');
  await key('f');await page.waitForTimeout(500);await clickUnit('green-1');await until(s=>s.rts.selected_ids.length===1);check(true,'eastfront RTS allows single-soldier selection');
  await page.locator('#expandGame').count();await page.screenshot({path:path.join(out,'eastfront.png')});
  check(errors.length===0,'no JavaScript, Godot or WebGL errors');
  fs.writeFileSync(path.join(out,'web.json'),JSON.stringify({passed:true,checks,errors,build:(await state()).build_id,final:await state()},null,2));
 }catch(e){fs.writeFileSync(path.join(out,'web.json'),JSON.stringify({passed:false,checks,errors,failure:String(e),state:await state()},null,2));await page.screenshot({path:path.join(out,'failure.png'),fullPage:true});throw e}finally{await browser.close()}
})();
