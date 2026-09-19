# -*- coding: utf-8 -*-
"""CC0 Quaternius Casual Character; original authored seated office loop."""
import bpy,math,json,pathlib
from mathutils import Vector,Matrix,Quaternion
R=pathlib.Path(__file__).resolve().parents[3];S=pathlib.Path(__file__).resolve().parent
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(S/'casual-original.glb'))
rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');rig.animation_data_clear()
for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
bpy.context.view_layer.update()
meshes=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.name.startswith('Casual')]
worlds={o:o.matrix_world.copy() for o in meshes};world=rig.matrix_world.copy()
rig.parent=None;rig.data.transform(world);rig.matrix_world=Matrix.Identity(4);rig.name='OfficeWorkerRig'
for o in meshes:
 o.parent=None;o.data.transform(worlds[o]);o.matrix_world=Matrix.Identity(4);o.parent=rig;o.matrix_parent_inverse=Matrix.Identity(4)
for o in list(bpy.context.scene.objects):
 if o not in meshes+[rig]:bpy.data.objects.remove(o,do_unlink=True)
for a in list(bpy.data.actions):bpy.data.actions.remove(a)
# Normalize standing height while preserving bind matrices and weights.
lo=min(v.co.z for o in meshes for v in o.data.vertices);hi=max(v.co.z for o in meshes for v in o.data.vertices)
f=1.72/(hi-lo);T=Matrix.Rotation(math.pi,4,'Z')@Matrix.Scale(f,4)@Matrix.Translation((0,0,-lo))
rig.data.transform(T)
for o in meshes:o.data.transform(T)
# Retain material separation; fit a muted office palette under existing lights.
palette={'LightBrown':(.24,.34,.28,1),'LightBlue':(.16,.20,.21,1),'Red_Dark':(.10,.13,.12,1),'White':(.46,.47,.40,1),'Hair':(.095,.068,.047,1),'Skin':(.58,.40,.27,1),'Skin_Darker':(.40,.24,.15,1),'Eyebrows':(.10,.064,.044,1),'Eye':(.022,.029,.025,1)}
for mat in bpy.data.materials:
 if mat.name in palette:
  mat.diffuse_color=palette[mat.name];mat.use_nodes=True
  bs=mat.node_tree.nodes.get('Principled BSDF')
  for link in list(mat.node_tree.links):mat.node_tree.links.remove(link)
  mat.node_tree.links.new(bs.outputs['BSDF'],mat.node_tree.nodes.get('Material Output').inputs['Surface'])
  bs.inputs['Base Color'].default_value=palette[mat.name];bs.inputs['Roughness'].default_value=.78
rest={b.name:b.matrix_local.copy() for b in rig.data.bones}
points={b.name:b.head_local.copy() for b in rig.data.bones}
for pb in rig.pose.bones:pb.rotation_mode='QUATERNION'
def world_pose(name,head,q):
 rig.pose.bones[name].matrix=Matrix.LocRotScale(Vector(head),q,Vector((1,1,1)));bpy.context.view_layer.update()
def segment(name,child,head,end):
 q=(points[child]-points[name]).normalized().rotation_difference((Vector(end)-Vector(head)).normalized())@rest[name].to_quaternion()
 world_pose(name,head,q)
def solve(a,b,end_name,target,pole):
 head=rig.pose.bones[a].head.copy();target=Vector(target)
 l1=(points[b]-points[a]).length;l2=(points[end_name]-points[b]).length
 v=target-head;d=v.normalized();dist=min(v.length,l1+l2-.0005)
 along=(l1*l1-l2*l2+dist*dist)/(2*dist)
 p=Vector(pole);p=(p-d*p.dot(d)).normalized()
 joint=head+d*along+p*math.sqrt(max(0,l1*l1-along*along))
 segment(a,b,head,joint);segment(b,end_name,joint,head+d*dist)
 return head+d*dist
scene=bpy.context.scene;scene.render.fps=24;scene.frame_start=0;scene.frame_end=192
rig.animation_data_create();act=bpy.data.actions.new('office_typing');rig.animation_data.action=act
for frame in range(0,193,4):
 scene.frame_set(frame);t=frame/192;wave=math.sin(t*math.tau)
 for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
 bpy.context.view_layer.update()
 world_pose('Body',points['Body']+Vector((-.025,0,-.304+.0015*wave)),rest['Body'].to_quaternion())
 world_pose('Hips',rig.pose.bones['Hips'].head,Quaternion((1,0,0),-.19)@rest['Hips'].to_quaternion())
 world_pose('Head',rig.pose.bones['Head'].head,Quaternion((0,0,1),.07+.025*math.sin(t*math.tau))@Quaternion((1,0,0),-.29+.008*wave)@rest['Head'].to_quaternion())
 for side,x in [('L',-.125),('R',.125)]:
  foot=Vector((x,.40 if side=='L' else .34,.024))
  solve('UpperLeg.'+side,'LowerLeg.'+side,'Foot.'+side,foot,(0,1,0))
  world_pose('Foot.'+side,foot,rest['Foot.'+side].to_quaternion())
  wrist=Vector((-.23+.002*wave,.510,.882+.0012*math.sin(t*math.tau*6))) if side=='L' else Vector((.17+.002*math.sin(t*math.tau),.505+.0015*wave,.883))
  wrist=solve('UpperArm.'+side,'LowerArm.'+side,'Wrist.'+side,wrist,(-1 if side=='L' else 1,-.35,-.6))
  segment('Wrist.'+side,'Index2.'+side,wrist,wrist+Vector((0,.12,-.022)))
  for finger in ['Index','Middle','Ring','Pinky']:
   for k in [2,3]:
    pb=rig.pose.bones.get(finger+str(k)+'.'+side)
    if pb:
     amount=(.22 if k==2 else .18) if side=='L' else (.40 if k==2 else .25)
     world_pose(pb.name,pb.head,Quaternion((1,0,0),-amount-.025*math.sin(t*math.tau*6+(0 if finger=='Index' else 1.5)))@pb.matrix.to_quaternion())
 for pb in rig.pose.bones:
  pb.keyframe_insert('location',frame=frame);pb.keyframe_insert('rotation_quaternion',frame=frame);pb.keyframe_insert('scale',frame=frame)
track=rig.animation_data.nla_tracks.new();track.name='office_typing';strip=track.strips.new('office_typing',0,act);rig.animation_data.action=None
scene.frame_set(0)
bpy.ops.wm.save_as_mainfile(filepath=str(S/'office-worker.blend'))
bpy.ops.export_scene.gltf(filepath=str(S/'office-worker.glb'),export_format='GLB',export_animations=True,export_animation_mode='NLA_TRACKS',export_yup=True)
(S/'animation.json').write_text(json.dumps({'clip':'office_typing','duration':8,'fps':24,'loop':True,'root_motion':'in_place','author':'Deskfront original pose animation','source_rig_bones':len(rig.data.bones),'target_tracks':'all source rig bones','standing_height':1.72,'position_godot':[-1.12,0,.57]},indent=2))
