extends RefCounted
## Code-authored miniature scenery; authoritative footprints stay in battlefield.gd.
static func build(field,node:Node3D,c:Dictionary):
 var w:float=c.size[0];var d:float=c.size[1];var h:float=c.height
 var plaster=field.mat(Color("#c3b997"));var dark=field.mat(Color("#434c43"));var brick=field.mat(Color("#927359"));var timber=field.mat(Color("#69624d"))
 match str(c.kind):
  "house":
   field.cube(node,Vector3(0,h*.46,0),Vector3(w,h*.92,d),plaster)
   field.cube(node,Vector3(0,h*.48,0),Vector3(w+.006,.012,d+.006),timber)
   for side in [-1,1]:
    for story in range(2):
     for z in [-d*.26,d*.26]:
      field.cube(node,Vector3(side*(w/2+.002),h*(.23+.45*story),z),Vector3(.004,h*.17,d*.22),dark)
      field.cube(node,Vector3(side*(w/2+.005),h*(.14+.45*story),z),Vector3(.01,.01,d*.27),timber)
   field.cube(node,Vector3(0,h*.17,d/2+.002),Vector3(w*.22,h*.34,.004),dark)
   field.cube(node,Vector3(0,h*.95,0),Vector3(w+.016,.025,d+.016),brick)
   field.cube(node,Vector3(w*.28,h+.016,-d*.25),Vector3(w*.12,.045,d*.12),brick)
  "bunker":
   field.cube(node,Vector3(0,h*.43,0),Vector3(w,h*.86,d),field.mat(Color("#868979")))
   field.cube(node,Vector3(0,h*.93,0),Vector3(w+.016,h*.14,d+.016),dark)
   for side in [-1,1]:field.cube(node,Vector3(side*(w/2+.002),h*.62,0),Vector3(.004,h*.20,d*.60),field.mat(Color("#222b26")))
  "wall","ruins":
   var count:int=maxi(2,ceili(w/.04))
   for row in range(4):
    for i in range(count):
     if c.kind=="ruins" and row>1 and (i+row)%3==0:continue
     field.cube(node,Vector3(-w/2+(i+.5)*w/count,(row+.5)*h/4,0),Vector3(w/count-.002,h/4-.002,d),brick if (i+row)%3 else plaster)
  "trench":
   field.cube(node,Vector3(0,h*.45,0),Vector3(w,h*.9,d),field.mat(Color("#736043")))
   var vertical:bool=d>w
   var count:int=maxi(2,ceili(maxf(w,d)/.045))
   for i in range(count):
    var offset:float=(i-(count-1)*.5)*maxf(w,d)/count
    var p:Vector3=Vector3(w/2+.002,h*.43,offset) if vertical else Vector3(offset,h*.43,d/2+.002)
    field.cube(node,p,Vector3(.006,h*.86,d/count*.8) if vertical else Vector3(w/count*.8,h*.86,.006),timber)
   field.cube(node,Vector3(0,h*.95,0),Vector3(w,.009,d),field.mat(Color("#a3936d")))
  "fuel_depot":
   field.cube(node,Vector3(0,.007,0),Vector3(w,.014,d),timber)
   for x in [-.25,.25]:
    for z in [-.25,.25]:
     var barrel=MeshInstance3D.new();var shape=CylinderMesh.new();shape.top_radius=minf(w,d)*.19;shape.bottom_radius=shape.top_radius;shape.height=h-.014;shape.radial_segments=12;barrel.mesh=shape;barrel.material_override=brick;node.add_child(barrel);barrel.position=Vector3(w*x,h/2+.007,d*z)
     field.cube(node,Vector3(w*x,h*.64,d*z),Vector3(w*.32,.009,d*.32),dark)
  "rock":
   var mesh=MeshInstance3D.new();var shape=SphereMesh.new();shape.radius=.5;shape.height=1;shape.radial_segments=7;shape.rings=3;mesh.mesh=shape;mesh.material_override=field.mat(Color("#7d8379"));node.add_child(mesh);mesh.position.y=h/2;mesh.scale=Vector3(w,h,d)
  "mud","road","water":
   var color:Color=Color({"mud":"#786343","road":"#a5a087","water":"#537e87"}[c.kind])
   field.cube(node,Vector3(0,h/2,0),Vector3(w,h,d),field.mat(color,.22 if c.kind=="water" else .9))
   if c.kind=="road":
    for i in range(5):field.cube(node,Vector3((i-2)*w/5,h+.001,0),Vector3(w/10,.001,.008),plaster)
