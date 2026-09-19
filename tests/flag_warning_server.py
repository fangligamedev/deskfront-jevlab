"""Isolated QA server with a deterministic test LM; never calls a cloud provider."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import server
from lm_controller import LMController

def decide(o):
    if o['flag_warning']['active']:
        action='hold' if o['mission']['in_capture_zone'] else 'capture'
        if o['self'].get('building_phase'):action='leave_building'
        elif o['self'].get('gun_id'):action='leave_gun'
        if action not in o['self']['available_actions']:action='wait'
        return {'action':action,'intent':'capture','reason':'测试模型：依据收到的败北预警反攻旗点'},{}
    return {'action':'wait','intent':'observe','reason':'测试模型：保持当前守旗或待命'},{}

if __name__=='__main__':
    config={'key':'LOCAL_TEST_NOT_A_CREDENTIAL','model':'deterministic-flag-test-client','base_url':'https://example.invalid','interval':3,'timeout':1,'max_requests':600,'concurrency':3,'log_path':':memory:'}
    server.LM=LMController(server.STATE,config,decide);server.LM.start()
    port=int(sys.argv[1]) if len(sys.argv)>1 else 8783
    http=server.ThreadingHTTPServer(('127.0.0.1',port),server.Handler)
    print('LOCAL TEST CLIENT http://127.0.0.1:'+str(port),flush=True)
    try:http.serve_forever()
    finally:server.LM.close();http.server_close()
