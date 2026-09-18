# -*- coding: utf-8 -*-
import json,pathlib
R=pathlib.Path(__file__).resolve().parents[3]
levels=[]
def add(id,name,color,spawns):
 l={'id':id,'name':name,'bounds':[-.30,.80,1.38,3.46],'floor_color':color,'spawns':spawns,'tank_spawn':[-.03,1.01],'target':[.56,2.12],'objects':[]};levels.append(l);return l

def box(l,id,x,z,w,d,h,color,kind='wall',yaw=0):l['objects'].append({'id':id,'kind':kind,'position':[x,z],'size':[w,h,d],'color':color,'yaw':yaw,'collision':h>.02,'destructible':kind=='crate'})
spawns=[[-.05,3.25],[1.16,1.17],[.10,1.35]]
# Open battlefield: low cover islands; continuous side lanes; exposed central objective.
l=add('crossroads','三线争夺场','#a9ac8b',spawns)
l['design']={'cover_height_limit':.065,'lanes':['west flank','central contested approach','east flank'],'tank_team':2,'tank_role':'rear reserve'}
box(l,'central-route',.54,2.14,.32,2.48,.004,'#bcb594','road')
for i,x in enumerate([-.19,1.25]):box(l,f'flank-route-{i}',x,2.17,.12,2.40,.004,'#b7b395','road')
box(l,'crossing',.54,2.14,1.58,.17,.005,'#bcb594','road')
box(l,'objective-apron',.54,2.17,.43,.38,.007,'#969e82','road')
for i,(x,z,w,angle) in enumerate([(.13,1.68,.34,-12),(1.00,1.62,.30,12),(.55,1.91,.25,0),(.06,2.30,.30,90),(1.01,2.31,.30,90),(.59,2.57,.27,0),(.12,2.91,.30,-12),(.99,2.88,.28,12)]):
 box(l,f'cover-{i}',x,z,w,.043,.060,'#ada582','sandbag',angle)
for i,(x,z,w,d,h) in enumerate([(.32,2.35,.09,.06,.042),(.78,1.99,.08,.065,.04),(.90,2.72,.085,.07,.045)]):
 box(l,f'crate-{i}',x,z,w,d,h,'#988157','crate')
# Small flat rubble patches break up approaches without obstructing soldier silhouettes.
for i,(x,z) in enumerate([(.30,1.49),(.80,1.40),(.24,2.70),(.76,3.07)]):
 box(l,f'rubble-{i}',x,z,.11,.065,.026,'#9b9e88','rock',18*i)
l=add('river','河谷双桥','#9ba887',spawns)
box(l,'river',.54,2.09,1.67,.36,.008,'#6b9391','water')
for i,x in enumerate([.04,1.01]):
 box(l,f'bridge-{i}',x,2.09,.23,.48,.023,'#b4a17a','bridge')
 for j in [-1,1]:box(l,f'rail-{i}-{j}',x+j*.12,2.09,.018,.47,.045,'#858873')
for i,(x,z) in enumerate([(.40,1.40),(.96,1.45),(.3,2.8),(1.05,3.06),(.78,2.65)]):
 box(l,f'rock-{i}',x,z,.19,.16,.10,'#859177','rock',i*24)
for i,(x,z) in enumerate([(.06,2.5),(.94,1.73),(.23,3.21)]):box(l,f'sandbags-{i}',x,z,.3,.038,.055,'#afa886','sandbag')
l=add('outpost','前哨阵地','#b9aa87',spawns)
for i,(x,z) in enumerate([(.08,1.44),(1.02,1.61),(.00,2.68),(1.01,2.83),(.50,2.22)]):
 box(l,f'sandbags-{i}',x,z,.38,.045,.065,'#a99c77','sandbag')
 box(l,f'trench-{i}',x,z+.075,.37,.10,.004,'#80775e','road')
for i,(x,z) in enumerate([(.66,1.12),(.99,3.13),(.22,2.08),(.93,2.42)]):box(l,f'crate-{i}',x,z,.10,.10,.06,'#91764c','crate')
box(l,'rear-sandbags',.43,1.52,.30,.045,.060,'#a99c77','sandbag')
for l in levels:
 l['objective']=[.54,2.17]
(R/'data/sandbox-maps.json').write_text(json.dumps({'schema_version':1,'table_height':.82,'map_top':.838,'levels':levels},ensure_ascii=False,indent=2))
