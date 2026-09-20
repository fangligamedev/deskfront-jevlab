// UI sends commands; Godot owns possession, movement and damage.
(()=>{
 const status=document.getElementById('shooterStatus');
 async function enter(view){
  if(typeof state==='undefined'||!state?.units)return;
  const unit=state.units.find(u=>u.selected&&u.hp>0&&u.kind==='infantry');
  if(!unit){status.textContent='请先在游戏中选中一名步兵。';return}
  if(state.paused){status.textContent='请先点击继续，再接管步兵。';return}
  await command({action:'possess',unit_id:unit.id,view,faction:unit.faction});
  status.textContent='点击游戏画面锁定鼠标；WASD 移动，E 掩体，右键探身，左键射击。';
 }
 document.getElementById('possessThird').onclick=()=>enter('third');
 document.getElementById('possessFirst').onclick=()=>enter('first');
 document.getElementById('releaseUnit').onclick=()=>command({action:'release_unit'});
})();
