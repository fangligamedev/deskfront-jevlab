import bpy,pathlib,math
R=pathlib.Path(__file__).resolve().parents[3]
bpy.ops.wm.read_factory_settings(use_empty=True)
mat=bpy.data.materials.new('Single faction plastic');mat.diffuse_color=(.16,.23,.09,1)
def cyl(name,radius,depth,pos,rot=(0,0,0)):
 bpy.ops.mesh.primitive_cylinder_add(vertices=24,radius=radius,depth=depth,location=pos,rotation=rot);o=bpy.context.object;o.name=name;o.data.materials.append(mat);b=o.modifiers.new('Mold bevel','BEVEL');b.width=.006;b.segments=3
 for p in o.data.polygons:p.use_smooth=True
 return o
def box(name,sz,p):
 bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=bpy.context.object;o.name=name;o.scale=sz;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(mat);b=o.modifiers.new('Soft molding','BEVEL');b.width=.009;b.segments=3
# Canonical 0.95m shoulder-launched toy weapon, barrel forward Blender -Y.
cyl('Launch tube',.055,.93,(0,0,0),(math.pi/2,0,0));cyl('Front collar',.072,.07,(0,-.43,0),(math.pi/2,0,0));cyl('Rear vent',.075,.1,(0,.42,0),(math.pi/2,0,0))
box('Trigger grip',(.035,.045,.115),(0,-.10,-.085));box('Shoulder rest',(.08,.22,.025),(0,.13,-.062));box('Sight mount',(.018,.09,.06),(0,-.04,.077));cyl('Optic',.018,.13,(0,-.04,.11),(math.pi/2,0,0))
bpy.ops.wm.save_as_mainfile(filepath=str(R/'source/latest/rocket-launcher.blend'))
bpy.ops.export_scene.gltf(filepath=str(R/'assets/models/rocket.glb'),export_format='GLB',export_apply=True)
