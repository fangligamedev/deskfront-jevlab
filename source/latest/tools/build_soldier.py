# -*- coding: utf-8 -*-
import bpy, math, pathlib, json, statistics
from mathutils import Vector, Matrix, Quaternion
R=pathlib.Path(__file__).resolve().parents[3]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(R/'source/latest/soldier-original.fbx'))
rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');rig.name='ToyRig'
meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
worlds={o:o.matrix_world.copy() for o in meshes};mw=rig.matrix_world.copy()
rig.data.transform(mw);rig.matrix_world=Matrix.Identity(4)
for o in meshes:
 o.data.transform(worlds[o]);o.matrix_world=Matrix.Identity(4);o.matrix_parent_inverse=Matrix.Identity(4)
lo=min(v.co.z for o in meshes for v in o.data.vertices)
shift=Vector((-rig.data.bones['Hips'].head_local.x,-rig.data.bones['Hips'].head_local.y,-lo))
T=Matrix.Translation(shift);rig.data.transform(T)
for o in meshes:
 o.data.transform(T)
 for poly in o.data.polygons:poly.use_smooth=True
mat=bpy.data.materials.new('Faction plastic');mat.diffuse_color=(.16,.23,.09,1);mat.use_nodes=True
bs=mat.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=mat.diffuse_color;bs.inputs['Roughness'].default_value=.32
bs.inputs['Coat Weight'].default_value=.16
for o in meshes:o.data.materials.clear();o.data.materials.append(mat)
bpy.context.view_layer.objects.active=rig;rig.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
b=rig.data.edit_bones.new('Root');b.head=(0,0,0);b.tail=(0,0,.1)
rig.data.edit_bones['Hips'].parent=b
bpy.ops.object.mode_set(mode='OBJECT')
# Retarget the CC0 author-published animation data; source is retained untouched.
before=set(bpy.data.objects);bpy.ops.import_scene.gltf(filepath=str(R/'source/latest/ual-author-preview.glb'))
src=next(o for o in bpy.data.objects if o not in before and o.type=='ARMATURE')
for tr in src.animation_data.nla_tracks:tr.mute=True
acts={a.name:a for a in bpy.data.actions}
mapnames={'Hips':'Hips','Spine':'Spine','Spine1':'Chest','Spine2':'UpperChest','Neck':'Neck','Head':'Head'}
for side in ['Left','Right']:
 for a,b in [('Shoulder','Shoulder'),('Arm','UpperArm'),('ForeArm','LowerArm'),('Hand','Hand'),('UpLeg','UpperLeg'),('Leg','LowerLeg'),('Foot','Foot'),('ToeBase','Toes')]:mapnames[side+a]=side+b
for pb in rig.pose.bones:pb.rotation_mode='QUATERNION'
rest={b.name:b.matrix_local.copy() for b in rig.data.bones}
ratio=rest['Hips'].translation.z/src.data.bones['Hips'].head_local.z
scene=bpy.context.scene;scene.render.fps=30
rig.animation_data_create(); baked=[];catalog=[]
# Helpers write global orientations with hierarchy updates, preserving the existing skin.
def orient(name,head,tail):
 pb=rig.pose.bones[name]; cur=pb.matrix.copy();q=cur.to_quaternion();curdir=(pb.tail-pb.head).normalized();nq=curdir.rotation_difference((Vector(tail)-Vector(head)).normalized())@q
 pb.matrix=Matrix.LocRotScale(Vector(head),nq,Vector((1,1,1)));bpy.context.view_layer.update()
