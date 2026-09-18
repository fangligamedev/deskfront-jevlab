"""Original CC0 models. Run: blender -b --python source/blender/build_assets.py
Coordinates of environment helpers are Godot meters (+Y up, -Z forward).
Rig authored Z-up in Blender; glTF exporter performs the axis conversion.
"""
import bpy, math, random, pathlib, json, sys
from mathutils import Vector, Matrix
ROOT=pathlib.Path(__file__).resolve().parents[2]
OUT=ROOT/'source'/'blender'/'generated'
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
    gb('floor',(0,-.035,0),(3.6,.06,3.0),carpet)
    gb('back wall',(0,1.1,-1.07),(3.6,2.2,.065),wall)
    gb('left wall',(-1.72,1.1,.15),(.06,2.2,2.5),wall)
    gb('wall trim',(0,.85,-1.025),(3.5,.055,.025),sage)
    gb('left wall trim',(-1.68,.85,.15),(.025,.055,2.4),sage)
    # L desk main slab and return
    for name,p,d in [('desk right',(.54,.79,-.05),(1.91,.06,1.50)),('desk left',(-.94,.79,-.26),(1.03,.06,1.08))]:
        gb(name+' edge',(p[0],p[1]-.022,p[2]),(d[0]+.018,.055,d[2]+.018),wood)
        gb(name,p,d,white)
    for x in [-1.20,1.19]:
        gb('pedestal',(x,.39,.14),(.43,.74,.50),sage)
        for j in range(3):
            y=.14+j*.235
            gb('drawer',(x,y,.405),(.395,.20,.025),sage)
            gb('label holder',(x-.095,y+.03,.423),(.115,.037,.01),brass)
            gb('label',(x-.095,y+.03,.430),(.085,.022,.005),paper)
            rod('drawer handle',(x+.02,y+.02,.44),(x+.13,y+.02,.44),.007,brass)
    # tall filing cabinet
    gb('filing cabinet',(-1.40,.62,.79),(.47,1.24,.5),sage)
    for j in range(4):
        gb('file drawer',(-1.4,.18+j*.29,1.05),(.43,.25,.025),sage)
        gb('file label',(-1.49,.22+j*.29,1.068),(.11,.04,.006),brass)
        rod('file pull',(-1.37,.22+j*.29,1.085),(-1.25,.22+j*.29,1.085),.008,brass)
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
    for x,z,m in [(1.11,.34,sage),(1.13,.72,red)]:
        gb('tray base',(x,.827,z),(.34,.013,.30),m)
        for dx in [-.165,.165]:gb('tray side',(x+dx,.857,z),(.014,.065,.30),m)
        gb('tray back',(x,.857,z-.15),(.34,.065,.012),m)
        for j in range(4):gb('documents',(x,.84+j*.002,z),(.29,.001,.26),paper,.001)
        for j in range(11):gb('printed rule',(x,.849,z-.09+j*.014),(.22,.001,.0015),sage,0)
    # chairs, boxes, frames
    for x,z in [(-.65,.64),(1.10,1.18)]:
        gb('chair cushion',(x,.46,z),(.43,.10,.39),sage,.04)
        gb('chair back',(x,.71,z+.18),(.43,.43,.10),sage,.05)
        gc('chair pole',(x,.23,z),.028,.38,black)
        for i in range(5):
            a=i*math.tau/5;end=(x+math.cos(a)*.30,.07,z+math.sin(a)*.30)
            rod('chair leg',(x,.10,z),end,.02,black);gu('wheel',end,(.025,.035,.038),black)
    for x,z,y in [(-1.35,1.32,.14),(-.4,1.2,.13),(.67,.91,.16),(.72,.93,.46),(-1.4,.78,1.36)]:
        gb('archive box',(x,y,z),(.32,.27,.29),brown)
        gb('box lid',(x,y+.14,z),(.34,.025,.31),brown)
        gb('archive label',(x,y+.02,z+.148),(.13,.048,.002),paper,0)
    for x,y,w,h in [(1.05,1.65,.48,.32),(-.9,1.53,.25,.18)]:
        gb('picture frame',(x,y,-1.022),(w,.018,h),wood) if False else None
        gb('picture frame',(x,y,-1.022),(w,h,.018),wood)
        gb('picture mat',(x,y,-1.009),(w-.025,h-.025,.005),paper)
        gb('picture sky',(x,y+.025,-1.004),(w-.065,h-.075,.003),blue)
        gb('picture meadow',(x,y-.06,-1.002),(w-.065,.07,.003),sage)
    for i in range(3):gb('pinned note',(-1.3+i*.24,1.02,-1.017),(.13,.15,.003),paper)
    join_materials();save('office')

