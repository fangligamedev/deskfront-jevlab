"""Reproducible Q009 CC-BY-SA-3.0 derivatives; separate source takes, not pitch clones."""
import pathlib,subprocess,json,hashlib,shutil,os
R=pathlib.Path(__file__).resolve().parents[2];S=R/'source/latest/q009/q009';D=R/'assets/audio';ff=os.environ.get('FFMPEG_BIN') or shutil.which('ffmpeg') or 'ffmpeg'
rows=[]
for name,stem,gain in [('rifle','rifle',.60),('smg','minigun',.40),('pistol','pistol',.60),('rocket_launch','rlauncher',.65),('tank_cannon','glauncher',.65),('grenade_blast','grenade',.65)]:
 for variant in [2,3]:
  source=S/f'{stem}{variant}.ogg';dest=D/f'{name}_{variant}.wav';filters=f'volume={gain},alimiter=limit=0.85:level=false'
  subprocess.run([ff,'-v','error','-y','-i',str(source),'-af',filters,'-ar','44100','-ac','1',str(dest)],check=True)
  rows.append({'path':str(dest.relative_to(R)),'source':str(source.relative_to(R)),'license':'CC-BY-SA-3.0','author':'Q009','processing':filters,'sha256':hashlib.sha256(dest.read_bytes()).hexdigest()})
(R/'docs/evidence/optimization/audio-variants.json').write_text(json.dumps(rows,indent=2))