reach_audit=[]
def arm(side,hand):
 # Two rigid bone segments. Never translate the wrist independently of its parent.
 a=rig.pose.bones[side+'Arm'];b=rig.pose.bones[side+'ForeArm'];p=a.head.copy()
 chest=rig.pose.bones['Spine2'].head.copy();ls=rig.pose.bones['LeftArm'].head;rs=rig.pose.bones['RightArm'].head
 sideways=ls-rs;sideways.z=0;sideways.normalize();back=Vector((0,0,1)).cross(sideways)
 offset=Vector(hand)-chest;offset.z-=.10
 h=(ls+rs)*.5+sideways*offset.x+back*offset.y+Vector((0,0,offset.z));v=h-p
 l1=a.length;l2=b.length;dist=max(math.sqrt(l1*l1+l2*l2+2*l1*l2*math.cos(math.radians(150))),min(v.length,(l1+l2)*.96));d=v.normalized();h=p+d*dist
 reach_audit.append({"clip":new,"frame":frame,"side":side,"correction":max(0,v.length-dist)})
 along=(l1*l1-l2*l2+dist*dist)/(2*dist);high=math.sqrt(max(0,l1*l1-along*along))
 pole=sideways*(.30 if side=='Left' else -.30)-back*.08+Vector((0,0,-1));pole=(pole-d*pole.dot(d)).normalized();el=p+d*along+pole*high
 # Stable rest-relative swing: avoid inheriting arbitrary twist from a hanging-arm clip.
 for name,start,end in [(side+'Arm',p,el),(side+'ForeArm',el,h)]:
  rb=rig.data.bones[name];q=(rb.tail_local-rb.head_local).normalized().rotation_difference((end-start).normalized())@rest[name].to_quaternion()
  rig.pose.bones[name].matrix=Matrix.LocRotScale(start,q,Vector((1,1,1)));bpy.context.view_layer.update()
 # A neutral wrist follows the forearm. Old world-space hand rotations broke wrists.
 wrist=rig.pose.bones[side+'Hand'];q=b.matrix.to_quaternion()@rest[side+'ForeArm'].to_quaternion().inverted()@rest[side+'Hand'].to_quaternion()
 wrist.matrix=Matrix.LocRotScale(wrist.head.copy(),q,Vector((1,1,1)));bpy.context.view_layer.update()
 # Curl around each finger's rest-frame hinge, not an assumed local Z axis.
 palm_normal=Vector((0,0,-1))
 for name in ['Middle','Index']:
  for idx in [1,2,3]:
   f=rig.pose.bones.get(side+'Hand'+name+str(idx))
   if f:
    rb=f.bone;direction=(rb.tail_local-rb.head_local).normalized();axis=direction.cross(palm_normal).normalized()
    local_axis=rb.matrix_local.to_quaternion().inverted()@axis
    f.rotation_quaternion=Quaternion(local_axis,.45 if idx==1 else .65)
 bpy.context.view_layer.update()
# Contact-authored step: one leading foot and then the trailing foot.
# World-space footprints and root curve are solved together, never a static pose translated sideways.
def ease(t):
 t=max(0,min(1,t));return t*t*t*(t*(t*6-15)+10)
def leg(side,ankle):
 a=rig.pose.bones[side+'UpLeg'];b=rig.pose.bones[side+'Leg'];hip=a.head.copy();v=Vector(ankle)-hip
 d=v.normalized();dist=max(.05,min(v.length,(a.length+b.length)*.985));ankle=hip+d*dist
 along=(a.length*a.length-b.length*b.length+dist*dist)/(2*dist)
 pole=Vector((.13 if side=='Left' else -.13,-1,0));pole=(pole-d*pole.dot(d)).normalized()
 knee=hip+d*along+pole*math.sqrt(max(0,a.length*a.length-along*along))
 orient(side+'UpLeg',hip,knee);orient(side+'Leg',knee,ankle)
 rig.pose.bones[side+'Foot'].matrix=Matrix.LocRotScale(Vector(ankle),rest[side+'Foot'].to_quaternion(),Vector((1,1,1)))
 bpy.context.view_layer.update()
foot_base={side:rest[side+'Foot'].translation.copy() for side in ['Left','Right']}
for side in foot_base:
 foot_base[side].x=.13 if side=='Left' else -.13
 foot_base[side].y=-.13 if side=='Left' else .10
