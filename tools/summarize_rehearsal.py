#!/usr/bin/env python3
"""Summarize the actual Godot rehearsal output; never substitute simulated results."""
import collections,gzip,hashlib,json,pathlib
ROOT=pathlib.Path(__file__).resolve().parents[1]
source=ROOT/'output/v05/final-rehearsal.json';data=json.loads(source.read_text());runs=data['runs']
assert len(runs)==100 and len({r['seed'] for r in runs})==100
out=ROOT/'docs/evidence/v05';out.mkdir(parents=True,exist_ok=True)
by_case=[]
for case in dict.fromkeys(r['case'] for r in runs):
 group=[r for r in runs if r['case']==case]
 by_case.append({'case':case,'runs':len(group),'passed':sum(r['passed'] for r in group),'shots':sum(r['shots'] for r in group),'destructions_including_scenario_injection':sum(r['destroyed'] for r in group),'max_unsafe_seconds':max(r['metrics']['unsafe_dwell_max'] for r in group),'max_stalled_seconds':max(r['metrics']['stuck_dwell_max'] for r in group)})
summary={'passed':data['passed'],'count':len(runs),'map_distribution':dict(collections.Counter(r['map'] for r in runs)),'fixed_dt':data['fixed_dt'],'simulated_seconds':sum(r['time'] for r in runs),'wall_seconds':data['wall_seconds'],'shots':sum(r['shots'] for r in runs),'destructions_including_scenario_injection':sum(r['destroyed'] for r in runs),'navigation_errors':sum(len(r['metrics']['invalid_navigation']) for r in runs),'animation_mismatches':sum(len(r['metrics']['animation_mismatch']) for r in runs),'walk_samples':sum(r['metrics']['walk_samples'] for r in runs),'max_unsafe_seconds':max(r['metrics']['unsafe_dwell_max'] for r in runs),'max_stalled_seconds':max(r['metrics']['stuck_dwell_max'] for r in runs),'by_case':by_case,'runs':[{k:r[k] for k in ['index','case','seed','map','passed','time','shots','destroyed','alive','collisions']} for r in runs]}
(out/'rehearsal-summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
(out/'rehearsal-full.json.gz').write_bytes(gzip.compress(source.read_bytes(),mtime=0))
previous=[]
for name in ['pilot','round1','round2','repair','repair2','round3']:
 path=ROOT/f'output/v05/{name}-rehearsal.json'
 if path.exists():
  old=json.loads(path.read_text());previous.append({'round':name,'count':old['count'],'passed_with_that_rounds_gates':old['passed'],'failure_indices':[r['index'] for r in old['runs'] if not r['passed']],'longest_stall':max(r['metrics'].get('stuck_dwell_max',0) for r in old['runs'])})
(out/'iteration-history.json').write_text(json.dumps(previous,indent=2)+'\n')
files=[*ROOT.glob('scripts/*.gd'),ROOT/'data/battle.json',ROOT/'data/gait.json',ROOT/'data/sandbox-maps.json',ROOT/'assets/models/toy-soldier.glb']
hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
(out/'runtime-source-hashes.json').write_text(json.dumps(hashes,indent=2)+'\n')
print(json.dumps({k:v for k,v in summary.items() if k not in ['runs']},ensure_ascii=False,indent=2))
