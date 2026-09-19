// Verify the exported build identity, real canvas input and browser audio unlock.
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const fs=require('fs'),path=require('path'),assert=require('assert');
const base=process.env.DESKFRONT_URL||'http://127.0.0.1:8781';
const out=path.resolve(__dirname,'../docs/evidence/latest-integration');
(async()=>{
 const browser=await chromium.launch({headless:true});
 const page=await browser.newPage({viewport:{width:1440,height:960}}),errors=[];
 page.on('pageerror',e=>errors.push(String(e)));
 page.on('console',m=>{if(m.type()==='error')errors.push(m.text())});
 await page.addInitScript(()=>{window.__qaAudio=[];const Audio=window.AudioContext;if(Audio)window.AudioContext=class extends Audio{constructor(...a){super(...a);window.__qaAudio.push(this)}}});
 try{
  await page.goto(base);
  const frame=await (await page.locator('#game').elementHandle()).contentFrame();
  await frame.waitForFunction(()=>window.__deskfrontState?.build_id,{},{timeout:90000});
  await page.waitForFunction(()=>live&&sessionCurrent,{},{timeout:45000});
  await page.getByRole('button',{name:'战术近景',exact:true}).click();
  await frame.waitForFunction(()=>window.__deskfrontState?.camera==='battle',{},{timeout:30000});
  await frame.locator('#canvas').click({position:{x:300,y:260}});
  await frame.waitForFunction(()=>window.__qaAudio.length>0&&window.__qaAudio.every(c=>c.state==='running'),{},{timeout:30000});
  const result=await frame.evaluate(()=>({build_id:window.__deskfrontState.build_id,version:window.__deskfrontState.version,resource_hash:window.__deskfrontState.resource_hash,bones:window.__deskfrontState.units.map(u=>u.bone_count),audio:window.__qaAudio.map(c=>({state:c.state,sampleRate:c.sampleRate})),camera:window.__deskfrontState.camera}));
  assert.equal(result.build_id,require('../build/web/build-info.json').id);
  assert.equal(result.version,require('../package.json').version);
  assert(result.bones.length===9&&result.bones.every(b=>b===50));
  assert.equal(errors.length,0,JSON.stringify(errors));
  fs.writeFileSync(path.join(out,'web-smoke.json'),JSON.stringify({passed:true,errors,...result},null,2));
  await page.screenshot({path:path.join(out,'integrated-game.png'),fullPage:true});
  console.log(JSON.stringify({passed:true,...result}));
 }catch(e){fs.writeFileSync(path.join(out,'web-smoke.json'),JSON.stringify({passed:false,error:String(e),errors},null,2));throw e}
 finally{await browser.close()}
})();
