"""Original deterministic 16-bit mono Foley / combat synthesis; CC0-1.0.
No samples, model provider or third-party recordings. 22050Hz, peak <= .78.
"""
import math, random, wave, struct, pathlib
ROOT=pathlib.Path(__file__).resolve().parents[2]
OUT=ROOT/'source/audio/generated';OUT.mkdir(exist_ok=True)
RATE=22050
DURATIONS={'rifle':.24,'smg':.13,'rocket':.65,'cannon':.8,'explosion':1.05,'impact':.16,'bayonet':.26,'order':.12,'reload':.35}
for index,(name,duration) in enumerate(DURATIONS.items()):
 rng=random.Random(1809+index);data=[];low=0.0
 for i in range(round(duration*RATE)):
  t=i/RATE;n=rng.uniform(-1,1);low=.86*low+.14*n
  if name in ('rifle','smg'):
   x=(n*.75+math.sin(2*math.pi*(160 if name=='rifle' else 230)*t)*.35)*math.exp(-t*(25 if name=='rifle' else 40))
  elif name in ('cannon','explosion'):
   x=(low*2.2+math.sin(2*math.pi*(65*t-15*t*t))*.28)*math.exp(-t*5)+n*.3*math.exp(-t*65)
  elif name=='rocket':x=(n*.32+low)*math.exp(-t*5)*min(1,t*150)
  elif name=='impact':x=n*math.exp(-t*40)+math.sin(2*math.pi*1100*t)*.12*math.exp(-t*28)
  elif name=='bayonet':x=n*.45*math.exp(-((t-.08)/.05)**2)+low*math.exp(-abs(t-.15)*45)
  elif name=='reload':x=n*(math.exp(-abs(t-.03)*160)+.5*math.exp(-abs(t-.21)*190))
  else:x=math.sin(2*math.pi*(780*t+150*t*t))*math.exp(-t*30)*.3
  data.append(x*min(1,t*1200)*min(1,(duration-t)*400))
 peak=max(abs(v) for v in data) or 1
 with wave.open(str(OUT/(name+'.wav')),'wb') as f:
  f.setparams((1,2,RATE,0,'NONE','not compressed'))
  f.writeframes(b''.join(struct.pack('<h',int(v/peak*.78*32767)) for v in data))
 print(name, duration)
