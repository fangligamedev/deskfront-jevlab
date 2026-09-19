"""Per-unit LM decisions. Only Godot executes gameplay; secrets never leave the provider client."""
import concurrent.futures
import copy
import json
import math
import os
from pathlib import Path
import threading
import time
import urllib.error
import urllib.request
import urllib.parse

ACTIONS = {'move', 'capture', 'cover', 'flank', 'retreat', 'hold', 'attack', 'grenade', 'posture', 'wait', 'man_at_gun', 'leave_gun', 'garrison', 'leave_building'}
INTENTS = {'survive', 'support', 'advance', 'flank', 'engage', 'withdraw', 'capture', 'observe'}
SYSTEM = '''你指挥桌面 RTS 中唯一一名玩具兵或坦克。观察是真实游戏状态，坐标为米 [x,z]。
目标：活着赢得战斗，争夺中央目标并消灭有威胁的敌人。三个阵营互为敌人。独立决策，只能控制 self。
保命不是一直留在出生点。重伤/高压制/实际暴露时 cover 或 retreat；健康、无直接威胁且未占点时必须寻找安全的推进机会，已有掩体不是永久 hold 的理由。
mission.advance_unit_id 是本队优先推进者的分工参考，不是已经执行的命令。该单位健康且未暴露时优先 capture 或 move；其他单位跟进到能提供实际火力的位置，不要所有人都等待他人先开枪。
掩体内若 self.combat.engageable_targets 非空，可 attack 有效目标或 hold 持续自动开火；若没有有效射位、没有占点且 progress.idle_seconds 超过 6 秒，应 move/capture/flank 调整位置，不能连续以“观察”为由原地停滞。高风险时允许继续隐蔽。
保持正在执行且有进展的路线或设备任务用 wait，不要用 hold 清空路线。路径失败后应换目标。只有正在产生火力、占点、防守必要通道或面对明确危险时，原地防守才有实际战术价值。
开阔交火可 prone，移动转移通常 auto 跑动，高压制才 prone 爬行；低掩体隐蔽和探头由执行器处理。
友军最近真正开火且仍能射击才算掩护，不能凭队友站着就单人冲锋。但无敌方有效火力覆盖的接敌前移动不需要等队友开枪。根据射程和 self.combat.incoming_threats 判断当前位置风险，不可把当前位置安全误当整条路线安全。转移途中执行器仍会紧急自保。
轻武器对坦克无效，禁止用步枪/冲锋枪/手枪 attack 坦克。敌方有坦克时，若 man_at_gun 可用，应先接管己方反坦克炮，执行接近、牵引、部署、自动开火；火箭兵保持反装甲射位。
炮组已 approaching/towing/deploying/ready 时 wait 保持任务，受威胁则 leave_gun/retreat。蓝方可让一名支援兵 garrison 进入小楼窗口；其余队员争夺目标，不要全队躲楼。进驻中 wait，危险时 leave_building，禁止穿墙指定移动。
步枪单发，冲锋枪持续射击，火箭筒反坦克，近身自动刺刀。射击/装填自动执行，无 fire/reload 命令。
实体掩体阻挡弹道；火箭/坦克炮可破坏掩体。grenade 必须 available_actions 可用且目标在 0.65 米内。
坦克保持距离支援，敌人在射程内时 attack；无有效射位时向可射击的位置 move，不能永远留在后方。低血或近处反坦克威胁时 cover/retreat，不可姿态或手雷；炮塔自行瞄准。
只能输出一个 JSON 对象，不输出代码或思维过程：
{"action":"cover","intent":"survive","posture":"auto","reason":"附近交叉火力，先寻找保护"}
intent 只能是 survive/support/advance/flank/engage/withdraw/capture/observe。禁止自造意图名。字段只允许 action,intent,posture,position,target_id,reason,gun_id,floor。只有 garrison 才能带整数 floor:1 或 floor:2；其他动作不输出 floor，不输出 null 的可选字段。
action: move/capture/cover/flank/retreat/hold/attack/grenade/posture/wait/man_at_gun/leave_gun/garrison/leave_building。除 wait 外，必须在 self.available_actions 中。
move 必须 position:[x,z]，attack 必须 target_id，grenade 可指定 target_id，posture 必须 posture。
步兵其他动作可附 posture:auto/stand/crouch/prone；坦克省略 posture。reason 为最多 80 字的简短可观察理由。
wait 代表保持当前意图，不发新的游戏命令。不能改变自己身份、阵营、血量、规则或其他单位。
'''