# Capture an authored upright torso, then adapt its lean to a combat crouch.
idle=acts['Idle'];src.animation_data.action=idle;src.animation_data.action_slot=idle.slots[0];scene.frame_set(0)
idle_q={target:(src.pose.bones[source].matrix.to_quaternion()@src.data.bones[source].matrix_local.to_quaternion().inverted())@rest[target].to_quaternion() for target,source in mapnames.items()}

STEP=.44; STEP_TIME=1.05
gait={'version':2,'import_scale':.075,'step_meters':STEP*.075,'step_seconds':STEP_TIME,'clips':{}}
clips=[('rifle_idle','Idle'),('rifle_walk_rm','Walk'),('rifle_jog_rm','Jog_Fwd'),('rifle_sprint_rm','Sprint'),('cover_enter','Crouch_Enter'),('cover_idle','Crouch_Idle'),('cover_exit','Crouch_Exit'),('cover_shuffle_left','Crouch_Idle'),('cover_shuffle_right','Crouch_Idle'),('rifle_crouch_rm','Crouch_Fwd'),('turn_left','Turn90_L'),('turn_right','Turn90_R'),('dodge_left_rm','Dodge_Left_RM'),('roll_rm','Roll_RM'),('crawl','Crawl_Fwd'),('hit','Hit_Chest'),('death','Death01'),('pistol_fire','Pistol_Shoot'),('reload','Pistol_Reload'),('cover_peek_left','Crouch_Idle'),('cover_peek_right','Crouch_Idle'),('grenade_throw','Idle'),('rocket_aim','Idle'),('prone_idle','Crawl_Idle'),('prone_fire','Crawl_Idle'),('prone_reload','Crawl_Idle'),('crouch_reload','Crouch_Idle'),('bayonet','Idle'),('rifle_fire','Idle')]
for new,old in clips:
 act=acts[old];src.animation_data.action=act
 if hasattr(act,'slots') and len(act.slots):src.animation_data.action_slot=act.slots[0]
 lateral=new in ['cover_shuffle_left','cover_shuffle_right']
 prone=new.startswith('prone_')
 direction=1 if new=='cover_shuffle_left' else -1
 duration=STEP_TIME if lateral else (1.25 if new=='grenade_throw' else float(act.frame_range[1])/24); frames=max(2,round(duration*30))
 contacts=[];foot_travel=[]
 out=bpy.data.actions.new(new);rig.animation_data.action=out
 for frame in range(frames+1):
  # Imported animation keys are 24fps. Evaluate at fractional source frame, then key at 30fps.
  f=(frame/frames)*float(act.frame_range[1]);scene.frame_set(int(f),subframe=f%1)
  for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
  bpy.context.view_layer.update()
  rootdelta=src.pose.bones['Root'].head-src.data.bones['Root'].head_local
  # Original locomotion in the public viewer is in-place. These calibrated root tracks are our derivative.
  speed={'rifle_walk_rm':1.0,'rifle_jog_rm':2.2,'rifle_sprint_rm':4.0,'rifle_crouch_rm':.55,'crawl':.5}.get(new,0)
  rootdelta=Vector(rootdelta)*ratio;rootdelta.y-=speed*frame/30
  lateral_root=direction*STEP*ease(frame/frames) if lateral else 0.0
  rootdelta.x+=lateral_root
  rig.pose.bones['Root'].location=rest['Root'].to_3x3().inverted()@rootdelta
  bpy.context.view_layer.update()
  for target,source in mapnames.items():
   if source not in src.pose.bones:continue
   sp=src.pose.bones[source];sr=src.data.bones[source].matrix_local
   pb=rig.pose.bones[target];m=pb.matrix.copy();pos=m.translation
   q=(sp.matrix.to_quaternion()@sr.to_quaternion().inverted())@rest[target].to_quaternion()
   if target=='Hips':pos=rest[target].translation+(sp.head-sr.translation)*ratio+Vector((lateral_root,-speed*frame/30,0))
   pb.matrix=Matrix.LocRotScale(pos,q,Vector((1,1,1)));bpy.context.view_layer.update()
  # Combat half-crouch: pelvis stays over a staggered support polygon, chest remains up.
  # The previous Crouch_Idle torso plus standing feet produced a backward chair pose.
  combat_crouch=lateral or new in ['cover_idle','cover_peek_left','cover_peek_right','crouch_reload','rifle_crouch_rm','cover_enter','cover_exit']
  source_feet={side:rig.pose.bones[side+'Foot'].head.copy() for side in ['Left','Right']}
  if combat_crouch:
   phase=frame/frames;breath=.006*math.sin(2*math.pi*phase)
   hip=rig.pose.bones['Hips'];crouch_weight=ease(phase) if new=='cover_enter' else (1-ease(phase) if new=='cover_exit' else 1)
   pos=Vector((lateral_root,.015+rootdelta.y,1.025-.265*crouch_weight+breath))
   hip.matrix=Matrix.LocRotScale(pos,Quaternion((1,0,0),.12)@rest['Hips'].to_quaternion(),Vector((1,1,1)));bpy.context.view_layer.update()
   for name in ['Spine','Spine1','Spine2','Neck','Head','LeftShoulder','RightShoulder']:
    pb=rig.pose.bones[name];pb.matrix=Matrix.LocRotScale(pb.head.copy(),Quaternion((1,0,0),.12)@idle_q[name],Vector((1,1,1)));bpy.context.view_layer.update()
  if not prone and new not in ['roll_rm','crawl','death','pistol_fire','grenade_throw']:
   chest=rig.pose.bones['Spine2'].head.copy();z=chest.z+.025
   lean=0
   if new.startswith('cover_peek'):lean=(.055 if new.endswith('left') else -.055)*math.sin(math.pi*frame/frames)**2
   hip=rig.pose.bones['Hips'];hip.location.x+=lean;bpy.context.view_layer.update();chest=rig.pose.bones['Spine2'].head.copy()
   dy=rootdelta.y
   if new=='rocket_aim':
    arm('Right',(chest.x-.075,chest.y-.20,z+.04));arm('Left',(chest.x-.01,chest.y-.39,z+.04))
   else:
    arm('Right',(chest.x-.075,chest.y-.22,z));arm('Left',(chest.x-.06,chest.y-.40,z+.015))
  if prone:
   chest=rig.pose.bones['Spine2'].head.copy()
   recoil=.035*max(0,1-frame/5) if new=='prone_fire' else 0
   reload_offset=.13*math.sin(math.pi*frame/frames)**2 if new=='prone_reload' else 0
   arm('Right',(chest.x-.075,chest.y-.22+recoil,chest.z+.035))
   arm('Left',(chest.x-.06,chest.y-.39+reload_offset,chest.z+.05))
  if new in ['bayonet','rifle_fire','crouch_reload','reload']:
   chest=rig.pose.bones['Spine2'].head.copy();t=frame/frames
   thrust=.075*math.sin(math.pi*t)**4 if new=='bayonet' else (-.035*max(0,1-frame/5) if new=='rifle_fire' else 0)
   reload_offset=.14*math.sin(math.pi*t)**2 if new in ['crouch_reload','reload'] else 0
   arm('Right',(chest.x-.075,chest.y-.22-thrust,chest.z+.025))
   arm('Left',(chest.x-.06,chest.y-.40-thrust+reload_offset,chest.z+.04))
  if new=='grenade_throw':
   chest=rig.pose.bones['Spine2'].head.copy();t=frame/frames
   stops=[(0,Vector((-.15,-.20,-.06))),(.32,Vector((-.22,.06,.26))),(.50,Vector((-.14,-.42,.16))),(.72,Vector((-.12,-.36,-.12))),(1,Vector((-.15,-.20,-.06)))]
   for i in range(len(stops)-1):
    if stops[i][0]<=t<=stops[i+1][0]:
     u=(t-stops[i][0])/(stops[i+1][0]-stops[i][0]);u=u*u*(3-2*u);hand=chest+stops[i][1].lerp(stops[i+1][1],u);break
   arm('Right',hand);arm('Left',chest+Vector((.19,-.22,-.19)))
  # Look down the weapon instead of carrying a crawl/hanging-head pose into aiming.
  if new not in ['roll_rm','crawl','death','hit','grenade_throw']:
   if prone:
    pb=rig.pose.bones['Neck'];pb.matrix=Matrix.LocRotScale(pb.head.copy(),Quaternion((1,0,0),.5)@rest['Neck'].to_quaternion(),Vector((1,1,1)));bpy.context.view_layer.update()
   pb=rig.pose.bones['Head'];pb.matrix=Matrix.LocRotScale(pb.head.copy(),Quaternion((1,0,0),.08)@rest['Head'].to_quaternion(),Vector((1,1,1)));bpy.context.view_layer.update()
  phase=frame/frames
  if combat_crouch:
   for side in ['Left','Right']:
    goal=foot_base[side].copy()
    if new=='rifle_crouch_rm':
     goal=source_feet[side];goal.z=max(foot_base[side].z,goal.z)
    if lateral:
     leading=(side=='Left')==(direction>0)
     start,end=(.06,.44) if leading else (.55,.93)
     u=max(0,min(1,(phase-start)/(end-start)))
     goal.x+=direction*STEP*ease(u)
     goal.z+=.10*math.sin(math.pi*u)**2
    leg(side,goal)
  heights=[rig.pose.bones[side+'Foot'].head.z for side in ['Left','Right']]
  foot_travel.append([rig.pose.bones[side+'Foot'].head.y+speed*frame/30 for side in ['Left','Right']])
  if lateral:
   contacts.append([not(.06<phase<.44),not(.55<phase<.93)] if direction>0 else [not(.55<phase<.93),not(.06<phase<.44)])
  else:contacts.append(heights)
  for pb in rig.pose.bones:
   pb.keyframe_insert('location',frame=frame);pb.keyframe_insert('rotation_quaternion',frame=frame)
 # Fit the root stride to the authored support-foot speed, not an arbitrary world speed.
 fit={}
 if new in ['rifle_walk_rm','rifle_jog_rm','rifle_sprint_rm']:
  mins=[min(h[i] for h in contacts) for i in range(2)]
  velocities=[(foot_travel[f][i]-foot_travel[f-1][i])*30 for f in range(1,frames+1) for i in range(2) if contacts[f][i]<mins[i]+.04 and contacts[f-1][i]<mins[i]+.04 and (foot_travel[f][i]-foot_travel[f-1][i])*30>.15]
  if not velocities:raise RuntimeError('No support-foot samples for '+new)
  fitted=statistics.median(velocities);fit={'support_samples':len(velocities),'old_speed':speed,'fitted_speed':fitted,'game_speed':fitted*.075}
  speed=fitted
  for frame in range(frames+1):
   scene.frame_set(frame);rig.pose.bones['Root'].location=rest['Root'].to_3x3().inverted()@Vector((0,-speed*frame/30,0));rig.pose.bones['Root'].keyframe_insert('location',frame=frame)
 rig.animation_data.action=None
 tr=rig.animation_data.nla_tracks.new();tr.name=new;strip=tr.strips.new(new,0,out);tr.mute=True
 if not lateral:
  mins=[min(x[i] for x in contacts) for i in range(2)]
  contacts=[[x[i]<=mins[i]+.027 for i in range(2)] for x in contacts]
  if fit:
   # A low swinging foot is not planted. Require backward travel near stance speed.
   for f in range(len(contacts)):
    a=max(0,f-1);b=min(frames,f+1)
    for i in range(2):
     velocity=(foot_travel[b][i]-foot_travel[a][i])*30/max(1,b-a)
     contacts[f][i]=contacts[f][i] and speed*.55<velocity<speed*1.6
 # Retargeting preserves joints, not the source mannequin's sole height.
 # Ground the actual deformed mesh (boot sole / prone support), after root extraction.
 rig.animation_data.action=out
 rig.animation_data.action_slot=out.slots[0]
 sole_heights=[]
 for sample in range(frames+1):
  scene.frame_set(sample);bpy.context.view_layer.update()
  deps=bpy.context.evaluated_depsgraph_get()
  low=min((o.matrix_world@v.co).z for original in meshes for o in [original.evaluated_get(deps)] for v in o.data.vertices)
  sole_heights.append(low-rig.pose.bones['Root'].head.z)
 corrections=[-h for h in sole_heights]
 if new in ['rifle_jog_rm','rifle_sprint_rm']:
  # Keep genuine running flight. Interpolate the support correction across the air phase.
  support=[i for i in range(frames) if any(contacts[i])]
  if not support:raise RuntimeError('No ground support for '+new)
  wrapped=[i-frames for i in support]+support+[i+frames for i in support]
  for i in range(frames+1):
   left=max(j for j in wrapped if j<=i);right=min(j for j in wrapped if j>=i)
   weight=0 if left==right else (i-left)/(right-left)
   offset=-(sole_heights[left%frames]*(1-weight)+sole_heights[right%frames]*weight)
   corrections[i]=max(offset,-sole_heights[i])
 for sample,offset in enumerate(corrections):
  scene.frame_set(sample)
  hip=rig.pose.bones['Hips'];pose=hip.matrix.copy();pose.translation.z+=offset;hip.matrix=pose
  hip.keyframe_insert('location',frame=sample)
 rig.animation_data.action=None
 ground_fit={'method':'deformed_mesh_support','before_min_m':min(sole_heights)*.075,'before_max_m':max(sole_heights)*.075,'max_correction_m':max(abs(x) for x in corrections)*.075,'running_flight_preserved':new in ['rifle_jog_rm','rifle_sprint_rm']}
 gait['clips'][new]={'duration':frames/30,'ground_fit':ground_fit,'stride_fit':fit,'contacts':contacts,'loop':new in ['rifle_idle','rifle_walk_rm','rifle_jog_rm','rifle_sprint_rm','rifle_crouch_rm','cover_idle','rocket_aim','crawl','prone_idle'],'root_displacement':[direction*STEP*.075 if lateral else 0,0,speed*frames/30*.075]}
 baked.append(out);catalog.append({'name':new,'source_clip':old,'contact_authored':lateral,'duration':frames/30,'root_motion':'contact-authored finite step' if lateral else 'calibrated derivative' if speed else ('author' if '_rm' in new else 'none')})
 print('BAKED',new,flush=True)
