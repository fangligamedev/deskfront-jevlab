"""Slow strategic plans + fast typed JEV intentions; Godot owns continuous execution."""
import concurrent.futures
import copy
import json
import time
import urllib.request
import urllib.error
from lm_controller import ArkClient, NoRedirect, ProviderError, configured
from jev_client import checked_choice

INTENTS={'advance':'沿安全通路持续推进，接敌交替掩护','flank_north':'从北侧寻找安全侧翼','flank_south':'从南侧寻找安全侧翼','regroup':'受损队员隐蔽重整，健康队员支援'}
CONSTRUCTION={'balanced':'两名工兵均衡施工','north_first':'优先完成北侧工事','south_first':'优先完成南侧工事','dig_first':'两名工兵先挖通所有沟槽，再搬沙包','sandbag_first':'优先给已挖好的工位搬运堆砌沙包'}

DEFENDERS={'entrench':'守军进入慢脑分配的战壕掩体；先隐蔽再射击','crossfire':'各占不同掩体建立交叉火力，禁止集体冲锋','fallback':'守军转移后排存活掩体，重整火力'}
ARMOR={'hold':'计划尚未到时或通路受阻，坦克继续可见待命','deploy_green':'按慢脑计划部署绿色坦克','deploy_red':'按慢脑计划部署红色坦克','deploy_both':'双方计划已到时，部署双方坦克'}

def validate_plan(value,allowed):
    from frontier_plan import campaign_plan
    try:return campaign_plan(value,allowed)
    except ValueError as e:raise ProviderError(str(e)) from None

