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

def validate_plan(value,allowed):
    rows=value.get('sectors') if isinstance(value,dict) else None
    if not isinstance(rows,list) or len(rows)!=3 or any(not isinstance(x,str) or x not in allowed for x in rows) or len(set(rows))!=3:raise ProviderError('invalid_campaign_plan')
    return {'sectors':rows,'strategy':str(value.get('strategy',''))[:160]}

class DualBrain:
    def __init__(self,state,lm):
        self.state=state;self.lm=lm;self.pool=concurrent.futures.ThreadPoolExecutor(max_workers=2,thread_name_prefix='eastfront-brain')
        self.pending={};self.receipts={};self.run='';self.plan={};self.submitted=set();self.next_fast=0;self.used={'slow':0,'fast':0};self.disabled=set();self.latest={};self.next_slow=0
    def close(self):self.pool.shutdown(wait=False,cancel_futures=True)
    def invoke(self,kind,payload,cfg,call):
        log=self.lm.call_log;trace=lambda **d:log.update(call,**d);started=time.monotonic()
        try:
            if kind=='slow':
                value,usage=ArkClient(dict(cfg,timeout=min(8,cfg['timeout']))).complete(payload,trace)
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
            self.run=s['run_id'];self.plan={};self.submitted=set();self.next_fast=0;self.used={'slow':0,'fast':0};self.disabled=set();self.latest={};self.next_slow=0
        for cid,call in list(self.receipts.items()):
            if cid in acks:
                self.lm.call_log.update(call,phase='executed' if acks[cid]['accepted'] else 'rejected',receipt=acks[cid]);del self.receipts[cid]
        enabled=f.get('backend') in ('dual_brain','dual_brain_laya') and not s.get('paused') and not s.get('winner')
        for kind,task in list(self.pending.items()):
            if not task['future'].done():continue
            del self.pending[kind];call=task['call']
            if not enabled or task['run']!=s['run_id']:
                self.lm.call_log.update(call,phase='discarded',discard_reason='run_or_control_changed');continue
            try:
                value=task['future'].result()
                if kind=='slow':
                    plan=validate_plan(value,task['key']['allowed']);start=task['key']['index']
                    self.plan={start+i:t for i,t in enumerate(plan['sectors'])};self.latest[kind]=dict(plan,start_index=start)
                    self.lm.call_log.update(call,phase='planned',decision=self.latest[kind])
                else:
                    if task['key']!=f['active_sector'] or now-task['started']>6:raise ProviderError('stale_fast_directive')
                    intent=checked_choice(value['answers']['intent'],INTENTS);policy=checked_choice(value['answers']['construction'],CONSTRUCTION)
                    command={'action':'eastfront_directive','sector':f['active_sector'],'intent':intent,'construction':policy,'provider':task.get('provider','typesafe_jev')+'_fast'}
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
            if r and r['index'] in self.plan and r['sequence'] not in self.submitted:
                self.submitted.add(r['sequence'])
                self.state.submit({'action':'eastfront_propose','sequence':r['sequence'],'template':self.plan[r['index']],'provider':'deepseek_slow_plan','instance_id':instance,'run_id':s['run_id']})
            if r and r['index'] not in self.plan and now>=getattr(self,'next_slow',0):
                cfg=self.lm.profiles.get('volcengine_ark',{});allowed=[x['id'] for x in r['candidates']]
                context={'frontier':r,'recent':f['chunks'],'wave':f.get('wave',1),'squad':[{'hp':u['hp'],'weapon':u['weapon']} for u in s['units'] if u['faction']=='green' and u['hp']>0]}
                payload={'model':cfg.get('model',''),'messages':[{'role':'system','content':'规划玩具兵无尽东线未来三段关卡，交替布局与战术难题。当前实际组件只有平坦桌面、可破坏沙包、浅战壕外观和步枪/冲锋枪/火箭步兵；没有真实高差、装甲单位、箱体或未列出的组件，不要在策略中虚构这些能力。结合小队剩余兵种提供可反制的防线。第一段不要重复 recent 最后一段。只从 candidates 选三个不同模板。只返回 JSON {"sectors":["模板ID","模板ID","模板ID"],"strategy":"简短战局规划"}。'},{'role':'user','content':json.dumps(context,ensure_ascii=False)}],'max_tokens':240,'thinking':{'type':'disabled'},'response_format':{'type':'json_object'}}
                self.launch('slow',s,payload,cfg,{'index':r['index'],'allowed':allowed})
            if now>=self.next_fast:
                self.next_fast=now+2
                cfg=self.lm.profiles.get('laya' if f.get('backend')=='dual_brain_laya' else 'typesafe_jev',{})
                context={'sector':f['active_sector'],'construction':[c for c in f['chunks'] if c['phase']=='building'],'strategy':self.latest.get('slow',{}),'units':[{k:u.get(k) for k in ('id','faction','hp','position','suppression','weapon','order_mode')} for u in s['units'] if u['hp']>0 and u.get('deployment_phase','active')=='active'],'control':s.get('control',{})}
                payload={'model':cfg.get('model',''),'state':context,'questions':{'intent':{'type':'choice','instructions':'决定绿色小队下一段持续战术意图：空旷安全时连续前进，接敌寻侧翼、保命并掩护；不要所有人原地等待。游戏AI连续执行，玩家控制时不干预。','criteria':INTENTS},'construction':{'type':'choice','instructions':'选择接下来工兵施工优先侧；已开始任务不重置，游戏引擎连续执行挖掘搬运堆砌。','criteria':CONSTRUCTION}}}
                if cfg.get('provider')=='laya':
                    from laya_client import frontier_payload
                    payload=frontier_payload(context,payload['questions'])
                self.launch('fast',s,payload,cfg,f['active_sector'])
        self.lm.frontier_status={'mode':f.get('backend','dual_brain'),'fast_provider':'laya' if f.get('backend')=='dual_brain_laya' else 'typesafe_jev','used':dict(self.used),'in_flight':list(self.pending),'latest':copy.deepcopy(self.latest),'disabled':sorted(self.disabled),'budgets':{'slow':64,'fast':300},'fast_interval_seconds':2}
