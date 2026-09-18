"""Original CC0 models. Run: blender -b --python source/blender/build_assets.py
Coordinates of environment helpers are Godot meters (+Y up, -Z forward).
Rig authored Z-up in Blender; glTF exporter performs the axis conversion.
"""
import bpy, math, random, pathlib, json, sys
from mathutils import Vector, Matrix
ROOT=pathlib.Path(__file__).resolve().parents[3]
OUT=ROOT/'source/latest'/'sandbox-generated'
OUT.mkdir(parents=True,exist_ok=True)
random.seed(18)

def clear():
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
    for a in list(bpy.data.actions): bpy.data.actions.remove(a)

def material(name, color, rough=.65, metal=0):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Roughness'].default_value=rough; p.inputs['Metallic'].default_value=metal
    return m

def finish(o,name,mat):
    o.name=name; o.data.materials.append(mat)
    return o

def box(name,p,d,m,bevel=.01):
    bpy.ops.mesh.primitive_cube_add(size=1, location=p); o=bpy.context.object; o.dimensions=d
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        mod=o.modifiers.new('soft molded edges','BEVEL'); mod.width=bevel; mod.segments=2
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return finish(o,name,m)

def uv(name,p,d,m):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=8,location=p);o=bpy.context.object;o.scale=d
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    for f in o.data.polygons:f.use_smooth=True
    return finish(o,name,m)

def cyl(name,p,r,depth,m):
    bpy.ops.mesh.primitive_cylinder_add(vertices=20,radius=r,depth=depth,location=p)
    return finish(bpy.context.object,name,m)

def g(p):return (p[0],-p[2],p[1])
def gb(name,p,d,m,b=.007):return box(name,g(p),(d[0],d[2],d[1]),m,b)
def gc(name,p,r,h,m):return cyl(name,g(p),r,h,m)
def gu(name,p,d,m):return uv(name,g(p),(d[0],d[2],d[1]),m)
def rod(name,a,b,r,m):
    a,b=Vector(g(a)),Vector(g(b));v=b-a
    o=cyl(name,(a+b)/2,r,v.length,m);o.rotation_euler=v.to_track_quat('Z','Y').to_euler();return o

def join_materials(objects=None):
    groups={};result=[]
    for o in (list(bpy.context.scene.objects) if objects is None else objects):
        if o.type=='MESH':groups.setdefault(o.data.materials[0].name,[]).append(o)
    for name,objs in groups.items():
        bpy.ops.object.select_all(action='DESELECT')
        for o in objs:o.select_set(True)
        bpy.context.view_layer.objects.active=objs[0];bpy.ops.object.join();objs[0].name=name;result.append(objs[0])
    return result

