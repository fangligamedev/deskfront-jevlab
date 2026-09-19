// Real exported Web build, isolated deterministic LM server; no cloud calls.
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const fs=require('fs'),path=require('path'),assert=require('assert');
const base='http://127.0.0.1:8784',out=path.resolve(__dirname,'../docs/evidence/motion-continuity');
(async()=>{
 const browser=await chromium.launch({headless:false}),page=await browser.newPage({viewport:{width:1360,height:960}}),errors=[],warnings=[],rows=[];
 page.on('pageerror',e=>errors.push(String(e)));page.on('console',m=>{if(m.type()==='error'){const entry={text:m.text(),url:m.location().url};(entry.url.endsWith('/favicon.ico')?warnings:errors).push(entry)}});
 await page.addInitScript(()=>{window.__qaAudio=[];const A=window.AudioContext;if(A)window.AudioContext=class extends A{constructor(...a){super(...a);window.__qaAudio.push(this)}}});
 const snapshot=async()=>await(await page.request.get(base+'/api/state')).json();
 async function until(fn){for(let i=0;i<600;i++){const d=await snapshot();if(fn(d.state,d))return d.state;await page.waitForTimeout(150)}throw Error('Timeout '+fn)}
 try{
  assert.equal((await snapshot()).lm.model,'deterministic-flag-test-client');
  await page.goto(base);await until(s=>s?.build_id===require('../data/build-info.json').id);await page.waitForFunction(()=>live&&sessionCurrent);
  const frame=await(await page.locator('#game').elementHandle()).contentFrame();
  await frame.locator('#canvas').click({position:{x:300,y:260}});await frame.waitForFunction(()=>window.__qaAudio.some(a=>a.state==='running'));
  await page.getByRole('button',{name:'战术近景',exact:true}).click();
  for(const mode of ['game_ai','lm']){
   await page.getByLabel('全局控制方式').selectOption(mode);await until(s=>Object.values(s.control).every(c=>c===mode));
   const measured=await frame.evaluate(()=>new Promise(resolve=>{const samples=[],states=[],start=performance.now();let previous=start;function next(now){samples.push(now-previous);previous=now;if(window.__deskfrontState)states.push({time:window.__deskfrontState.time,fps:window.__deskfrontState.fps,moving:window.__deskfrontState.units.filter(u=>u.movement_speed>0).length});if(now-start<8000)requestAnimationFrame(next);else{const gl=document.querySelector('#canvas').getContext('webgl2'),ext=gl?.getExtension('WEBGL_debug_renderer_info');resolve({samples,states,renderer:ext?gl.getParameter(ext.UNMASKED_RENDERER_WEBGL):'unknown'})}}requestAnimationFrame(next)}));
   const sorted=measured.samples.slice(5).sort((a,b)=>a-b);rows.push({mode,frames:sorted.length,median_ms:sorted[Math.floor(sorted.length*.5)],p95_ms:sorted[Math.floor(sorted.length*.95)],renderer:measured.renderer,states:measured.states.filter((_,i)=>i%30===0)});
   await page.screenshot({path:path.join(out,mode+'-web.png')});
  }
  const s=(await snapshot()).state;assert.equal(errors.length,0,JSON.stringify(errors));
  fs.writeFileSync(path.join(out,'web.json'),JSON.stringify({passed:true,build_id:s.build_id,errors,warnings,rows,audio:await frame.evaluate(()=>window.__qaAudio.map(a=>a.state)),note:'Isolated deterministic LM for integration; not cloud inference latency.'},null,2));console.log(JSON.stringify({passed:true,build_id:s.build_id,rows:rows.map(({states,...r})=>r)}));
 }catch(e){fs.writeFileSync(path.join(out,'web.json'),JSON.stringify({passed:false,error:String(e),errors,rows},null,2));throw e}
 finally{await browser.close()}
})();
