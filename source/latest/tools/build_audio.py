# -*- coding: utf-8 -*-
import subprocess,pathlib,json
R=pathlib.Path(__file__).resolve().parents[3];src=R/'source/latest/q009/q009';dst=R/'assets/audio';ff=__import__('shutil').which('ffmpeg') or 'ffmpeg'
rows=[]
for name,source,filters in [('rifle','rifle.ogg','volume=0.65'),('pistol','pistol.ogg','volume=0.6'),('rocket_launch','rlauncher.ogg','volume=0.7'),('grenade_blast','grenade.ogg','volume=0.7'),('rocket_blast','explosion.ogg','volume=0.65'),('tank_cannon','glauncher.ogg','asetrate=35280,aresample=44100,bass=g=5:f=100,volume=0.7'),('tank_impact','grenade3.ogg','asetrate=33075,aresample=44100,bass=g=4:f=90,volume=0.65'),('reload','weapswitch.ogg','volume=0.6')]:
 out=dst/(name+'.wav');subprocess.run([ff,'-v','error','-y','-i',str(src/source),'-af',filters+',alimiter=limit=0.85:level=false','-ar','44100','-ac','1',str(out)],check=True)
 rows.append({'event':name,'source':source,'license':'CC-BY-SA-3.0','author':'Q009','processing':filters,'derivative_license':'CC-BY-SA-3.0'})
(R/'docs/audio-catalog.json').write_text(json.dumps(rows,indent=2))
