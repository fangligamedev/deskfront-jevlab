/* Presentation modes never mutate the running battle. Window ownership is explicit. */
(()=>{
 const query=new URLSearchParams(location.search);
 let current=['overview','execution','game','demo','eastfront'].includes(query.get('view'))?query.get('view'):'overview';
 let remote=query.has('native'),popup=null;
 function setView(mode){
  current=mode;document.body.dataset.view=mode;
  document.querySelectorAll('[data-view]').forEach(b=>{b.setAttribute('aria-pressed',String(b.dataset.view===mode))});
  const url=new URL(location.href);url.searchParams.set('view',mode);history.replaceState(null,'',url);
  document.title=({overview:'策划网页',execution:'战术执行',game:'独立游戏',demo:'演示导演',eastfront:'无尽东线'})[mode]+' · Deskfront';
 }
 const api={get mode(){return current},get remote(){return remote},setRemote(value){remote=value;if(value)sessionStorage.removeItem('deskfront-engine-owner');document.body.classList.toggle('remote-game',value);document.querySelector('#remoteGame').hidden=!value;},setView};
 window.DeskfrontViews=api;
 document.querySelectorAll('[data-view]').forEach(b=>b.onclick=()=>setView(b.dataset.view));
 const dialog=document.querySelector('#windowDialog');
 function gameWindowURL(){return '/?view=game'+(typeof state!=='undefined'&&state.eastfront?.enabled?'&campaign=eastfront':'')}
 function openWindowDialog(){
  document.querySelector('.standalone-link').href=gameWindowURL();
  if(popup&&!popup.closed){popup.focus();return}
  dialog.showModal();
 }
 document.querySelector('#openGameWindow').onclick=openWindowDialog;
 document.querySelector('#gamePopout').onclick=openWindowDialog;
 document.querySelector('#cancelGameWindow').onclick=()=>dialog.close();
 document.querySelector('#createGameWindow').onclick=()=>{
  // window.open stays inside the user's click, before any asynchronous request.
  popup=window.open(gameWindowURL(),'deskfront-game-'+location.port,'popup=yes,width=1440,height=960,resizable=yes,scrollbars=yes');
  if(!popup){document.querySelector('#windowHelp').textContent='浏览器拦截了窗口。请允许本站弹出窗口后重试；也可以选择下方「当前页面放大游戏」。';return}
  dialog.close();document.querySelector('#viewStatus').textContent='正在启动独立游戏窗口…';
  setTimeout(()=>{if(!remote){document.querySelector('#windowHelp').textContent='独立窗口尚未连接。可用下方游戏专页链接打开，或在当前页面放大游戏。新窗口会开始新局。';dialog.showModal();}},10000);
 };
 document.querySelector('#expandGame').onclick=()=>{dialog.close();setView('game')};
 document.querySelector('#gameBack').onclick=()=>setView('overview');
 document.querySelector('#gameFullscreen').onclick=()=>{
  const p=document.querySelector('.game-panel');
  if(!document.fullscreenEnabled){document.querySelector('#viewStatus').textContent='浏览器不支持全屏，请使用独立游戏视图。';setView('game');return}
  const result=document.fullscreenElement?document.exitFullscreen?.():p.requestFullscreen?.();
  result?.catch(()=>{document.querySelector('#viewStatus').textContent='浏览器未允许全屏；仍可使用放大的游戏视图。'});
 };
 window.addEventListener('message',e=>{
  if(e.origin!==location.origin||!popup||e.source!==popup||e.data?.type!=='deskfront-game-ready')return;
  api.setRemote(true);
  const frame=document.querySelector('#game');if(frame)frame.src='about:blank';
  document.querySelector('#viewStatus').textContent='独立游戏窗口已启动新局；此网页的指令继续控制该窗口。';
 });
 document.querySelector('#focusGameWindow').onclick=()=>{if(popup&&!popup.closed)popup.focus();else document.querySelector('#viewStatus').textContent='请切换到已打开的游戏窗口；如果已关闭，可在网页重新开始。'};
 document.querySelector('#resumeEmbedded').onclick=()=>document.querySelector('#resumeDialog').showModal();
 document.querySelector('#cancelResume').onclick=()=>document.querySelector('#resumeDialog').close();
 document.querySelector('#confirmResume').onclick=()=>{document.querySelector('#resumeDialog').close();window.dispatchEvent(new Event('deskfront-new-embedded'))};
 setInterval(()=>{if(popup?.closed){popup=null;document.querySelector('#viewStatus').textContent='独立窗口已关闭。可点击「在网页重新开始」启动新局。'}},1000);
 setView(current);
})();
