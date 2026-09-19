#!/usr/bin/env python3
"""Record how approved preview assets map to the live main project. No network."""
import hashlib,json,struct
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
REVIEW=ROOT.parent/'combat-review-v2'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def glb(p):
 data=p.read_bytes();length=struct.unpack_from('<I',data,12)[0];return json.loads(data[20:20+length])
def main():
 references={
  'models/toy-soldier.glb':'scripts/toy_actor.gd',
  'models/office-worker.glb':'scripts/game.gd',
  'models/office-sandbox.glb':'scripts/game.gd',
  'models/tank.glb':'scripts/unit.gd',
  'models/antitank-gun.glb':'scripts/field_gun.gd',
  'models/sandbag.glb':'scripts/sandbox_map.gd',
  **{f'models/{n}.glb':'scripts/toy_actor.gd' for n in ['rifle','pistol','rocket']},
  'models/grenade.glb':'scripts/combat_fx.gd',
  **{f'audio/{n}.wav':'scripts/combat_fx.gd' for n in ['rifle','pistol','reload','grenade_blast','rocket_launch','rocket_blast','tank_cannon','tank_impact']},
  **{f'vfx/{n}':'scripts/combat_fx.gd' for n in ['flow.png','fx.png','soft_flipbook.gdshader']},
  'fonts/DeskfrontUI.otf':'scripts/game.gd'}
 catalog={r['path']:r for r in json.loads((ROOT/'.forge/assets.json').read_text())['assets']}
 rows=[]
 for rel,loader in references.items():
  p=ROOT/'assets'/rel;review=REVIEW/'assets'/rel;record=catalog.get('assets/'+rel,{})
  rows.append({'path':'assets/'+rel,'loader':loader,'sha256':sha(p),'preview_sha256':sha(review) if review.exists() else None,'variant':'approved_preview' if review.exists() and sha(review)==sha(p) else 'main_game_revision','license':record.get('license'),'registered_hash_matches':record.get('sha256')==sha(p)})
 soldier=glb(ROOT/'assets/models/toy-soldier.glb');worker=glb(ROOT/'assets/models/office-worker.glb')
 meshes=[r.get('name','') for r in worker['meshes']]
 report={'passed':all(r['registered_hash_matches'] and r['license'] for r in rows) and any('Suit' in n for n in meshes),'assets':rows,'soldier_clips':[r['name'] for r in soldier['animations']],'worker_meshes':meshes,'worker_animation':[r['name'] for r in worker['animations']],'note':'Runtime loading and interactions verified separately by Godot and browser tests; differing main-game variants are preserved, not downgraded.'}
 out=ROOT/'output/asset-application/inventory.json';out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'passed':report['passed'],'assets':len(rows),'soldier_clips':len(report['soldier_clips']),'worker':meshes}));return 0 if report['passed'] else 1
if __name__=='__main__':raise SystemExit(main())
