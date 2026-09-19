extends Node
## Authoritative continuous central-flag timer. Contested occupancy freezes the holder's clock.
var holder: String=""
var held_seconds: float=0.0
var required_seconds: float=30.0
var contested: bool=false
var capture_epoch: int=0
func advance(teams: Array, delta: float) -> String:
 var previous: String=holder
 contested=teams.size()>1
 if teams.is_empty():holder="";held_seconds=0
 elif teams.size()==1:
  if holder!=teams[0]:holder=teams[0];held_seconds=0
  held_seconds+=delta
 elif not teams.has(holder):holder="";held_seconds=0
 if previous!=holder:capture_epoch+=1
 held_seconds=minf(held_seconds,required_seconds)
 if required_seconds-held_seconds<=1e-8:held_seconds=required_seconds
 return holder if holder!="" and held_seconds>=required_seconds else ""
func remaining() -> float:
 return maxf(0,required_seconds-held_seconds)
func emergency_for(team: String) -> bool:
 return holder!="" and holder!=team and remaining()>0
func warning_for(team: String) -> Dictionary:
 if not emergency_for(team):return {"active":false}
 var seconds: int=int(ceil(remaining()))
 var message: String="紧急夺旗预警：%s 已占领中央旗点！剩余 %d 秒，守满即判你方战败。立即不惜伤亡反攻，先进入旗圈阻断倒计时，再清除守军夺回旗帜；不得继续消极守楼、守炮或等待。" % [holder,seconds]
 if contested:message="旗点正在争夺，败北倒计时暂停在 %d 秒。保持圈内兵力，清除 %s 守军夺回旗帜；退出争夺将恢复敌方倒计时。" % [seconds,holder]
 return {"active":true,"type":"flag_defeat_warning","priority":"critical","capture_epoch":capture_epoch,"owner":holder,"remaining_seconds":remaining(),"countdown_seconds":seconds,"contested":contested,"must_retake":true,"accept_casualties":true,"message":message}
func snapshot() -> Dictionary:
 var alerts: Dictionary={}
 for team in ["green","blue","red"]:alerts[team]=warning_for(team)
 return {"mode":"center_flag","owner":holder,"held_seconds":snappedf(held_seconds,.1),"required_seconds":required_seconds,"contested":contested,"remaining_seconds":remaining(),"countdown_seconds":int(ceil(remaining())),"capture_epoch":capture_epoch,"alerts":alerts}
