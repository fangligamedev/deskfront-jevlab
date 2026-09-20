"""TypeSafe System One adapter: typed selection of concrete legal game commands."""
import copy
import json
import math
import urllib.request
import urllib.error
from lm_controller import ProviderError, NoRedirect

RULES = '''You command ONE plastic toy soldier or tank in a simulated desktop RTS, not a real conflict.
If mission.eastfront exists, each flag is a sector checkpoint: capture it then advance east (+X), resupply between sectors. Survival matters; there is no enemy sudden-death countdown in this mode. Otherwise win by holding the central flag continuously. Stay alive using cover, friendly support and safe advances.
All positions are [x,z] metres, +x right, +z down. Select ONE concrete candidate command for self.
The engine executes movement, cover, raycast weapons, reloads, melee and urgent self-preservation.
Attack targets must be alive and hostile; rifles/SMGs cannot damage tanks. Rockets/cannon are anti-armor.
When out of range, capture/flank advances toward combat. Do not repeatedly hold/wait if safe progress is possible.
Use mission.advance_unit_id for leapfrog support: the designated mover advances while teammates cover.
If a flag_warning is active, contest the flag before the enemy wins; abandon a remote firing post if necessary.
Wait preserves an already useful movement, towing, garrison or firing task; it does not mean abandoning the battle.
Injured/suppressed soldiers should seek cover or retreat, then rejoin. Tanks stay at support range and reverse from close rockets.
Only blue can use its building. A non-rocket soldier facing armor can man a friendly available anti-tank gun.
Candidate descriptions are command semantics, not evidence that a route is safe or a target visible. Use the observed state.'''


def candidates(obs):
    u=obs['self'];allowed=set(u.get('available_actions',[]));tank=u.get('kind')=='tank';result={}
    def add(key,action,intent,description,**fields):
        if action!='wait' and action not in allowed:return
        result[key]={'command':dict(action=action,intent=intent,**fields),'description':description}
    add('continue_task','wait','observe','Continue an already useful task (moving, firing, towing, garrison). Avoid indefinite idle.')
    if tank and not u.get('combat_ready',True):return result
    add('capture_flag','capture','capture','Advance along navigable routes to contest/capture the flag; hold it when inside.')
    add('seek_cover','cover','survive','Find directionally protective cover; tank repositions to a safer supporting firing spot.')
    add('flank','flank','flank','Advance through a flank rather than staying static behind rear cover.')
    add('retreat','retreat','withdraw','Withdraw toward friendly deployment; appropriate for severe damage or untenable exposure.')
    add('hold_fire_position','hold','support','Hold a useful firing/flag defense position; auto-engage enemies with legal shots.')
    enemies=sorted(obs.get('enemies',[]),key=lambda e:math.dist(u['position'],e['position']))
    for e in enemies[:6]:
        distance=math.dist(u['position'],e['position'])
        if e.get('kind')!='tank' or u.get('weapon') in ('rocket','cannon'):
            if distance<=u.get('weapon_range',2.0):add('attack_'+e['id'],'attack','engage','Engage '+e['id']+' at '+str(round(distance,2))+'m; engine still checks actual firing line.',target_id=e['id'])
        if not tank and e.get('kind')!='tank' and distance<=.65:
            add('grenade_'+e['id'],'grenade','engage','Throw one available grenade at '+e['id']+' within 0.65m.',target_id=e['id'])
    if not tank:
        for g in obs.get('at_guns',[]):
            if g['faction']==u['faction'] and g.get('phase') not in ('destroyed',) and not g.get('operator_id'):
                add('man_'+g['id'],'man_at_gun','support','Approach and operate the friendly anti-tank gun '+g['id']+'.',gun_id=g['id'])
        add('leave_gun','leave_gun','withdraw','Abandon the gun to escape danger or contest the flag.')
        if u['faction']=='blue':
            for floor in [1,2]:add('garrison_'+str(floor),'garrison','support','Move via stairs to floor '+str(floor)+' of the friendly building for fire support.',floor=floor)
        add('leave_building','leave_building','advance','Exit building via real stairs to join the flag fight or escape collapse.')
    # Bound short movement suggestions; Godot remains responsible for collision and pathing.
    objective=obs['objective']['position'];distance=math.dist(u['position'],objective)
    if distance>.1:
        p=[u['position'][i]+(objective[i]-u['position'][i])*min(1,.22/distance) for i in range(2)]
        b=obs['bounds']
        if b[0]<=p[0]<=b[2] and b[1]<=p[1]<=b[3]:add('advance_step','move','advance','Advance a short 0.22m step toward the objective while the engine handles obstacles.',position=p)
    return result


