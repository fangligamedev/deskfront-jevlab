extends SceneTree
var checks: Array=[]
func _initialize():call_deferred("run")
func check(ok: bool, name: String):
 checks.append({"test":name,"passed":ok})
 if not ok:push_error(name)
func run():
 var f=load("res://scripts/flag_objective.gd").new()
 f.advance(['red'],.016)
 var s: Dictionary=f.snapshot()
 check(s.countdown_seconds==30,'claim starts a 30 second countdown')
 check(s.alerts.green.active and s.alerts.blue.active and not s.alerts.red.active,'both enemy factions warned, holder not threatened')
 check(s.alerts.green.message.contains('战败') and s.alerts.green.accept_casualties,'explicit loss and casualty priority')
 var epoch: int=f.capture_epoch;var remaining: float=f.remaining()
 f.advance(['red','green'],5)
 check(f.remaining()==remaining and f.contested,'contesting pauses countdown rather than running down')
 check(f.warning_for('green').message.contains('暂停'),'contested warning explains paused clock')
 f.advance(['red'],29.97)
 check(f.snapshot().countdown_seconds==1,'never displays zero before victory')
 check(f.advance(['red'],.014)=='red' and f.snapshot().countdown_seconds==0,'zero coincides with actual victory')
 f.advance(['blue'],.016)
 check(f.capture_epoch>epoch and f.snapshot().countdown_seconds==30,'new holder starts fresh epoch and 30 seconds')
 f.advance([],1);check(not f.warning_for('green').active and f.held_seconds==0,'empty flag clears countdown and warnings');f.free()
 var g=load('res://scenes/main.tscn').instantiate();root.add_child(g);g.set_physics_process(false);g.paused=true;g.fx.set_muted(true)
 g.command({'action':'control','faction':'green','mode':'lm'})
 var u=g.units[0];u.hp=10;u.safety_until=g.elapsed+3;u.safety_reason='low_health'
 var cmd={'action':'capture','source':'lm','faction':'green','unit_ids':[u.id],'run_id':g.run_id,'seen_tick':g.tick_id,'control_epoch':g.control_epochs.green,'intent':'capture'}
 check(g.command(cmd).message=='survival_override','normal safety policy remains without flag emergency')
 g.flag_objective.advance(['red'],.016);cmd.flag_epoch=g.flag_objective.capture_epoch
 check(g.command(cmd).accepted,'low health LM counterattack is accepted during flag emergency')
 u.survival_tick();check(u.safety_until==0 and u.safety_reason=='','automatic retreat does not overwrite emergency LM order')
 cmd.flag_epoch=0;check(g.command(cmd).message=='flag_state_changed','queued orders from pre-capture observation are rejected')
 cmd.flag_epoch=g.flag_objective.capture_epoch;cmd.unit_ids=['red-1']
 check(not g.command(cmd).accepted,'emergency does not bypass unit authority')
 var before: float=g.flag_objective.remaining();g._physics_process(10)
 check(g.flag_objective.remaining()==before,'game pause stops flag countdown')
 g.update_hud();check(g.flag_warning_panel.visible and g.flag_warning_label.text.contains('00:30'),'native HUD visibly renders 30 second warning')
 g.flag_objective.advance(['green'],.01);check(not g.flag_emergency('green'),'retaking cancels own emergency')
 var result={"passed":checks.all(func(c):return c.passed),"checks":checks}
 FileAccess.open('res://docs/evidence/flag-warning/engine.json',FileAccess.WRITE).store_string(JSON.stringify(result,'  '))
 print('FLAG_WARNING_CONTRACT ',JSON.stringify(result));quit(0 if result.passed else 1)
