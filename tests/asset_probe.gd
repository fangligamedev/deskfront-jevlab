extends SceneTree
func _initialize() -> void:
	var report: Dictionary={"passed":true,"assets":[]}
	for filename in ["infantry-green","infantry-blue","infantry-red","worker"]:
		var model=load("res://assets/models/"+filename+".glb").instantiate()
		root.add_child(model)
		var sk: Skeleton3D=model.find_children("*","Skeleton3D",true,false)[0]
		var player: AnimationPlayer=model.find_children("*","AnimationPlayer",true,false)[0]
		var item: Dictionary={"asset":filename,"bones":sk.get_bone_count(),"skin":false,"clips":[]}
		for m in model.find_children("*","MeshInstance3D",true,false):
			if m.skin!=null:item.skin=true
		for clip in player.get_animation_list():
			if clip=="RESET":continue
			var a: Animation=player.get_animation(clip)
			var missing: Array=[];var bone_tracks: int=0;var max_root_drift: float=0;var variation: float=0
			for track in range(a.get_track_count()):
				var path: NodePath=a.track_get_path(track)
				if path.get_subname_count()>0:
					var bn=path.get_subname(0)
					if sk.find_bone(bn)<0:missing.append(bn)
					else:bone_tracks+=1
					if bn=="root" and a.track_get_type(track)==Animation.TYPE_POSITION_3D:
						var first: Vector3=a.track_get_key_value(track,0)
						for k in range(a.track_get_key_count(track)):
							var v: Vector3=a.track_get_key_value(track,k);max_root_drift=maxf(max_root_drift,Vector2(v.x-first.x,v.z-first.z).length())
				if a.track_get_type(track)==Animation.TYPE_ROTATION_3D and a.track_get_key_count(track)>1:
					var first: Quaternion=a.track_get_key_value(track,0)
					for k in range(a.track_get_key_count(track)):variation=maxf(variation,first.angle_to(a.track_get_key_value(track,k)))
			var semantic=String(clip).get_slice("/",String(clip).get_slice_count("/")-1)
			a.loop_mode=Animation.LOOP_LINEAR if semantic in ["idle","run","aim","crouch","prone","typing"] else Animation.LOOP_NONE
			var passed: bool=missing.is_empty() and bone_tracks>0 and max_root_drift<.001 and variation>.0001 and a.length>0
			report.passed=report.passed and passed
			item.clips.append({"id":semantic,"duration":a.length,"loop":a.loop_mode,"bone_tracks":bone_tracks,"missing_bones":missing,"root_horizontal_drift":max_root_drift,"rotation_variation":variation,"passed":passed})
		report.passed=report.passed and item.skin and item.bones==17
		report.assets.append(item)
		if filename=="infantry-green":ResourceSaver.save(player.get_animation_library(""),"res://output/infantry-library.tres")
		model.queue_free()
	var f=FileAccess.open("res://output/asset-probe.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "))
	print("ASSET_PROBE ",report.passed)
	quit(0 if report.passed else 1)