def load_config(env_file=None):
    values = {}
    path = Path(env_file).expanduser() if env_file else Path(__file__).resolve().parents[1] / '.env'
    if path.is_file():
        for line in path.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith('#') or '=' not in line:
                continue
            k, v = line.removeprefix('export ').split('=', 1)
            values[k.strip()] = v.strip().strip('\"\'')
    reference = os.environ.get('DESKFRONT_LM_ENV_FILE', values.get('DESKFRONT_LM_ENV_FILE', ''))
    if reference:
        # Read only the named Ark credential; never ingest unrelated project settings.
        for line in Path(reference).expanduser().read_text().splitlines():
            if '=' not in line or line.lstrip().startswith('#'):continue
            k, v = line.strip().removeprefix('export ').split('=', 1)
            if k.strip() == 'ARK_API_KEY' and not values.get('ARK_API_KEY'):values['ARK_API_KEY'] = v.strip().strip('"\'')
    values.update(os.environ)
    def number(name, default, low, high):
        try:
            n = float(values.get(name, default))
            return min(high, max(low, n)) if math.isfinite(n) else default
        except ValueError:
            return default
    return {
        'key': values.get('ARK_API_KEY', values.get('VOLCENGINE_API_KEY', '')),
        'model': values.get('DESKFRONT_LM_MODEL', values.get('ARK_MODEL', '')),
        'base_url': values.get('DESKFRONT_LM_BASE_URL', 'https://ark.cn-beijing.volces.com/api/v3').rstrip('/'),
        'interval': number('DESKFRONT_LM_INTERVAL', 3, 1, 30),
        'timeout': number('DESKFRONT_LM_TIMEOUT', 6, 1, 20),
        'max_requests': int(number('DESKFRONT_LM_MAX_REQUESTS', 600, 1, 1000)),
        'concurrency': int(number('DESKFRONT_LM_CONCURRENCY', 3, 1, 9)),
    }


class ProviderError(Exception):
    pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ProviderError('provider_redirect_refused')


class ArkClient:
    def __init__(self, config):
        self.config = config
        url = urllib.parse.urlsplit(config['base_url'])
        # Credentials only go to the explicitly intended official Ark inference host.
        if url.scheme != 'https' or url.hostname != 'ark.cn-beijing.volces.com' or url.username or url.password or url.query or url.fragment or url.port not in (None, 443) or url.path.rstrip('/') != '/api/v3':
            raise ValueError('unsupported_ark_endpoint')

    def __call__(self, observation):
        cfg = self.config
        payload = {'model': cfg['model'], 'messages': [{'role': 'system', 'content': SYSTEM + ('\n本次 self 是坦克。输出示例：{"action":"cover","intent":"survive","reason":"拉开与火箭兵距离"}。绝不输出 posture 字段。' if observation['self']['kind']=='tank' else '')}, {'role': 'user', 'content': json.dumps(observation, ensure_ascii=False, separators=(',', ':'))}], 'max_tokens': 256, 'temperature': .2, 'thinking': {'type': 'disabled'}, 'response_format': {'type': 'json_object'}}
        req = urllib.request.Request(cfg['base_url'] + '/chat/completions', data=json.dumps(payload).encode(), headers={'Authorization': 'Bearer ' + cfg['key'], 'Content-Type': 'application/json'})
        try:
            with urllib.request.build_opener(NoRedirect()).open(req, timeout=cfg['timeout']) as r:
                raw = r.read(131073)
            if len(raw) > 131072:
                raise ProviderError('response_too_large')
            data = json.loads(raw)
            content = data['choices'][0]['message']['content']
            if not isinstance(content, str):
                raise ProviderError('missing_json_content')
            usage = data.get('usage', {})
            return json.loads(content), {k: int(usage.get(k, 0)) for k in ['prompt_tokens', 'completion_tokens', 'total_tokens']}
        except urllib.error.HTTPError as e:
            # Do not surface provider bodies: they may echo headers or inputs.
            raise ProviderError('provider_http_' + str(e.code)) from None
        except (urllib.error.URLError, TimeoutError, OSError):
            raise ProviderError('provider_network_or_timeout') from None
        except (ValueError, KeyError, IndexError, TypeError):
            raise ProviderError('invalid_provider_json') from None