def save(name):
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/(name+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',export_animations=True,export_animation_mode='NLA_TRACKS',export_yup=True)

def office():
    clear()
    sage=material('sage painted steel',(.34,.43,.39));wall=material('aged mint plaster',(.65,.73,.65))
    white=material('warm gray laminate',(.68,.71,.65));wood=material('oak edging',(.33,.24,.13))
    cream=material('yellowed ABS',(.64,.65,.49));black=material('charcoal',(.045,.065,.061))
    paper=material('paper',(.79,.80,.7));brass=material('brass',(.45,.32,.12),.4,.5)
    carpet=material('ochre carpet',(.32,.30,.18));brown=material('archive cardboard',(.43,.32,.21))
    red=material('rust enamel',(.42,.20,.14));blue=material('blue book',(.11,.26,.36));screen=material('CRT dark glass',(.045,.12,.13),.25)
    greenlight=material('phosphor',(.30,.55,.39))
    gb('floor',(-.30,-.035,1.30),(5.4,.06,5.6),carpet)
    gb('back wall',(-.30,1.1,-1.43),(5.34,2.2,.065),wall)
    gb('left wall',(-2.96,1.1,1.30),(.06,2.2,5.52),wall)
    gb('wall trim',(-.30,.85,-1.385),(5.25,.055,.025),sage)
    gb('left wall trim',(-2.92,.85,1.30),(.025,.055,5.44),sage)
    # L desk main slab and return
    for name,p,d in [('desk right',(.54,.79,1.40),(1.91,.06,4.40)),('desk left',(-1.54,.79,-.26),(2.23,.06,1.08))]:
        gb(name+' edge',(p[0],p[1]-.022,p[2]),(d[0]+.018,.055,d[2]+.018),wood)
        gb(name,p,d,white)
    for x in [-2.35,1.19]:
        gb('pedestal',(x,.39,.14),(.43,.74,.50),sage)
        for j in range(3):
            y=.14+j*.235
            gb('drawer',(x,y,.405),(.395,.20,.025),sage)
            gb('label holder',(x-.095,y+.03,.423),(.115,.037,.01),brass)
            gb('label',(x-.095,y+.03,.430),(.085,.022,.005),paper)
            rod('drawer handle',(x+.02,y+.02,.44),(x+.13,y+.02,.44),.007,brass)
    # New front legs and apron support the extended tabletop.
    for x in [-.30,1.38]:
        gb('front leg',(x,.38,3.43),(.075,.76,.075),sage)
    gb('front apron',(.54,.71,3.43),(1.75,.12,.045),sage)
    # Cabinet moves left with the expanded office; preserve its proportions.
    cabinet_before=set(bpy.context.scene.objects)
    # tall filing cabinet
    gb('filing cabinet',(-1.40,.62,.79),(.47,1.24,.5),sage)
    for j in range(4):
        gb('file drawer',(-1.4,.18+j*.29,1.05),(.43,.25,.025),sage)
        gb('file label',(-1.49,.22+j*.29,1.068),(.11,.04,.006),brass)
        rod('file pull',(-1.37,.22+j*.29,1.085),(-1.25,.22+j*.29,1.085),.008,brass)
    for obj in set(bpy.context.scene.objects)-cabinet_before:obj.location.x-=.90
    computer_before=set(bpy.context.scene.objects)
    # CRT computer on left workspace, screen faces +Z
    gb('computer base',(-.95,.865,-.42),(.50,.09,.40),cream)
    gb('CRT housing',(-.95,1.095,-.47),(.46,.39,.36),cream,.035)
    gb('CRT bezel',(-.95,1.09,-.275),(.425,.33,.045),cream,.018)
    gb('CRT display',(-.95,1.10,-.248),(.35,.25,.008),screen,.008)
    for i in range(13):gb('code on CRT',(-1.07+random.random()*.03,1.195-i*.016,-.242),(.11+random.random()*.15,.003,.002),greenlight,.0)
    for i in range(13):gb('vent',(-1.15+i*.023,.89,-.207),(.008,.035,.004),sage,0)
    gc('power lamp',(-.745,.924,-.245),.006,.003,greenlight)
    gb('keyboard',(-.90,.84,.00),(.46,.028,.18),cream)
    for r in range(5):
        for c in range(15):gb('key',(-1.11+c*.028,.859,-.065+r*.027),(.023,.01,.021),paper,.002)
    gb('spacebar',(-.92,.865,.064),(.14,.009,.018),paper,.002)
    gb('mouse pad',(-.50,.824,.01),(.21,.005,.20),sage)
    gu('mouse',(-.50,.846,.00),(.037,.020,.057),cream)
    gb('telephone',(-1.30,.86,-.01),(.18,.06,.21),cream)
    gb('receiver',(-1.30,.915,-.025),(.22,.045,.063),sage)
    for r in range(3):
        for c in range(3):gb('phone key',(-1.34+c*.035,.898,.04+r*.025),(.019,.008,.014),paper,.001)
    for obj in set(bpy.context.scene.objects)-computer_before:obj.location.x-=.45
    # articulated desk lamp
    gc('lamp base',(.29,.834,-.57),.092,.026,black)
    rod('lamp lower',(.29,.85,-.57),(.43,1.13,-.68),.012,black)
    rod('lamp upper',(.43,1.13,-.68),(.17,1.29,-.60),.010,black)
    gc('lamp shade',(.17,1.25,-.60),.055,.09,black)
    gc('lamp inner',(.17,1.206,-.60),.042,.004,paper)
    # loose cable as series of links
    for i in range(24):
        t=i/24*math.pi*2;tt=(i+1)/24*math.pi*2
        rod('lamp cable',(.22+.22*math.cos(t),.825,-.75+.09*math.sin(t)),(.22+.22*math.cos(tt),.825,-.75+.09*math.sin(tt)),.003,black)
    for i in range(3):gb('book',(-.09,.836+i*.022,-.51),(.16,.021,.22),[red,paper,blue][i])
    gc('mug',(-.42,.878,-.36),.039,.105,cream);gc('coffee',(-.42,.933,-.36),.032,.002,black)
    for i in range(12):
        a=i*math.tau/12;b=(i+1)*math.tau/12
        rod('cup handle',(-.462,.88+.027*math.cos(a),-.36+.027*math.sin(a)),(-.462,.88+.027*math.cos(b),-.36+.027*math.sin(b)),.007,cream)
    gc('pen cup',(-.60,.88,-.55),.035,.12,sage)
    for i in range(6):rod('pen',(-.62+i*.007,.85,-.55),(-.64+i*.014,1.04,-.55+random.uniform(-.02,.02)),.003,black)
    gb('tape base',(-.40,.84,-.57),(.12,.038,.08),black)
    gc('tape roll',(-.40,.884,-.57),.038,.026,cream)
    gb('sharpener',(.84,.869,-.46),(.12,.10,.12),sage)
    # paper trays, original style
    for x,z,m in [(1.23,-.53,sage),(1.23,-.14,red)]:
        gb('tray base',(x,.827,z),(.34,.013,.30),m)
        for dx in [-.165,.165]:gb('tray side',(x+dx,.857,z),(.014,.065,.30),m)
        gb('tray back',(x,.857,z-.15),(.34,.065,.012),m)
        for j in range(4):gb('documents',(x,.84+j*.002,z),(.29,.001,.26),paper,.001)
        for j in range(11):gb('printed rule',(x,.849,z-.09+j*.014),(.22,.001,.0015),sage,0)
    # chairs, boxes, frames
    for x,z in [(-1.10,.64),(1.96,2.85)]:
        gb('chair cushion',(x,.46,z),(.43,.10,.39),sage,.04)
        gb('chair back',(x,.71,z+.18),(.43,.43,.10),sage,.05)
        gc('chair pole',(x,.23,z),.028,.38,black)
        for i in range(5):
            a=i*math.tau/5;end=(x+math.cos(a)*.30,.07,z+math.sin(a)*.30)
            rod('chair leg',(x,.10,z),end,.02,black);gu('wheel',end,(.025,.035,.038),black)
    for x,z,y in [(-2.25,1.40,.14),(-2.12,2.10,.13),(1.92,1.10,.16),(1.95,1.10,.46),(-2.3,.78,1.36)]:
        gb('archive box',(x,y,z),(.32,.27,.29),brown)
        gb('box lid',(x,y+.14,z),(.34,.025,.31),brown)
        gb('archive label',(x,y+.02,z+.148),(.13,.048,.002),paper,0)
    for x,y,w,h in [(1.05,1.65,.48,.32),(-.9,1.53,.25,.18)]:
        gb('picture frame',(x,y,-1.382),(w,.018,h),wood) if False else None
        gb('picture frame',(x,y,-1.382),(w,h,.018),wood)
        gb('picture mat',(x,y,-1.369),(w-.025,h-.025,.005),paper)
        gb('picture sky',(x,y+.025,-1.364),(w-.065,h-.075,.003),blue)
        gb('picture meadow',(x,y-.06,-1.362),(w-.065,.07,.003),sage)
    for i in range(3):gb('pinned note',(-1.3+i*.24,1.02,-1.377),(.13,.15,.003),paper)
    save('office-sandbox-editable')
    join_materials();save('office-sandbox')


office()
