import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import math, threading, unittest
from deepseek_logprobs import DeepSeekLogprobsClient,option_distribution
from lm_controller import ProviderError,observation,validate_decision
from test_lm import state

def answer(letter='A',tokens=None):
    return {'choices':[{'message':{'content':letter},'logprobs':{'content':[{'token':letter,'logprob':-.1,'top_logprobs':tokens or [{'token':'A','logprob':-.1},{'token':'B','logprob':-2}]}]}}], 'usage':{'prompt_tokens':10,'completion_tokens':1,'total_tokens':11}}
def cfg():return {'base_url':'https://ark.cn-beijing.volces.com/api/v3','key':'TEST','model':'test','timeout':1}
class LogprobsContract(unittest.TestCase):
    def test_missing_probs_do_not_become_fake_confidence(self):
        with self.assertRaisesRegex(ProviderError,'logprobs_unavailable'):option_distribution({'choices':[]},['A','B'])
    def test_malformed_positions_are_clear_errors(self):
        d=answer();d['choices'][0]['logprobs']['content']=[None,'bad']
        with self.assertRaisesRegex(ProviderError,'logprobs_no_option_tokens'):option_distribution(d,['A','B'])
    def test_partial_coverage_is_explicit(self):
        d=option_distribution(answer(),['A','B','C']);self.assertEqual(d['coverage'],2/3);self.assertEqual(d['probabilities']['C'],0);self.assertAlmostEqual(sum(d['probabilities'].values()),1)
    def test_trim_and_finite(self):
        d=option_distribution(answer(' A ',[{'token':'"B"','logprob':-.2},{'token':'C','logprob':float('nan')}]),['A','B','C']);self.assertEqual(d['selected'],'A');self.assertEqual(d['coverage'],2/3)
    def test_parallel_queries_and_valid_game_action(self):
        gate=threading.Barrier(3)
        def transport(p):gate.wait(timeout=2);return answer('B')
        s=state().state;u=s['units'][0];trace=[]
        decision,usage=DeepSeekLogprobsClient(cfg(),transport)(observation(s,u,[]),lambda **d:trace.append(d))
        validate_decision(decision,s,u);self.assertEqual(usage['provider_requests'],3);self.assertEqual(usage['total_tokens'],33);self.assertEqual(len(trace),1)
    def test_parse_retry_usage_is_counted(self):
        counts={};lock=threading.Lock()
        def transport(p):
            key=p['messages'][0]['content']
            with lock:counts[key]=counts.get(key,0)+1;n=counts[key]
            return answer('?', [{'token':'?','logprob':-.1}]) if n==1 else answer()
        s=state().state;d,usage=DeepSeekLogprobsClient(cfg(),transport)(observation(s,s['units'][0],[]))
        self.assertEqual(usage['provider_requests'],6);self.assertEqual(usage['total_tokens'],66)
    def test_missing_feature_no_repeated_retry(self):
        calls=[]
        def transport(p):calls.append(p);return {'choices':[{'message':{'content':'A'}}]}
        s=state().state
        with self.assertRaisesRegex(ProviderError,'logprobs_unavailable'):DeepSeekLogprobsClient(cfg(),transport)(observation(s,s['units'][0],[]))
        self.assertEqual(len(calls),3)
    def test_parked_enemies_excluded(self):
        s=state().state;s['units'][1]['deployment_phase']='parked';o=observation(s,s['units'][0],[])
        self.assertNotIn(s['units'][1]['id'],[u['id'] for u in o['enemies']+o['allies']])
    def test_eastfront_goal_precedes_central_flag(self):
        s=state().state;s['eastfront']={'enabled':True,'active_sector':3,'cleared':2,'chunks':[]}
        o=observation(s,s['units'][0],[]);self.assertEqual(o['mission']['eastfront']['active_sector'],3);self.assertFalse(o['flag_warning']['active'])
