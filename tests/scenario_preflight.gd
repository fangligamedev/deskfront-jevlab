extends SceneTree
func _initialize():
 var path=OS.get_environment("DESKFRONT_SCENARIO_FILE")
 var level=JSON.parse_string(FileAccess.get_file_as_string(path))
 var result=preload("res://scripts/scenario_validator.gd").validate(level)
 print("SCENARIO_VALIDATION "+JSON.stringify(result))
 quit(0 if result.passed else 1)