# Remove the source mannequin from the derived scene; preserve separate original GLB.
for o in list(bpy.data.objects):
 if o not in before:bpy.data.objects.remove(o,do_unlink=True)
for a in list(bpy.data.actions):
 if a not in baked and a.users==0:bpy.data.actions.remove(a)
for tr in rig.animation_data.nla_tracks:tr.mute=False
rig.animation_data.action=None
for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
scene.frame_set(0)
bpy.ops.object.select_all(action='DESELECT');rig.select_set(True)
for o in meshes:o.select_set(True)
bpy.ops.wm.save_as_mainfile(filepath=str(R/'source/latest/toy-soldier-retarget.blend'))
bpy.ops.export_scene.gltf(filepath=str(R/'assets/models/toy-soldier.glb'),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='NLA_TRACKS',export_force_sampling=True,export_nla_strips=True)
(R/'docs/animation-catalog.json').write_text(json.dumps(catalog,indent=2))

(R/'data/gait.json').write_text(json.dumps(gait,indent=2))
(R/'docs/evidence/anatomy/bake-reach.json').write_text(json.dumps({'samples':len(reach_audit),'max_requested_reach_correction_m':max(x['correction'] for x in reach_audit),'corrections_over_2cm':sum(x['correction']>.02 for x in reach_audit),'worst':sorted(reach_audit,key=lambda x:x['correction'],reverse=True)[:20]},indent=2))
