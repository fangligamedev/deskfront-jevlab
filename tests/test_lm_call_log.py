import json
import io
import urllib.error
import tempfile
import threading
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
from test_lm import state, controller, settle
from lm_controller import ArkClient, ProviderError
from lm_call_log import CallLog


class Response:
    status=200
    def __init__(self, raw):self.raw=raw
    def read(self, n):return self.raw[:n]
    def __enter__(self):return self
    def __exit__(self, *args):pass


class LogContract(unittest.TestCase):
    def test_provider_billing_error_has_safe_actionable_code(self):
        client=ArkClient({'base_url':'https://ark.cn-beijing.volces.com/api/v3','key':'TEST_SECRET','timeout':1})
        error=urllib.error.HTTPError('https://ark.cn-beijing.volces.com/api/v3/chat/completions',403,'Forbidden',{},io.BytesIO(b'{"error":{"code":"AccountOverdueError"}}'))
        with patch('urllib.request.OpenerDirector.open',side_effect=error):
            with self.assertRaisesRegex(ProviderError,'^provider_account_overdue$'):client.complete({})

    def test_persistent_pagination_and_redaction(self):
        with tempfile.TemporaryDirectory() as d:
            path=str(Path(d)/'log.sqlite3');log=CallLog(path,'TEST_SECRET')
            for i in range(5):log.start(unit_id='green-1' if i%2 else 'red-tank',run_id='r',request={'key':'TEST_SECRET','message':'Bearer TEST_SECRET'},model='test')
            log.update(5,response_text='echo TEST_SECRET',phase='returned')
            restored=CallLog(path,'TEST_SECRET');page=restored.list(limit=2)
            self.assertEqual([r['id'] for r in page['items']],[5,4])
            self.assertEqual([r['id'] for r in restored.list(before=page['next_before'],limit=2)['items']],[3,2])
            self.assertEqual(len(restored.list(unit='green-1')['items']),2)
            self.assertNotIn('TEST_SECRET',json.dumps(restored.get(5)))
            self.assertNotIn(b'TEST_SECRET',Path(path).read_bytes())

    def test_exact_wire_payload_raw_response_and_receipt(self):
        s=state();c=controller(s,None,log_path=":memory:");wire=[]
        c.client=ArkClient(c.config)
        content='{"action":"hold","intent":"observe","reason":"test"}'
        raw=json.dumps({'choices':[{'message':{'content':content}}],'usage':{'total_tokens':21}}).encode()
        def open_req(req,timeout):wire.append(json.loads(req.data));return Response(raw)
        try:
            with patch('lm_controller.urllib.request.build_opener',return_value=SimpleNamespace(open=open_req)):
                c.tick();settle(c)
            records=[c.call_log.get(r['id']) for r in c.call_log.list()['items']]
            self.assertEqual(len(records),2)
            for row in records:
                self.assertIn(row['request'],wire)
                self.assertEqual(row['response_text'],raw.decode())
                self.assertEqual(row['parsed_response']['action'],'hold')
                self.assertEqual(row['usage']['total_tokens'],21)
            ids=list(s.pending);s.sync({'state':s.state,'acks':[{'id':id,'accepted':True,'message':'applied'} for id in ids]});c.tick()
            self.assertTrue(all(r['phase']=='executed' for r in c.call_log.list()['items']))
            self.assertNotIn('TEST_SECRET',json.dumps([c.call_log.get(r['id']) for r in c.call_log.list()['items']]))
        finally:c.close()

    def test_invalid_provider_json_retains_raw_reply(self):
        s=state();c=controller(s,None,log_path=":memory:");c.client=ArkClient(c.config)
        raw=b'{"choices":[{"message":{"content":"not valid json"}}]}'
        try:
            with patch('lm_controller.urllib.request.build_opener',return_value=SimpleNamespace(open=lambda *a,**k:Response(raw))):c.tick();settle(c)
            row=c.call_log.get(c.call_log.list()['items'][0]['id'])
            self.assertEqual(row['response_text'],raw.decode());self.assertEqual(row['error'],'invalid_provider_json')
            self.assertEqual(row['phase'],'error')
        finally:c.close()

    def test_discarded_reply_survives_reset_and_is_not_executed(self):
        release=threading.Event()
        def client(o):release.wait(1);return {'action':'wait','intent':'observe'},{}
        s=state();c=controller(s,client)
        try:
            c.tick();s.state['run_id']='next';s.state['paused']=True;release.set();settle(c)
            rows=[c.call_log.get(r['id']) for r in c.call_log.list()['items']]
            self.assertEqual(len(rows),2)
            self.assertTrue(all(r['phase']=='discarded' and r['run_id']=='r' and r['parsed_response']['action']=='wait' for r in rows))
            self.assertEqual(s.pending,{})
        finally:release.set();c.close()