class DualBrain:
    def __init__(self,state,lm):
        self.state=state;self.lm=lm;self.pool=concurrent.futures.ThreadPoolExecutor(max_workers=2,thread_name_prefix='eastfront-brain')
        self.pending={};self.receipts={};self.plan_receipts={};self.plan_call=None;self.plan_calls={};self.run='';self.plan={};self.submitted=set();self.next_fast=0;self.used={'slow':0,'fast':0};self.disabled=set();self.latest={};self.next_slow=0
    def planning_request(self,front,request):
        """Prepare the next batch while at least one fully planned battle remains."""
        if request and request['index'] not in self.plan:return request
        future=[i for i in self.plan if i>=front['active_sector']]
        catalog=front.get('template_catalog',request.get('candidates',[]))
        if not future or len(future)>2 or not catalog:return None
        return {'index':max(future)+1,'candidates':catalog,'prefetch':True,'seed':front.get('seed',19)}
    def close(self):self.pool.shutdown(wait=False,cancel_futures=True)
    def invoke(self,kind,payload,cfg,call):
        log=self.lm.call_log;trace=lambda **d:log.update(call,**d);started=time.monotonic()
        try:
            if kind=='slow':
                value,usage=ArkClient(dict(cfg,timeout=30)).complete(payload,trace)
            elif cfg['provider']=='laya':
                from laya_client import complete
                value=complete(cfg,payload,trace);usage=value.get('usage',{})
            else:
                req=urllib.request.Request('https://api.typesafe.ai/v1/systemone',data=json.dumps(payload).encode(),headers={'Authorization':'Bearer '+cfg['key'],'Content-Type':'application/json'})
                with urllib.request.build_opener(NoRedirect()).open(req,timeout=min(5,cfg['timeout'])) as response:raw=response.read(131073)
                trace(http_status=response.status,response_text=raw[:131072].decode(errors='replace'))
                if len(raw)>131072:raise ProviderError('response_too_large')
                value=json.loads(raw);usage=value.get('usage',{})
            trace(phase='returned',parsed_response=value,usage=usage,latency_ms=round((time.monotonic()-started)*1000));return value
        except urllib.error.HTTPError as e:
            trace(phase='error',http_status=e.code,response_text=e.read(131072).decode(errors='replace'),error='provider_http_'+str(e.code));raise ProviderError('provider_http_'+str(e.code)) from None
        except (TimeoutError,OSError,urllib.error.URLError):
            trace(phase='error',error='provider_network_or_timeout',latency_ms=round((time.monotonic()-started)*1000));raise ProviderError('provider_network_or_timeout') from None
        except Exception as e:
            trace(phase='error',error=str(e) if isinstance(e,ProviderError) else 'brain_request_failed');raise ProviderError(str(e) if isinstance(e,ProviderError) else 'brain_request_failed') from None
    def launch(self,kind,s,payload,cfg,key):
        if kind in self.pending or kind in self.disabled or self.used[kind]>=(64 if kind=='slow' else 300):return
        if not configured(cfg):self.latest[kind]={'error':'provider_not_configured'};return
        call=self.lm.call_log.start(unit_id='eastfront-'+kind+'-brain',faction='studio',run_id=s['run_id'],tick=s['tick'],model=cfg['model'],provider=cfg['provider'],request=payload)
        self.pending[kind]={'future':self.pool.submit(self.invoke,kind,payload,cfg,call),'run':s['run_id'],'key':key,'call':call,'started':time.monotonic(),'provider':cfg['provider']};self.used[kind]+=1
    def tick(self,s,instance,acks):
        now=time.monotonic();f=s.get('eastfront',{});r=f.get('request',{})
        if self.run!=s['run_id']:
            self.run=s['run_id'];self.plan={};self.plan_receipts={};self.plan_call=None;self.plan_calls={};self.submitted=set();self.next_fast=0;self.used={'slow':0,'fast':0};self.disabled=set();self.latest={};self.next_slow=0
        for cid,call in list(self.receipts.items()):
            if cid in acks:
                self.lm.call_log.update(call,phase='executed' if acks[cid]['accepted'] else 'rejected',receipt=acks[cid]);del self.receipts[cid]
        for cid,row in list(self.plan_receipts.items()):
            if cid not in acks:continue
            receipt=acks[cid];del self.plan_receipts[cid]
            history=(self.lm.call_log.get(row['call']) or {}).get('sector_receipts',[])
            history=[h for h in history if h['sector']!=row['index']]+[{'sector':row['index'],'receipt':receipt}]
            self.lm.call_log.update(row['call'],phase='executed' if receipt['accepted'] else 'rejected',receipt=receipt,sector_receipts=history[-3:])
            if not receipt['accepted']:
                self.submitted.discard(row['sequence']);self.plan.pop(row['index'],None);self.next_slow=now+3
                self.latest['slow_error']={'error':receipt.get('reason',receipt.get('error','engine_rejected_plan'))}
        enabled=f.get('backend') in ('dual_brain','dual_brain_laya') and not s.get('paused') and not s.get('winner')
        for kind,task in list(self.pending.items()):
            if not task['future'].done():continue
            del self.pending[kind];call=task['call']
            if not enabled or task['run']!=s['run_id']:
                self.lm.call_log.update(call,phase='discarded',discard_reason='run_or_control_changed');continue
            try:
                value=task['future'].result()
                if kind=='slow':
                    from frontier_plan import fit_campaign_layouts, validate_long_defense
                    try:fitted,adjustments=fit_campaign_layouts(value)
                    except ValueError as e:raise ProviderError(str(e)) from None
                    self.lm.call_log.update(call,layout_adjustments=adjustments)
                    plan=validate_plan(fitted,task['key']['allowed']);start=task['key']['index']
                    if task['key'].get('compose'):
                        if not all('layout' in p for p in plan['sectors']):raise ProviderError('layout_required')
                        kinds={c['kind'] for p in plan['sectors'] for c in p['layout']['components']}
                        if len(kinds)<4 or not kinds.intersection({'house','bunker','fuel_depot'}):raise ProviderError('insufficient_terrain_variety')
                        try:validate_long_defense(plan)
                        except ValueError as e:raise ProviderError(str(e)) from None
                    self.latest.pop('slow_error',None);self.plan_call=call;self.plan.update({start+i:t for i,t in enumerate(plan['sectors'])});self.plan_calls.update({start+i:call for i in range(3)});self.latest[kind]=dict(plan,start_index=start,layout_adjustments=adjustments)
                    self.lm.call_log.update(call,phase='planned',decision=self.latest[kind])
                else:
                    if task['key']!=f['active_sector'] or now-task['started']>6:raise ProviderError('stale_fast_directive')
                    intent=checked_choice(value['answers']['intent'],INTENTS);policy=checked_choice(value['answers']['construction'],CONSTRUCTION)
                    command={'action':'eastfront_directive','sector':f['active_sector'],'intent':intent,'construction':policy,'defense':checked_choice(value['answers']['defense'],DEFENDERS),'armor':checked_choice(value['answers']['armor'],ARMOR),'provider':task.get('provider','typesafe_jev')+'_fast'}
                    code,receipt=self.state.submit(dict(command,instance_id=instance,run_id=s['run_id']))
                    self.latest[kind]=dict(command,accepted_for_queue=code==202)
                    self.lm.call_log.update(call,phase='submitted' if code==202 else 'rejected',decision=command,receipt=receipt)
                    if code==202:self.receipts[receipt['id']]=call
            except (ProviderError,KeyError,TypeError,ValueError) as e:
                code=str(e) if isinstance(e,ProviderError) else 'invalid_brain_response';self.latest[kind]={'error':code};self.lm.call_log.update(call,phase='discarded' if code=='stale_fast_directive' else 'error',error=code)
                if code in ('provider_http_401','provider_http_402','provider_http_403','provider_account_overdue'):self.disabled.add(kind)
                if kind=='slow':self.next_slow=now+5
                elif code in ('laya_http_429','laya_local_busy','laya_network_or_timeout','provider_http_429','provider_network_or_timeout'):self.next_fast=now+4
        if enabled:
            self.plan={i:p for i,p in self.plan.items() if i>=f['active_sector']-1}
            self.plan_calls={i:c for i,c in self.plan_calls.items() if i in self.plan}
            if r and r['index'] in self.plan and r['sequence'] not in self.submitted:
                code,receipt=self.state.submit({'action':'eastfront_propose','sequence':r['sequence'],'template':self.plan[r['index']]['template'],'battle_plan':self.plan[r['index']],'provider':'deepseek_slow_plan','instance_id':instance,'run_id':s['run_id']})
                if code==202:
                    self.submitted.add(r['sequence']);self.plan_receipts[receipt['id']]={'call':self.plan_calls.get(r['index'],self.plan_call),'sequence':r['sequence'],'index':r['index']}
                else:self.latest['slow_error']={'error':receipt.get('error','plan_queue_rejected')}
            planning=self.planning_request(f,r)
            if planning and now>=getattr(self,'next_slow',0):
                cfg=self.lm.profiles.get('volcengine_ark',{});allowed=[x['id'] for x in planning['candidates']]
                recent={c['index']:{k:c.get(k) for k in ('index','template','phase')} for c in f['chunks']}
                recent.update({i:{'index':i,'template':p['template'],'phase':'planned'} for i,p in self.plan.items() if i<planning['index'] and i not in recent})
                context={'component_catalog':f.get('component_catalog',{}),'dimensions':f.get('dimensions',{}),'frontier':planning,'recent':[recent[i] for i in sorted(recent)][-3:],'previous_validation_error':self.latest.get('slow_error',{}).get('error',self.latest.get('slow',{}).get('error','')),'wave':f.get('wave',1),'squad':[{'hp':u['hp'],'weapon':u['weapon']} for u in s['units'] if u['faction']=='green' and u['hp']>0]}
                prompt='你是玩具兵无尽东线的慢脑战役规划师。输出未来三段可执行方案，不只是模板名字。只有绿色远征队与红色守军，没有蓝方。每段选模板、2至3名守军weapon只能为rifle/smg/rocket（禁止cannon等未实现武器），分配不同的整数掩体station(0/1/2)、defense(entrench/crossfire/fallback)、construction(balanced/north_first/south_first/dig_first/sandbag_first)、双方坦克是否出场/开战后延迟0至20游戏秒/战术role(support/push)。armor的green和red无论enabled是true或false都必须完整提供enabled/delay/role三个键，禁用时填delay:0,role:support。第一段必须安排双方坦克。任意一段只要green.enabled=true，该段红方defenders必须至少一名rocket反制。previous_validation_error若非空，纠正该错误后重新给出完整三段。红军应据壕防守，不要在开阔地待机。三段模板不得重复，第一段不可重复recent末段。Godot拥有塑料骨骼士兵与坦克。你必须自由组合component_catalog，不要只选旧模板的三个沙包。每段额外提供layout:{theme,objective_z,components:[{kind,x,z,width,depth},...]}。组件6至12个，按前沿、纵深、后方三道阵地布置；每段至少3个安全掩体house/bunker/wall/ruins/rock/trench/sandbag；station 0/1/2对应过滤掉mud/road/water/fuel_depot后的前三个安全掩体，其余可自由组合。kind只能是catalog中的键。整个三段至少4种组件，必须有house/bunker/fuel_depot中的建筑，布局、侧翼、主题应不同。房屋是可破坏外围掩体，不支持进入二楼。沙包、浅壕可被坦克碾压；坚固建筑必须绕行或炮击；燃料站被摧毁会爆炸。mud减速，road加速，water不可通行。theme从meadow/dust/ruins/trench/supply/ridge/village/industrial/forest选。坐标是段内局部坐标，单位米。当前每段东西长4.35米（原来的3倍）、南北宽2.8米。x 0.25至4.15、z约-1.2至1.2；width与depth范围0.04至1.8；x±width/2必须在[0.12,4.25]，abs(z)+depth/2<=1.32。必须先列出前三个安全工位：例如 components 开头 [{kind:trench,x:0.8,z:-0.5,width:0.08,depth:0.9},{kind:bunker,x:2.1,z:0.5,width:0.4,depth:0.4},{kind:ruins,x:3.5,z:-0.5,width:0.5,depth:0.4}]（示意，输出须为合法JSON，可变化类型与z）。前三个安全工位分别安排在x约0.8、2.1、3.5，形成三道纵深防线，不可挤在开头1米。至少安排一段长度0.65至1.5米的连续战壕/沙包/墙，保留缺口、拐角和侧翼通路；房屋、士兵、坦克保持原有模型比例，不把单个沙包或人放大。各组件矩形间留至少0.04间隙，留出坦克宽0.24的贯通通路。目标在x=4.13,z=objective_z(-0.9至0.9)，周围0.13不可放组件。不要把大建筑放在目标或守军后方的东端通道上。充分利用扩宽后的上下侧翼，避免所有组件挤在中间。严格返回JSON：{"strategy":"简短总体战术","sectors":[{"template":"候选ID","defenders":[{"weapon":"rifle","station":0},{"weapon":"rocket","station":2}],"defense":"entrench","construction":"dig_first","armor":{"green":{"enabled":true,"delay":2,"role":"support"},"red":{"enabled":true,"delay":4,"role":"support"}},"reason":"该段战术目的"},另外两段同结构]}。'
                payload={'model':cfg.get('model',''),'messages':[{'role':'system','content':prompt},{'role':'user','content':json.dumps(context,ensure_ascii=False)}],'max_tokens':4800,'thinking':{'type':'disabled'},'response_format':{'type':'json_object'}}
                self.launch('slow',s,payload,cfg,{'index':planning['index'],'allowed':allowed,'compose':bool(f.get('component_catalog'))})
            if now>=self.next_fast:
                self.next_fast=now+2
                cfg=self.lm.profiles.get('laya' if f.get('backend')=='dual_brain_laya' else 'typesafe_jev',{})
                context={'sector':f['active_sector'],'construction':[{'index':c['index'],'construction':c.get('construction',{}),'plan':c.get('battle_plan',{})} for c in f['chunks'] if c['phase']=='building'],'strategy':self.latest.get('slow',{}),'units':[{k:u.get(k) for k in ('id','faction','hp','position','suppression','weapon','order_mode')} for u in s['units'] if u['hp']>0 and u.get('deployment_phase','active')=='active'],'control':s.get('control',{}),'active_plan':next((c.get('battle_plan',{}) for c in f['chunks'] if c['index']==f['active_sector']),{}),'armor':f.get('armor',[]),'defense':f.get('defense','entrench')}
                payload={'model':cfg.get('model',''),'state':context,'questions':{'intent':{'type':'choice','instructions':'决定绿色小队下一段持续战术意图：空旷安全时连续前进，接敌寻侧翼、保命并掩护；不要所有人原地等待。游戏AI连续执行，玩家控制时不干预。','criteria':INTENTS},'construction':{'type':'choice','instructions':'选择接下来工兵施工优先侧；已开始任务不重置，游戏引擎连续执行挖掘搬运堆砌。','criteria':CONSTRUCTION}}}
                payload['questions']['defense']={'type':'choice','instructions':'执行慢脑守军站位方案。常态据壕防守，遭重压才撤向后排，不冲出掩体。','criteria':DEFENDERS}
                payload['questions']['armor']={'type':'choice','instructions':'执行慢脑坦克计划。armor 中 ready=true 表示已到部署时机且通路可用，此时派上场；双方均就绪选择 deploy_both。未就绪继续待命。','criteria':ARMOR}
                if cfg.get('provider')=='laya':
                    from laya_client import frontier_payload
                    payload=frontier_payload(context,payload['questions'])
                self.launch('fast',s,payload,cfg,f['active_sector'])
        self.lm.frontier_status={'mode':f.get('backend','dual_brain'),'fast_provider':'laya' if f.get('backend')=='dual_brain_laya' else 'typesafe_jev','used':dict(self.used),'in_flight':list(self.pending),'latest':copy.deepcopy(self.latest),'disabled':sorted(self.disabled),'budgets':{'slow':64,'fast':300},'fast_interval_seconds':2,'planned_sectors':sorted(self.plan),'planning_ahead':bool(self.pending.get('slow') and self.pending['slow']['key']['index']>f.get('active_sector',0))}
