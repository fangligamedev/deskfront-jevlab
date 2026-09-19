"""Local, paginated LLM request/response audit; never store authorization headers."""
import json
import re
import sqlite3
import threading
import time
from pathlib import Path


class CallLog:
    def __init__(self, path=':memory:', secret='', extra_secrets=()):
        if path != ':memory:':Path(path).parent.mkdir(parents=True, exist_ok=True)
        self.secret = secret
        self.extra_secrets=tuple(v for v in extra_secrets if v)
        self.lock = threading.RLock()
        self.db = sqlite3.connect(str(path), check_same_thread=False)
        self.db.execute('CREATE TABLE IF NOT EXISTS calls (id INTEGER PRIMARY KEY AUTOINCREMENT, unit TEXT, run TEXT, updated REAL, body TEXT)')
        self.db.commit()

    def clean(self, value):
        if isinstance(value, dict):
            return {k: ('[REDACTED]' if k.lower() in {'authorization', 'api_key', 'key', 'access_token'} else self.clean(v)) for k, v in value.items()}
        if isinstance(value, list):return [self.clean(v) for v in value]
        if isinstance(value, str):
            for secret in (self.secret,)+self.extra_secrets:
                if secret:value = value.replace(secret, '[REDACTED]')
            return re.sub(r'(?i)Bearer\s+[^\s"\\]+', 'Bearer [REDACTED]', value)
        return value

    def start(self, **row):
        with self.lock:
            now = time.time()
            row.update(started_at=now, updated_at=now, phase='requesting')
            row = self.clean(row)
            cursor = self.db.execute('INSERT INTO calls(unit,run,updated,body) VALUES(?,?,?,?)', (row['unit_id'], row['run_id'], now, json.dumps(row, ensure_ascii=False)))
            self.db.commit()
            return cursor.lastrowid

    def get(self, id):
        with self.lock:
            row = self.db.execute('SELECT body FROM calls WHERE id=?', (id,)).fetchone()
            return dict(json.loads(row[0]), id=id) if row else None

    def update(self, id, **changes):
        with self.lock:
            row = self.get(id)
            if row is None:return
            row.update(self.clean(changes), updated_at=time.time())
            self.db.execute('UPDATE calls SET updated=?,body=? WHERE id=?', (row['updated_at'], json.dumps(row, ensure_ascii=False), id))
            self.db.commit()

    def list(self, before=None, unit='', limit=40, run=''):
        with self.lock:
            clauses=[];args=[]
            if before:clauses.append('id<?');args.append(int(before))
            if unit:clauses.append('unit=?');args.append(unit)
            if run:clauses.append('run=?');args.append(run)
            where=' WHERE '+' AND '.join(clauses) if clauses else ''
            rows=self.db.execute('SELECT id,body FROM calls'+where+' ORDER BY id DESC LIMIT ?', args+[min(100,max(1,limit))+1]).fetchall()
            more=len(rows)>limit;rows=rows[:limit]
            keys=['unit_id','faction','run_id','tick','started_at','updated_at','phase','model','latency_ms','error']
            items=[dict({k:v for k,v in json.loads(body).items() if k in keys}, id=id) for id,body in rows]
            return {'items':items,'next_before':items[-1]['id'] if more and items else None,'units':[r[0] for r in self.db.execute('SELECT DISTINCT unit FROM calls ORDER BY unit')]}
