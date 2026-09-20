"""Local Laya System One adapter. No cloud credentials, no redirects or silent truncation."""
import copy
import json
import math
import threading
import urllib.request
import urllib.error
import urllib.parse
from lm_controller import ProviderError, NoRedirect
from jev_client import candidates, checked_choice


def endpoint(config):
    base=config.get('base_url','http://127.0.0.1:9400').rstrip('/')
    url=urllib.parse.urlsplit(base)
    if url.scheme!='http' or url.hostname not in ('127.0.0.1','localhost') or url.username or url.password or url.path or url.query or url.fragment:
        raise ValueError('laya_requires_local_endpoint')
    return base


_inference_lock=threading.Lock()

def complete(config,payload,trace=None):
    # Serialize this game's director and units against the shared single-worker service.
    if not _inference_lock.acquire(timeout=1):raise ProviderError("laya_local_busy")
    try:return _complete(config,payload,trace)
    finally:_inference_lock.release()

def _complete(config,payload,trace=None):
    # Laya rejects the JEV-only model field. Keep an exact, auditable wire payload.
    payload={k:v for k,v in payload.items() if k in ('state','questions')}
    payload['allow_truncation']=False
    if trace:trace(request=payload)
    req=urllib.request.Request(endpoint(config)+'/v1/systemone',data=json.dumps(payload,ensure_ascii=False).encode(),headers={'Content-Type':'application/json'})
    try:
        with urllib.request.build_opener(urllib.request.ProxyHandler({}),NoRedirect()).open(req,timeout=min(5,config.get('timeout',3))) as response:
            raw=response.read(131073)
            if trace:trace(http_status=response.status,response_text=raw[:131072].decode(errors='replace'))
        if len(raw)>131072:raise ProviderError('response_too_large')
        result=json.loads(raw)
        if not isinstance(result,dict) or not isinstance(result.get('answers'),dict):raise ProviderError('invalid_laya_response')
        if result.get('meta',{}).get('warnings'):raise ProviderError('laya_input_truncated')
        if trace:trace(provider_response=result,resolved_model=result.get('model','laya-multilingual'))
        return result
    except urllib.error.HTTPError as e:
        if trace:trace(http_status=e.code,response_text=e.read(131072).decode(errors='replace'))
        raise ProviderError('laya_http_'+str(e.code)) from None
    except (urllib.error.URLError,TimeoutError,OSError):raise ProviderError('laya_network_or_timeout') from None
    except (ValueError,TypeError):raise ProviderError('invalid_laya_response') from None


def rounded(value):
    if isinstance(value,float):return round(value,3)
    if isinstance(value,dict):return {k:rounded(v) for k,v in value.items()}
    if isinstance(value,list):return [rounded(v) for v in value]
    return value

def frontier_payload(context,questions):
    """Project only fields used by the bounded choices; never truncate server input."""
    units=context.get('units',context.get('squad',[]))
    rows=[{k:u[k] for k in ('id','faction','hp','position','suppression','weapon') if k in u} for u in units[:9]]
    state={'game':'Toy RTS. East is +x. Survive and advance. Workers build upcoming cover.',
           'sector':context.get('sector',context.get('frontier',{}).get('index')),'units':rows,
           'recent':[c.get('template') for c in context.get('recent_sectors',[])][-3:],
           'construction':[{'index':c['index'],'progress':c.get('construction',{}).get('progress',0)} for c in context.get('construction',[])],
           'strategy':context.get('strategy',{}).get('sectors',[])}
    return {'allow_truncation':False,'state':rounded(state),'questions':questions}


class LayaClient:
    def __init__(self,config):endpoint(config);self.config=config
    def options(self,obs):return candidates(obs)
    def build_payload(self,obs):
        u=obs['self'];opts=self.options(obs)
        state={'game':'Toy RTS; x east, z south. Capture flag, survive. Engine handles paths, shots and cover.',
               'self':{k:u[k] for k in ('id','faction','kind','hp','max_hp','position','weapon','weapon_range','suppression','action','order_mode','combat_ready','in_cover','ammo','locomotion') if k in u},
               'objective':obs['objective']['position'],'flag_warning':obs.get('flag_warning',{}),
               'eastfront':bool(obs.get('mission',{}).get('eastfront')),
               'enemies':[{k:e[k] for k in ('id','kind','hp','position','weapon') if k in e} for e in sorted(obs.get('enemies',[]),key=lambda e:math.dist(u['position'],e['position']))[:3]],
               'moving':u.get('combat',{}).get('path_active'),
               'shootable':u.get('combat',{}).get('engageable_targets',[])[:3],
               'threats':u.get('combat',{}).get('incoming_threats',[])[:3],
               'idle_seconds':obs.get('progress',{}).get('idle_seconds'),
               'allies':[{k:a[k] for k in ('id','hp','position','weapon') if k in a} for a in obs.get('allies',[])[:2]]}
        questions={'danger':{'type':'noul','instructions':'Is this unit in immediate danger, considering HP, enemies and range?'}}
        if len(opts)>1:
            questions['tactic']={'type':'choice','instructions':'Choose safe progress toward flag; fight within range, cover under fire, retreat if badly hurt. Keep useful tasks. Do not idle when safe. Rifles cannot hurt tanks.',
                'criteria':{k:v['command']['action']+' '+str(v['command'].get('target_id',v['command'].get('gun_id',''))) for k,v in opts.items()}}
        if u.get('kind')!='tank':questions['posture']={'type':'choice','instructions':'Auto for safe travel; crouch behind cover, prone under exposed fire. Avoid crawling safe transfers.','criteria':{'auto':'Adapt to task','prone':'Lie down','crouch':'Crouch','stand':'Stand'}}
        return {'state':rounded(state),'questions':questions,'allow_truncation':False}
    def __call__(self,obs,trace=None):
        payload=self.build_payload(obs);data=complete(self.config,payload,trace);answers=data['answers'];opts=self.options(obs)
        try:
            selected=checked_choice(answers['tactic'],opts) if 'tactic' in payload['questions'] else next(iter(opts))
            decision=copy.deepcopy(opts[selected]['command']);danger=answers['danger'].get('noul')
            if answers['danger'].get('type')!='noul' or type(danger) not in (int,float) or not math.isfinite(danger) or not 0<=danger<=1:raise ProviderError('invalid_laya_danger')
            if 'posture' in payload['questions']:
                posture=checked_choice(answers['posture'],payload['questions']['posture']['criteria'])
                if decision['action']!='wait':decision['posture']=posture
            decision['reason']='Laya 本地选择 '+selected+'；危险概率 '+str(round(danger*100))+'%'
            evaluation={'provider':'laya','selected':selected,'danger':danger,'probabilities':answers.get('tactic',{}).get('probabilities',{}),'confidence':answers.get('tactic',{}).get('confidence'),'meta':data.get('meta',{})}
            if trace:trace(laya_evaluation=evaluation)
            # Encoder inference reports its own usage; do not invent generated-token counts.
            usage=data.get('usage',{});inp=int(usage.get('input_tokens',0));out=int(usage.get('output_tokens',0))
            return decision,dict(usage,prompt_tokens=inp,completion_tokens=out,total_tokens=inp+out,laya_evaluation=evaluation)
        except (KeyError,TypeError,AttributeError):raise ProviderError('invalid_laya_response') from None