def checked_choice(answer,options):
    if not isinstance(answer,dict) or answer.get('type')!='choice' or answer.get('choice') not in options:raise ProviderError('invalid_jev_choice')
    probs=answer.get('probabilities');confidence=answer.get('confidence')
    valid=lambda v:type(v) in (int,float) and math.isfinite(v) and 0<=v<=1
    if not valid(confidence) or not isinstance(probs,dict) or set(probs)!=set(options) or not all(valid(v) for v in probs.values()) or abs(sum(probs.values())-1)>.02:raise ProviderError('invalid_jev_probabilities')
    # Observed replies expose rounded probabilities that can differ from choice.
    # Preserve the provider's explicit legal choice, never silently recompute it.
    return answer['choice']


class JevClient:
    def __init__(self,config):
        if config['base_url']!='https://api.typesafe.ai/v1':raise ValueError('unsupported_typesafe_endpoint')
        self.config=config

    def build_payload(self,obs):
        options=candidates(obs)
        questions={'tactic':{'type':'choice','instructions':RULES,'criteria':{k:v['description'] for k,v in options.items()}},'danger':{'type':'noul','instructions':'Based on self HP, suppression, exposure and enemy weapons/range, is this unit in immediate danger requiring protection?'}}
        if obs['self'].get('kind')!='tank':
            questions['posture']={'type':'choice','instructions':'Choose the most appropriate body posture for self now. Auto lets the engine run while moving and crouch/prone for cover or incoming fire. Never crawl long safe transfers. Prone when exposed under fire.','criteria':{'auto':'Let the engine adapt posture and speed to the task.','prone':'Lie down to fire or crawl under immediate enemy fire.','crouch':'Crouch for nearby cover and low movement.','stand':'Stand and run through a safe movement window.'}}
        return {'model':self.config['model'],'state':dict(obs,command_candidates={k:v['command'] for k,v in options.items()}),'questions':questions}

    def __call__(self,obs,trace=None):
        payload=self.build_payload(obs);cfg=self.config
        req=urllib.request.Request(cfg['base_url']+'/systemone',data=json.dumps(payload).encode(),headers={'Authorization':'Bearer '+cfg['key'],'Content-Type':'application/json'})
        try:
            with urllib.request.build_opener(NoRedirect()).open(req,timeout=cfg['timeout']) as response:
                raw=response.read(131073)
                if trace:trace(http_status=response.status,response_text=raw[:131072].decode('utf-8',errors='replace'),response_truncated=len(raw)>131072)
            if len(raw)>131072:raise ProviderError('response_too_large')
            data=json.loads(raw);answers=data['answers'];opts=payload['state']['command_candidates']
            selected=checked_choice(answers['tactic'],opts);decision=copy.deepcopy(opts[selected])
            danger=answers['danger'].get('noul')
            if answers['danger'].get('type')!='noul' or type(danger) not in (int,float) or not math.isfinite(danger) or not 0<=danger<=1:raise ProviderError('invalid_jev_danger')
            if 'posture' in payload['questions']:
                posture=checked_choice(answers['posture'],payload['questions']['posture']['criteria'])
                if decision['action']!='wait':decision['posture']=posture
            confidence=answers['tactic']['confidence']
            decision['reason']='JEV 选择 '+selected+'；置信度 '+str(round(confidence*100))+'%；危险概率 '+str(round(danger*100))+'%'
            evaluation={'model':data.get('model',cfg['model']),'selected':selected,'confidence':confidence,'probabilities':answers['tactic']['probabilities'],'danger':danger,'posture':answers.get('posture'),'candidates':opts}
            usage=data.get('usage',{});inp=int(usage.get('input_tokens',0));out=int(usage.get('output_tokens',0))
            if trace:trace(provider_response=data,jev_evaluation=evaluation,resolved_model=evaluation['model'])
            return decision,{'prompt_tokens':inp,'completion_tokens':out,'total_tokens':inp+out,'jev_evaluation':evaluation}
        except urllib.error.HTTPError as e:
            if trace:trace(http_status=e.code,response_text=e.read(131072).decode('utf-8',errors='replace'))
            raise ProviderError('typesafe_http_'+str(e.code)) from None
        except (urllib.error.URLError,TimeoutError,OSError):raise ProviderError('typesafe_network_or_timeout') from None
        except (ValueError,KeyError,IndexError,TypeError,AttributeError):raise ProviderError('invalid_typesafe_response') from None