def observation(state, unit, memory):
    fields = ['id', 'faction', 'kind', 'weapon', 'hp', 'max_hp', 'position', 'goal', 'posture', 'suppression', 'ammo', 'reload_remaining', 'order_mode', 'locomotion', 'weapon_state', 'weapon_range', 'turret_yaw', 'reversing', 'in_cover', 'cover_id', 'cqb_stance', 'available_actions', 'last_shot_at', 'last_shot_target', 'survival_reason', 'path_failure', 'gun_id', 'building_floor', 'building_phase', 'elevation', 'combat', 'tactical_role']
    small = lambda u: {k: u[k] for k in fields if k in u}
    obs = {'run_id': state['run_id'], 'tick': state['tick'], 'time': state['time'], 'bounds': state['bounds'], 'self': small(unit), 'allies': [small(u) for u in state['units'] if u['hp'] > 0 and u['faction'] == unit['faction'] and u['id'] != unit['id']], 'enemies': [small(u) for u in state['units'] if u['hp'] > 0 and u['faction'] != unit['faction']], 'covers': [{k: c[k] for k in ['id', 'position', 'size', 'height', 'hp', 'alive'] if k in c} for c in state.get('covers', [])], 'objective': {k: state['objective'][k] for k in ['position', 'radius']}, 'weapon_rules': state.get('weapons', {}).get(unit.get('weapon'), {}), 'at_guns': state.get('at_guns',[]), 'building': state.get('building',{}), 'previous': memory[-2:]}

    members=[u for u in state['units'] if u['faction']==unit['faction'] and u['hp']>0]
    movers=[u for u in members if u['kind']!='tank' and u['hp']/max(1,u['max_hp'])>.45 and u.get('suppression',0)<.6 and not u.get('gun_id') and not u.get('building_phase')]
    movers.sort(key=lambda u:(u.get('tactical_role')!='assault',math.dist(u['position'],state['objective']['position']),u['id']))
    distance=math.dist(unit['position'],state['objective']['position'])
    obs['mission']={'advance_unit_id':movers[0]['id'] if movers else '', 'objective_distance':round(distance,3),'in_capture_zone':distance<=state['objective']['radius'],'goal':'安全接敌、建立实际火力、争夺目标；不能全队永久观察'}
    obs['scores']=state.get('scores',{})
    obs['covers']=[c for c in obs['covers'] if c.get('alive',True)]
    return obs


def validate_decision(value, state, unit):
    if not isinstance(value, dict) or set(value) - {'action', 'intent', 'posture', 'position', 'target_id', 'reason', 'gun_id', 'floor'}:
        raise ValueError('invalid_decision_fields')
    action = value.get('action')
    if action not in ACTIONS or value.get('intent') not in INTENTS:
        raise ValueError('invalid_decision_action_or_intent')
    if action != 'wait' and action not in unit.get('available_actions', []):
        raise ValueError('action_unavailable')
    clean = {'action': action, 'intent': value['intent'], 'reason': str(value.get('reason', ''))[:80]}
    if action == 'posture' and 'posture' not in value:
        raise ValueError('posture_required')
    if 'posture' in value:
        if unit['kind'] == 'tank' or value['posture'] not in {'auto', 'stand', 'crouch', 'prone'}:
            raise ValueError('invalid_posture')
        clean['posture'] = value['posture']
    if action == 'move':
        p = value.get('position');b = state['bounds']
        if not isinstance(p, list) or len(p) != 2 or not all(type(n) in (int, float) and math.isfinite(n) for n in p) or not (b[0] <= p[0] <= b[2] and b[1] <= p[1] <= b[3]):
            raise ValueError('invalid_position')
        clean['position'] = p
    if 'floor' in value:
        if action != 'garrison' or type(value['floor']) is not int or value['floor'] not in (1,2):raise ValueError('invalid_floor')
        clean['floor']=value['floor']
    if 'gun_id' in value:
        if action != 'man_at_gun' or not any(g['id']==value['gun_id'] and g['faction']==unit['faction'] for g in state.get('at_guns',[])):raise ValueError('invalid_gun')
        clean['gun_id']=value['gun_id']
    if action == 'attack' and not value.get('target_id'):
        raise ValueError('target_required')
    if 'target_id' in value:
        targets = [u for u in state['units'] if u['hp'] > 0 and u['faction'] != unit['faction'] and u['id'] == value['target_id']]
        if not targets:
            raise ValueError('invalid_target')
        if action == 'attack' and targets[0].get('kind')=='tank' and unit.get('weapon') not in ('rocket','cannon'):raise ValueError('anti_armor_required')
        if action == 'grenade' and math.dist(unit['position'], targets[0]['position']) > .65:
            raise ValueError('grenade_out_of_range')
        clean['target_id'] = value['target_id']
    return clean


