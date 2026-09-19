"""CC0 derived geometry; keep armatures/animations and silhouette. Run with Blender."""
import bpy, pathlib, json, struct, shutil
R=pathlib.Path(__file__).resolve().parents[2]
D=R/'source/optimization'; (D/'originals').mkdir(exist_ok=True)
rows=[]
def audit(p):
 b=p.read_bytes();n=struct.unpack_from('<I',b,12)[0];j=json.loads(b[20:20+n]);return {'bytes':len(b),'triangles':sum(j['accessors'][v['indices']]['count']//3 for m in j.get('meshes',[]) for v in m['primitives']),'surfaces':sum(len(m['primitives']) for m in j.get('meshes',[])),'animations':len(j.get('animations',[]))}
for name in ['rifle','pistol','grenade','rocket','tank','sandbag']:
 p=R/'assets/models'/f'{name}.glb'; original=D/'originals'/p.name
 if not original.exists():shutil.copy2(p,original)
 before=audit(original);bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(original))
 meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
 mat=bpy.data.materials.new('FactionPlastic' if name!='sandbag' else 'SandCanvas');mat.diffuse_color=(.3,.4,.2,1) if name!='sandbag' else (.56,.49,.31,1);mat.use_nodes=True;bs=mat.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=mat.diffuse_color;bs.inputs['Roughness'].default_value=.32 if name!='sandbag' else .85
 for o in meshes:
  o.data.materials.clear();o.data.materials.append(mat)
  for poly in o.data.polygons:poly.material_index=0
 # Static pieces can share a single draw. Armatures and tank gun remain separate.
 if name in ['rocket','sandbag']:
  bpy.ops.object.select_all(action='DESELECT')
  for o in meshes:o.select_set(True)
  bpy.context.view_layer.objects.active=meshes[0];bpy.ops.object.join()
 bpy.ops.wm.save_as_mainfile(filepath=str(D/f'{name}-optimized.blend'))
 bpy.ops.export_scene.gltf(filepath=str(p),export_format='GLB',export_animations=True,export_animation_mode='ACTIONS',export_yup=True)
 rows.append({'asset':name,'before':before,'after':audit(p)})
 # Godot import generates per-mesh LODs automatically; source remains full resolution.
(R/'docs/evidence/optimization/meshes.json').write_text(json.dumps(rows,indent=2))
