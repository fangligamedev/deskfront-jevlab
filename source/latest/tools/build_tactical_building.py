"""Editable Blender companion derived from the exact runtime component manifest."""
import bpy,json,pathlib
R=pathlib.Path(__file__).resolve().parents[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
for p in json.loads((R/'building-components.json').read_text())['parts']:
 x,y,z=p['position'];w,h,d=p['size']
 bpy.ops.mesh.primitive_cube_add(size=1,location=(x,-z,y))
 o=bpy.context.object;o.name=p['id'];o.scale=(w,d,h);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 mat=bpy.data.materials.new(p['id']);mat.diffuse_color=(*p['color'],1);o.data.materials.append(mat);o['destructible']=p['destructible']
bpy.ops.wm.save_as_mainfile(filepath=str(R/'tactical-building.blend'))