class LMController:
    def __init__(self, state, config, client=None):
        self.state = state;self.config = config
        self.client = client if client is not None else ArkClient(config)
        self.ready = bool(config['key'] and config['model'])
        self.pool = concurrent.futures.ThreadPoolExecutor(max_workers=config['concurrency'], thread_name_prefix='deskfront-lm')
        self.lock = threading.Lock();self.stop_event = threading.Event()
        self.run_id = '';self.pending = {};self.units = {};self.next_due = {};self.memory = {};self.fallback_due = {}
        self.used = 0;self.metrics = {};self.history = [];self.backoff_until = 0
        self.status='idle';self.progress={}
        self.thread = None

    def start(self):
        self.thread = threading.Thread(target=self._loop, daemon=True);self.thread.start()

    def close(self):
        self.stop_event.set()
        if self.thread:self.thread.join(timeout=2)
        self.pool.shutdown(wait=False, cancel_futures=True)

    def _loop(self):
        while not self.stop_event.wait(.15):
            try:self.tick()
            except Exception:
                # Internal failures do not take down the real-time simulation or leak secrets.
                with self.lock:self.metrics['controller_errors'] = self.metrics.get('controller_errors', 0) + 1

    def snapshot(self):
        with self.lock:
            return copy.deepcopy({'status':self.status,'configured': self.ready, 'provider': 'volcengine_ark', 'model': self.config['model'], 'interval_seconds': self.config['interval'], 'max_requests': self.config['max_requests'], 'used_requests': self.used, 'budget_remaining': max(0, self.config['max_requests'] - self.used), 'run_id': self.run_id, 'in_flight': len(self.pending), 'metrics': self.metrics, 'units': self.units, 'recent': self.history[-18:]})

    def _record(self, entry):
        self.history.append(entry)
        self.history = self.history[-120:]
        self.state.record('lm_decision', entry)

    def _submit(self, s, u, decision, origin, now, seen_tick=None):
        entry = {'unit_id': u['id'], 'run_id': s['run_id'], 'tick': s['tick'], 'phase': 'waiting' if decision['action'] == 'wait' else 'submitted', 'origin': origin, **decision}
        if decision['action'] != 'wait':
            c = {k: v for k, v in decision.items() if k not in {'intent', 'reason'}}
            c.update(faction=u['faction'], unit_ids=[u['id']], run_id=s['run_id'], seen_tick=s['tick'] if seen_tick is None else seen_tick, control_epoch=s.get('control_epochs', {}).get(u['faction'], 0), intent=decision['intent'], reason=decision['reason'])
            code, ack = self.state.submit(c, source='lm')
            if code == 202:entry['command_id'] = ack['id']
            else:entry.update(phase='rejected', error=ack.get('error', 'queue_rejected'))
        self.units[u['id']] = entry
        if origin=='deepseek_lm':
            counts=self.metrics.setdefault('unit_decisions', {});counts[u['id']]=counts.get(u['id'], 0)+1
            actions=self.metrics.setdefault('model_actions',{});actions[decision['action']]=actions.get(decision['action'],0)+1
        self.memory.setdefault(u['id'], []).append({k: entry[k] for k in ['action', 'intent', 'reason']})
        self.memory[u['id']] = self.memory[u['id']][-2:]
        self._record(entry)
        self.next_due[u['id']] = now + self.config['interval']

    def _fallback(self, s, u, reason, now):
        if now < self.fallback_due.get(u['id'], 0):return
        self.fallback_due[u['id']] = now + 6
        action = 'wait' if u.get('gun_id') or u.get('building_phase') or u.get('in_cover') or u.get('survival_reason') or u.get('order_mode') == 'self_preserve' else 'cover'
        self._submit(s, u, {'action': action, 'intent': 'survive', 'reason': reason}, 'local_fallback', now)
        self.units[u['id']]['phase'] = 'fallback'
        self.metrics['fallbacks'] = self.metrics.get('fallbacks', 0) + 1

    def tick(self):
        now = time.monotonic()
        # Lock order: state snapshot first; never hold State.lock while taking LM.lock.
        with self.state.lock:
            s = copy.deepcopy(self.state.state);age = now - self.state.updated;acks = copy.deepcopy(self.state.results)
        with self.lock:
            if not s or 'run_id' not in s:return
            if self.run_id != s['run_id']:
                self.run_id = s['run_id'];self.units = {};self.memory = {};self.next_due = {};self.fallback_due = {};self.used = 0;self.metrics = {};self.history = [];self.backoff_until = 0;self.progress={}
            live = {u['id']: u for u in s['units'] if u['hp'] > 0}
            active = {k: u for k, u in live.items() if s.get('control', {}).get(u['faction']) == 'lm'}
            self.status=('unconfigured' if not self.ready else 'offline' if age>3 else 'finished' if s.get('winner') else 'idle' if not active else 'paused' if s.get('paused') else 'budget_exhausted' if self.used>=self.config['max_requests'] else 'backoff' if now<self.backoff_until else 'running')
            for uid, row in self.units.items():
                if uid not in live:row['phase'] = 'dead'
                elif uid not in active:row['phase'] = 'inactive'
                elif row.get('command_id') in acks and row.get('phase') == 'submitted':
                    ack = acks[row['command_id']];row['receipt'] = ack;row['phase'] = 'executing' if ack['accepted'] else 'rejected'
                    metric = 'accepted' if ack['accepted'] else 'rejected';self.metrics[metric] = self.metrics.get(metric, 0) + 1
            for uid, task in list(self.pending.items()):
                if not task['future'].done():continue
                del self.pending[uid]
                u = active.get(uid)
                if task['run_id'] != s['run_id'] or u is None or age > 3 or s.get('paused') or s.get('winner') or task['epoch'] != s.get('control_epochs', {}).get(u['faction'], 0) or s['tick'] - task['tick'] > 300:
                    self.metrics['discarded'] = self.metrics.get('discarded', 0) + 1
                    if u:self.units[uid] = {'unit_id': uid, 'phase': 'stale', 'reason': '控制权、局次或观察已变化，丢弃旧回复'}
                    continue
                try:
                    value, usage = task['future'].result()
                    self.metrics['responses'] = self.metrics.get('responses', 0) + 1
                    self.metrics['tokens'] = self.metrics.get('tokens', 0) + usage.get('total_tokens', 0)
                    latency = round((now - task['started']) * 1000)
                    self.metrics['latency_ms_total'] = self.metrics.get('latency_ms_total', 0) + latency
                    decision = validate_decision(value, s, u)
                    self._submit(s, u, decision, 'deepseek_lm', now, task['tick'])
                    self.units[uid]['latency_ms'] = latency;self.units[uid]['usage'] = usage
                except (ProviderError, ValueError, TypeError, KeyError) as error:
                    code=str(error) if isinstance(error, ProviderError) else (str(error) if isinstance(error,ValueError) and str(error) in {'invalid_decision_fields','invalid_decision_action_or_intent','action_unavailable','invalid_posture','invalid_floor','invalid_gun','invalid_position','target_required','invalid_target','grenade_out_of_range','anti_armor_required','posture_required'} else 'invalid_or_unavailable_action')
                    self.metrics['last_error'] = code
                    counts=self.metrics.setdefault('error_codes',{});counts[code]=counts.get(code,0)+1
                    self.metrics['errors'] = self.metrics.get('errors', 0) + 1
                    if isinstance(error, ProviderError):self.backoff_until = now + min(30, 2 ** min(4, self.metrics['errors']))
                    self._fallback(s, u, '模型请求或动作校验失败，保持自保', now)
            if age > 3 or s.get('paused') or s.get('winner'):return
            for uid in sorted(active, key=lambda k: self.next_due.get(k, 0)):
                u = active[uid]
                if uid in self.pending or now < self.next_due.get(uid, 0):continue
                row=self.units.get(uid, {})
                if row.get('phase')=='submitted' and row.get('command_id') not in acks:continue
                if not self.ready or self.used >= self.config['max_requests'] or now < self.backoff_until:
                    self._fallback(s, u, {'unconfigured':'LLM 未配置，使用本地自保','budget_exhausted':'LLM 本局预算已耗尽，模型已停止请求，使用本地自保','backoff':'LLM 请求暂时失败，退避期间使用本地自保'}.get(self.status,'LLM 暂不可用，使用本地自保'), now);continue
                if len(self.pending) >= self.config['concurrency']:break
                obs = observation(s, u, self.memory.get(uid, []))
                previous=self.progress.get(uid)
                if previous is None or math.dist(u['position'],previous['position'])>.04 or u.get('last_shot_at',-1)!=previous['shot']:
                    previous={'position':list(u['position']),'shot':u.get('last_shot_at',-1),'time':s['time']};self.progress[uid]=previous
                obs['progress']={'idle_seconds':round(max(0,s['time']-previous['time']),1),'last_action':row.get('action',''),'last_receipt':row.get('receipt',{}).get('message','')}

                future = self.pool.submit(self.client, obs)
                self.pending[uid] = {'future': future, 'run_id': s['run_id'], 'tick': s['tick'], 'epoch': s.get('control_epochs', {}).get(u['faction'], 0), 'started': now}
                self.units[uid] = {**self.units.get(uid, {}), 'unit_id': uid, 'phase': 'thinking', 'started_tick': s['tick']}
                self.next_due[uid] = now + self.config['interval'];self.used += 1
                counts=self.metrics.setdefault('unit_calls', {});counts[uid]=counts.get(uid, 0)+1
