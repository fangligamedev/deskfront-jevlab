const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const fs=require('fs'),path=require('path');
(async()=>{
 const browser=await chromium.launch({headless:true,args:['--use-angle=metal','--enable-gpu']});
 const page=await browser.newPage({viewport:{width:1600,height:1050}});
 await page.addInitScript(()=>{
  window.__deskAudio=[];const Original=window.AudioContext||window.webkitAudioContext;
  if(Original){const Observed=class extends Original{constructor(...args){super(...args);window.__deskAudio.push(this)}};window.AudioContext=Observed;if(window.webkitAudioContext)window.webkitAudioContext=Observed;}
 });
 try{
  const base=process.env.DESKFRONT_URL||'http://127.0.0.1:8776';await page.goto(base);
  await page.frameLocator('#game').locator('canvas').waitFor({timeout:60000});
  const frame=page.frames().find(f=>f.url().includes('/play/'));
  await frame.waitForFunction(()=>window.__deskAudio?.length>0,null,{timeout:60000});
  await page.frameLocator('#game').locator('canvas').click({position:{x:120,y:160}});
  await frame.waitForFunction(()=>window.__deskAudio.some(c=>c.state==='running'));
  const started=Date.now();let s;
  do{s=(await(await page.request.get(base+'/api/state')).json()).state;if(s.combat_fx?.audio_events>0)break;await page.waitForTimeout(200)}while(Date.now()-started<20000);
  const states=await frame.evaluate(()=>window.__deskAudio.map(c=>c.state));
  const report={passed:states.includes('running')&&s.combat_fx.audio_events>0,contexts:states,audio_events:s.combat_fx.audio_events,build_id:s.build_id};
  fs.writeFileSync(path.resolve(__dirname,'../output/asset-application/web-audio.json'),JSON.stringify(report,null,2));if(!report.passed)throw Error('Audio did not unlock');console.log(report);
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exit(1)});