def rigged(name,human=False,team='green'):
    clear()
    body=material('uniform',(.26,.34,.27) if human else ({'green':(.28,.40,.18),'blue':(.13,.28,.38),'red':(.49,.20,.13)}[team]),.66 if human else .32)
    dark=material('boots and equipment',(.11,.15,.13),.5)
    skin=material('skin',(.52,.34,.22)) if human else body
    hair=material('hair',(.09,.065,.035)) if human else body
    bpy.ops.object.armature_add();rig=bpy.context.object;rig.name='WorkerRig' if human else 'InfantryRig'
    bpy.ops.object.mode_set(mode='EDIT');eb=rig.data.edit_bones;eb.remove(eb[0])
    specs={'root':((0,0,0),(0,0,.2),None),'hips':((0,0,.85),(0,0,1.0),'root'),'spine':((0,0,1.0),(0,0,1.30),'hips'),'neck':((0,0,1.30),(0,0,1.43),'spine'),'head':((0,0,1.43),(0,0,1.69),'neck')}
    for side,s in [('L',1),('R',-1)]:
        specs.update({f'upper_arm.{side}':((s*.23,0,1.29),(s*.34,0,1.04),'spine'),f'forearm.{side}':((s*.34,0,1.04),(s*.35,0,.81),f'upper_arm.{side}'),f'hand.{side}':((s*.35,0,.81),(s*.35,0,.71),f'forearm.{side}'),f'thigh.{side}':((s*.12,0,.86),(s*.13,0,.48),'hips'),f'shin.{side}':((s*.13,0,.48),(s*.13,0,.11),f'thigh.{side}'),f'foot.{side}':((s*.13,0,.11),(s*.13,.16,.07),f'shin.{side}')})
    for n,(h,t,p) in specs.items():
        b=eb.new(n);b.head=h;b.tail=t
        if p:b.parent=eb[p]
    bpy.ops.object.mode_set(mode='OBJECT')
    parts=[]
    def bind(o,bone):
        vg=o.vertex_groups.new(name=bone);vg.add(list(range(len(o.data.vertices))),1,'REPLACE');parts.append(o);return o
    bind(box('jacket',(0,0,1.16),(.44,.23,.38),body,.07),'spine')
    bind(box('pelvis',(0,0,.87),(.30,.23,.19),body,.04),'hips')
    bind(uv('head',(0,0,1.53),(.13,.125,.16),skin),'head')
    bind(uv('nose',(0,.125,1.52),(.035,.05,.04),skin),'head')
    if human:
        bind(uv('hair',(0,-.016,1.62),(.137,.127,.105),hair),'head')
        bind(box('scarf',(0,.03,1.34),(.31,.26,.10),dark,.025),'neck')
    else:
        bind(uv('helmet dome',(0,0,1.65),(.17,.165,.095),body),'head')
        bind(cyl('helmet rim',(0,0,1.62),.18,.022,body),'head')
        bind(box('backpack',(0,-.17,1.16),(.27,.16,.31),body,.035),'spine')
        for x in [-.12,.12]:bind(box('ammo pouch',(x,.145,1.10),(.10,.09,.13),body,.013),'spine')
        bind(box('belt',(0,0,.97),(.34,.255,.045),dark,.008),'hips')
    for side,s in [('L',1),('R',-1)]:
        for bn,a,b,r in [(f'upper_arm.{side}',(s*.24,0,1.28),(s*.34,0,1.04),.080),(f'forearm.{side}',(s*.34,0,1.04),(s*.35,0,.81),.062),(f'thigh.{side}',(s*.12,0,.85),(s*.13,0,.48),.093),(f'shin.{side}',(s*.13,0,.48),(s*.13,0,.14),.070)]:
            a,b=Vector(a),Vector(b);v=b-a;o=cyl(bn,(a+b)/2,r,v.length,body);o.rotation_euler=v.to_track_quat('Z','Y').to_euler();bind(o,bn)
        bind(uv('hand',(s*.35,0,.76),(.064,.065,.076),skin),f'hand.{side}')
        bind(box('boot',(s*.13,.05,.085),(.15,.26,.14),dark if human else body,.025),f'foot.{side}')
    if not human:
        bind(box('rifle stock',(-.35,.025,.73),(.07,.08,.29),body,.009),'hand.R')
        bind(cyl('rifle barrel',(-.35,.025,.47),.019,.26,body),'hand.R')
        bind(box('rifle magazine',(-.35,.095,.66),(.052,.085,.10),body,.007),'hand.R')
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts:o.select_set(True)
    bpy.context.view_layer.objects.active=parts[0];bpy.ops.object.join();mesh=parts[0];mesh.name='SkinnedWorker' if human else 'SkinnedInfantry'
    mod=mesh.modifiers.new('Armature','ARMATURE');mod.object=rig;mesh.parent=rig
    def pose_frame(clip,t):
        wave=math.sin(t*math.tau)
        def bone(n,h,tail):
            h,tail=Vector(h),Vector(tail);rest=rig.data.bones[n]
            direction=tail-h
            q=(rest.tail_local-rest.head_local).rotation_difference(direction)
            basis=q.to_matrix().to_4x4() @ rest.matrix_local.to_quaternion().to_matrix().to_4x4()
            matrix=Matrix.Translation(h) @ basis @ Matrix.Diagonal((1,direction.length/rest.length,1,1))
            rig.pose.bones[n].matrix=matrix
            bpy.context.view_layer.update()
        pelvis=Vector((0,0,.85));up=Vector((0,0,1))
        if clip=='run':pelvis.z+=.018*abs(wave)
        if clip=='crouch':pelvis.z=.57;up=Vector((0,.16,.987))
        if clip=='prone':pelvis.z=.19;up=Vector((0,.97,.243))
        if clip=='death':
            a=min(1,t*1.8)*math.pi/2;pelvis.z=.85-min(1,t*1.8)*.69;up=Vector((0,-math.sin(a),math.cos(a)))
        if clip=='typing':pelvis.z=.57;up=Vector((0,.10,.995))
        bone('root',(0,0,0),(0,0,.2))
        bone('hips',pelvis,pelvis+up*.15)
        bone('spine',pelvis+up*.15,pelvis+up*.45)
        bone('neck',pelvis+up*.45,pelvis+up*.58)
        bone('head',pelvis+up*.58,pelvis+up*.84+Vector((.007*wave,0,0)))
        def arm(side,shoulder,wrist,pole):
            length1=(Vector(specs['upper_arm.'+side][1])-Vector(specs['upper_arm.'+side][0])).length
            length2=(Vector(specs['forearm.'+side][1])-Vector(specs['forearm.'+side][0])).length
            direction=(wrist-shoulder);distance=min(direction.length,length1+length2-.002);direction.normalize()
            wrist=shoulder+direction*distance
            a=(length1**2-length2**2+distance**2)/(2*distance)
            perp=(pole-shoulder)-direction*(pole-shoulder).dot(direction);perp.normalize()
            elbow=shoulder+direction*a+perp*math.sqrt(max(0,length1**2-a*a))
            bone('upper_arm.'+side,shoulder,elbow);bone('forearm.'+side,elbow,wrist)
            handdir=Vector((0,1,0)) if clip not in ['idle','death'] else Vector((0,0,-1))
            bone('hand.'+side,wrist,wrist+handdir*.10)
        for side,sign in [('L',1),('R',-1)]:
            hip=pelvis+Vector((sign*.12,0,.01))
            if clip=='typing':knee=hip+Vector((0,.37,-.035));ankle=knee+Vector((0,.01,-.37))
            elif clip=='crouch':knee=Vector((sign*.13,.24,.34));ankle=Vector((sign*.13,0,.11))
            elif clip=='prone':knee=Vector((sign*.13,-.33,.14));ankle=Vector((sign*.13,-.67,.09))
            elif clip=='death':
                amount=min(1,t*1.8);knee=Vector((sign*.13,.30*amount,.48-.34*amount));ankle=Vector((sign*.13,.66*amount,.11))
            elif clip=='run':
                angle=wave*sign*.55;knee=hip+Vector((0,math.sin(angle)*.38,-math.cos(angle)*.38));a2=angle-max(0,wave*sign)*.6;ankle=knee+Vector((0,math.sin(a2)*.37,-math.cos(a2)*.37))
            else:knee=Vector((sign*.13,0,.48));ankle=Vector((sign*.13,0,.11))
            bone('thigh.'+side,hip,knee);bone('shin.'+side,knee,ankle);bone('foot.'+side,ankle,ankle+Vector((0,.16,-.04)))
            shoulder=pelvis+up*.44+Vector((sign*.23,0,0))
            if clip in ['idle','death']:
                wrist=shoulder+Vector((sign*.12,0,-.46))
            elif clip=='typing':wrist=Vector((sign*.19,.50,.99+.008*wave*sign))
            elif clip=='prone':wrist=Vector((sign*.085,.83,.28))
            else:
                wrist=pelvis+Vector((-.10 if sign<0 else -.06,.35 if sign<0 else .40,.35))
                if clip=='fire':wrist.y-=.035*math.sin(t*math.pi)
                if clip=='reload' and sign>0:wrist+=Vector((0,-.12*math.sin(t*math.pi),-.16*math.sin(t*math.pi)))
            arm(side,shoulder,wrist,shoulder+Vector((sign*.3,.10,-.30)))

    bpy.context.scene.render.fps=24
    clips={'typing':(120,True)} if human else {'idle':(48,True),'run':(24,True),'aim':(48,True),'fire':(10,False),'crouch':(48,True),'prone':(48,True),'reload':(48,False),'death':(30,False)}
    rig.animation_data_create()
    for clip,(length,loop) in clips.items():
        act=bpy.data.actions.new(clip);rig.animation_data.action=act
        for f in range(0,length+1,2):
            t=f/length;wave=math.sin(t*math.tau)
            for pb in rig.pose.bones:pb.rotation_mode='XYZ';pb.rotation_euler=(0,0,0);pb.location=(0,0,0)
            def rot(b,x=0,y=0,z=0):rig.pose.bones[b].rotation_euler=tuple(math.radians(v) for v in (x,y,z))
            def aim():
                rot('upper_arm.L',78,5,-12);rot('forearm.L',-5,0,6);rot('upper_arm.R',72,-8,24);rot('forearm.R',-15,0,-35)
            if clip=='typing':
                rig.pose.bones['hips'].location.y=-.28
                rot('thigh.L',82);rot('thigh.R',82);rot('shin.L',-82);rot('shin.R',-82)
                rot('spine',7);rot('head',2*wave,3*math.sin(t*math.tau))
                rot('upper_arm.L',48+2*wave);rot('upper_arm.R',48-2*wave);rot('forearm.L',28+3*wave);rot('forearm.R',28-3*wave)
            elif clip=='run':
                rot('thigh.L',34*wave);rot('thigh.R',-34*wave);rot('shin.L',-max(0,wave)*38);rot('shin.R',-max(0,-wave)*38)
                aim();rot('spine',8);rig.pose.bones['hips'].location.y=.025*abs(wave)
            elif clip=='death':
                rot('hips',-min(1,t*1.6)*85);rig.pose.bones['hips'].location.y=-min(1,t*1.6)*.57
            else:
                if clip!='idle':aim()
                rot('head',wave*1.2)
                if clip=='idle':rot('spine',wave*1.4)
                if clip in ['crouch','prone']:
                    rig.pose.bones['hips'].location.y=-.29 if clip=='crouch' else -.60
                    rot('thigh.L',65);rot('thigh.R',25);rot('shin.L',-100);rot('shin.R',-75);rot('spine',18 if clip=='crouch' else 75)
                if clip=='fire':rot('spine',-6*math.sin(t*math.pi));rot('upper_arm.L',78-8*math.sin(t*math.pi),5,-12)
                if clip=='reload':rot('forearm.R',-20+45*math.sin(t*math.pi),0,-35)
            pose_frame(clip,t)
            for pb in rig.pose.bones:
                pb.keyframe_insert('scale',frame=f)
                pb.keyframe_insert('rotation_euler',frame=f);pb.keyframe_insert('location',frame=f)
        rig.animation_data.action=None
        tr=rig.animation_data.nla_tracks.new();tr.name=clip;st=tr.strips.new(clip,0,act);st.action_frame_end=length;tr.mute=True
    for tr in rig.animation_data.nla_tracks:tr.mute=False
    bpy.context.scene.frame_set(0)
    save(name)
    (OUT/(name+'-clips.json')).write_text(json.dumps({k:{'duration':v[0]/24,'fps':24,'loop':v[1],'root_motion':'in_place','bones':list(specs)} for k,v in clips.items()},indent=2))

