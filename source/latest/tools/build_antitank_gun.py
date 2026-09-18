"""Original CC0 toy field gun. Metres, Blender +Y / Godot -Z forward."""
import bpy, math, pathlib
from mathutils import Vector
R=pathlib.Path(__file__).resolve().parents[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
mat=bpy.data.materials.new('Green molded plastic');mat.diffuse_color=(.35,.486,.231,1);mat.use_nodes=True
bs=mat.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=mat.diffuse_color;bs.inputs['Roughness'].default_value=.32

def finish(o,name,bevel=.0015,parent=None):
 o.name=name;o.data.materials.append(mat)
 if bevel:
  mod=o.modifiers.new('Molded edges','BEVEL');mod.width=bevel;mod.segments=3
 mod=o.modifiers.new('Weighted normals','WEIGHTED_NORMAL')
 if parent:o.parent=parent
 return o

def box(name,pos,size,parent=None):
 bpy.ops.mesh.primitive_cube_add(size=1,location=pos);o=bpy.context.object;o.scale=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 return finish(o,name,parent=parent)

def rod(name,a,b,r,vertices=32,parent=None):
 a,b=Vector(a),Vector(b);d=b-a
 bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=r,depth=d.length,location=(a+b)/2)
 o=bpy.context.object;o.rotation_mode='QUATERNION';o.rotation_quaternion=d.to_track_quat('Z','Y')
 for p in o.data.polygons:p.use_smooth=True
 return finish(o,name,.0008,parent)

# Empty allows recoil without moving wheels / shield.
recoil=bpy.data.objects.new('Recoil',None);bpy.context.collection.objects.link(recoil)
box('Breech',(0,.012,.112),(.029,.052,.028),recoil)
rod('Barrel',(0,.03,.113),(0,.198,.113),.009,parent=recoil)
rod('Recoil cylinder',(0,.025,.100),(0,.120,.100),.006,parent=recoil)
# Open muzzle: actual annulus, recessed bore.
n=32;verts=[]
for y,r in [(.186,.014),(.208,.014),(.208,.008),(.186,.008)]:
 verts += [(math.cos(i*2*math.pi/n)*r,y,.113+math.sin(i*2*math.pi/n)*r) for i in range(n)]
faces=[]
for ring in range(4):
 for i in range(n):faces.append((ring*n+i,ring*n+(i+1)%n,((ring+1)%4)*n+(i+1)%n,((ring+1)%4)*n+i))
mesh=bpy.data.meshes.new('Muzzle annulus');mesh.from_pydata(verts,[],faces);mesh.update();o=bpy.data.objects.new('Open muzzle brake',mesh);bpy.context.collection.objects.link(o);finish(o,o.name,.0004,recoil)
rod('Bore recess',(0,.183,.113),(0,.185,.113),.008,parent=recoil)
# Low clipped-corner shield; bent upper lip catches the unchanged scene lighting.
outline=[(-.079,.051),(.079,.051),(.079,.120),(.058,.142),(-.058,.142),(-.079,.120)]
verts=[(x,y,z) for y in [.034,.040] for x,z in outline];n=len(outline)
faces=[tuple(range(n-1,-1,-1)),tuple(range(n,n*2))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
mesh=bpy.data.meshes.new('Shield solid');mesh.from_pydata(verts,[],faces);mesh.update();o=bpy.data.objects.new('Low armor shield',mesh);bpy.context.collection.objects.link(o);finish(o,o.name)
rod('Axle',(-.10,0,.045),(.10,0,.045),.008)
box('Carriage',(0,0,.066),(.055,.074,.032))
rod('Elevation pivot',(-.035,.008,.105),(.035,.008,.105),.011)
for s in [-1,1]:
 x=s*.094
 rod('Wheel', (x-.009,0,.045),(x+.009,0,.045),.044,48)
 rod('Wheel hub',(x-s*.012,0,.045),(x+s*.018,0,.045),.018)
 for i in range(12):
  a=i*math.tau/12
  rod('Wheel molded ribs',(x+s*.010,math.cos(a)*.019,.045+math.sin(a)*.019),(x+s*.010,math.cos(a)*.036,.045+math.sin(a)*.036),.0025,12)
 rod('Split trail',(s*.021,-.020,.057),(s*.081,-.177,.014),.010)
 box('Ground spade',(s*.081,-.177,.012),(.045,.024,.018))
 rod('Handle riser',(s*.081,-.139,.019),(s*.081,-.139,.080),.003)
 rod('Trail handle',(s*.068,-.139,.080),(s*.110,-.139,.080),.004)
for x in [-.063,.063]:
 for z in [.063,.112]:rod('Shield rivet',(x,.039,z),(x,.042,z),.0023,12)
rod('Sight post',(-.026,.018,.10),(-.026,.018,.147),.003)
rod('Sight optic',(-.026,.001,.147),(-.026,.037,.147),.006)
rod('Elevation crank',(.037,0,.085),(.053,0,.085),.003)
rod('Crank grip',(.053,0,.085),(.053,-.012,.085),.004)
bpy.ops.wm.save_as_mainfile(filepath=str(R/'antitank-gun.blend'))
bpy.ops.export_scene.gltf(filepath=str(R/'antitank-gun.glb'),export_format='GLB',export_apply=True)
