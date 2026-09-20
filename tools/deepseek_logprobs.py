"""Original Python adapter inspired by the user's multi-question logprobs brief.
Probabilities are conditional on returned option tokens, NOT calibrated win odds.
"""
import concurrent.futures
import copy
import json
import math
import re
import urllib.request
import urllib.error
from lm_controller import ArkClient, NoRedirect, ProviderError
from jev_client import candidates, RULES


def option_distribution(data, labels):
    """Select the answer position with widest option coverage, ignoring prose tokens."""
    try:
        positions = data['choices'][0]['logprobs']['content'][:12]
    except (KeyError, TypeError, IndexError):
        raise ProviderError('logprobs_unavailable') from None
    if not isinstance(positions,list):raise ProviderError('logprobs_unavailable')
    best = {}
    for position in positions:
        if not isinstance(position,dict):continue
        found = {}
        alternatives=position.get('top_logprobs',[])
        if not isinstance(alternatives,list):alternatives=[]
        for token in alternatives + [position]:
            if not isinstance(token,dict):continue
            key = re.sub(r'[\s\"\'`]', '', str(token.get('token', '')))
            value = token.get('logprob')
            if key in labels and type(value) in (int, float) and math.isfinite(value) and value > -999:
                found[key] = max(found.get(key, -math.inf), value)
        if len(found) > len(best):best = found
    if not best:raise ProviderError('logprobs_no_option_tokens')
    top = max(best.values());weights = {k:math.exp(v-top) for k,v in best.items()};total=sum(weights.values())
    probs={k:weights.get(k,0)/total for k in labels}
    entropy=-sum(p*math.log(p) for p in probs.values() if p>0)
    return {'selected':max(probs,key=probs.get),'probabilities':probs,'coverage':len(best)/len(labels),
            'observed_labels':list(best),'confidence':1-entropy/math.log(len(labels)) if len(labels)>1 else 1,
            'meaning':'conditional_on_observed_option_tokens_not_success_probability'}


class DeepSeekLogprobsClient:
    def __init__(self, config, transport=None):
        ArkClient(config)  # Apply the same credential destination allowlist.
        self.config=config;self.transport=transport or self._post

    def build_payload(self, obs):
        opts=dict(list(candidates(obs).items())[:20])
        questions={'tactic':(RULES,{k:v['description'] for k,v in opts.items()}),
                   'danger':('Is self in immediate danger requiring protection? Evaluate HP, suppression and effective enemy fire.',{'yes':'Immediate danger','no':'No immediate danger'})}
        if obs['self'].get('kind')!='tank':
            questions['posture']=('Choose posture. Auto runs through safe transfers; prone for immediate incoming fire, never long safe crawling.',{'auto':'Engine adapts','prone':'Lie down','crouch':'Crouch','stand':'Run standing'})
        requests=[]
        for name,(instruction,options) in questions.items():
            labels={chr(65+i):key for i,key in enumerate(options)}
            text='\n'.join(label+': '+options[key] for label,key in labels.items())
            payload={'model':self.config['model'],'messages':[{'role':'system','content':instruction+'\nReturn exactly ONE option letter. No explanation.\n'+text},{'role':'user','content':json.dumps(obs,ensure_ascii=False,separators=(',',':'))}],
                     'max_tokens':8,'temperature':0,'thinking':{'type':'disabled'},'logprobs':True,'top_logprobs':20}
            requests.append({'question':name,'labels':labels,'payload':payload})
        return {'transport':'parallel_chat_completions','requests':requests,'command_candidates':{k:v['command'] for k,v in opts.items()},'max_attempts_per_question':2}

    def _post(self, payload):
        req=urllib.request.Request(self.config['base_url']+'/chat/completions',data=json.dumps(payload).encode(),headers={'Authorization':'Bearer '+self.config['key'],'Content-Type':'application/json'})
        try:
            with urllib.request.build_opener(NoRedirect()).open(req,timeout=self.config['timeout']) as r:
                raw=r.read(131073)
            if len(raw)>131072:raise ProviderError('response_too_large')
            return json.loads(raw)
        except urllib.error.HTTPError as e:
            raw=e.read(131072).decode(errors='replace')
            try:code=json.loads(raw).get('error',{}).get('code','')
            except ValueError:code=''
            error=ProviderError('provider_account_overdue' if code=='AccountOverdueError' else 'provider_http_'+str(e.code));error.response_text=raw;error.http_status=e.code
            raise error from None
        except (urllib.error.URLError,TimeoutError,OSError):raise ProviderError('provider_network_or_timeout') from None
        except (ValueError,KeyError,TypeError):raise ProviderError('invalid_provider_json') from None

    def __call__(self, obs, trace=None):
        batch=self.build_payload(obs);rows=[];answers={};usage={'prompt_tokens':0,'completion_tokens':0,'total_tokens':0,'provider_requests':0}
        def question(q):
            attempts=[]
            for i in range(2):
                try:
                    data=self.transport(q['payload']);attempts.append({'response':data})
                    d=option_distribution(data,q['labels'])
                    d['selected']=q['labels'][d['selected']];d['probabilities']={q['labels'][k]:v for k,v in d['probabilities'].items()}
                    return q['question'],d,attempts,None
                except ProviderError as error:
                    attempts.append({'error':str(error),'response_text':getattr(error,'response_text',''),'http_status':getattr(error,'http_status',None)})
                    if str(error)!='logprobs_no_option_tokens' or i==1:return q['question'],None,attempts,str(error)
            raise AssertionError('unreachable')
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
            for name,answer,attempts,error in pool.map(question,batch['requests']):
                rows.append({'question':name,'attempts':attempts,'error':error})
                if answer:answers[name]=answer
                for attempt in attempts:
                    if 'response' in attempt:
                        usage['provider_requests']+=1
                        for key in ['prompt_tokens','completion_tokens','total_tokens']:usage[key]+=int(attempt['response'].get('usage',{}).get(key,0))
                    elif attempt['error'].startswith('provider_'):usage['provider_requests']+=1
        if trace:trace(response_text=json.dumps(rows,ensure_ascii=False),parsed_response=answers,usage=usage)
        failures=[row['error'] for row in rows if row['error']]
        if failures:raise ProviderError(failures[0])
        selected=answers['tactic']['selected'];decision=copy.deepcopy(batch['command_candidates'][selected])
        if 'posture' in answers and decision['action']!='wait':decision['posture']=answers['posture']['selected']
        decision['reason']='DeepSeek 多题选择 '+selected+'；候选覆盖 '+str(round(answers['tactic']['coverage']*100))+'%（非胜率）'
        usage['logprobs_evaluation']={'questions':answers,'model':self.config['model'],'requests_per_round':len(batch['requests'])}
        return decision,usage