def sandbag():
    clear();cloth=material('sand canvas',(.43,.36,.23),.98);seam=material('stitched seam',(.30,.25,.16),1)
    gb('stuffed canvas bag',(0,0,0),(.059,.020,.042),cloth,.007)
    for x in [-.025,.025]:gb('end fold',(x,0,0),(.003,.012,.030),seam,.001)
    for z in [-.020,.020]:gb('seam',(0,-.002,z),(.046,.0015,.0015),seam,.0006)
    join_materials();save('sandbag')

def tank():
    clear();red=material('tank body',(.52,.23,.16),.38);dark=material('rubber treads',(.10,.12,.10));metal=material('wheel hubs',(.32,.17,.12),.4)
    gb('hull',(0,.05,0),(.115,.06,.20),red,.015)
    gb('upper hull',(0,.085,-.01),(.105,.035,.15),red,.012)
    for x in [-.065,.065]:
        gb('track',(x,.037,0),(.03,.066,.215),dark,.02)
        for z in [-.075,-.037,0,.037,.075]:
            o=gc('road wheel',(x,.037,z),.025,.034,metal);o.rotation_euler[1]=math.pi/2
        for z in [i*.018-.09 for i in range(11)]:gb('tread link',(x,.073,z),(.033,.007,.013),dark,.001)
    hull_objects=join_materials()
    gc('turret',(0,.12,-.01),.048,.049,red);gc('hatch',(0,.148,-.01),.021,.012,red)
    rod('main gun',(0,.131,-.04),(0,.131,-.18),.008,red)
    turret_objects=[o for o in list(bpy.context.scene.objects) if o.type=='MESH' and o not in hull_objects]
    turret_meshes=join_materials(turret_objects)
    pivot=bpy.data.objects.new('TurretPivot',None);bpy.context.collection.objects.link(pivot);pivot.location=g((0,.12,-.01))
    bpy.context.view_layer.update()
    for o in turret_meshes:
        world=o.matrix_world.copy();o.parent=pivot;o.matrix_world=world
    muzzle=bpy.data.objects.new('Muzzle',None);bpy.context.collection.objects.link(muzzle);muzzle.parent=pivot
    muzzle.location=Vector(g((0,.131,-.18)))-pivot.location
    save('tank')

if '--only-tank' in sys.argv:
    tank()
else:
    office()
    for team in ['green','blue','red']:rigged('infantry-'+team,team=team)
    rigged('worker',True);tank();sandbag()
print('DESKFRONT_BLENDER_COMPLETE',OUT)
