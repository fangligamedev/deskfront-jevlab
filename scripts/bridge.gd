extends Node
var game
var http: HTTPRequest
var elapsed: float=0
var busy: bool=false
var acknowledgements: Array=[]
var seen_ids: Array=[]
var base_url: String="http://127.0.0.1:8768"
var enabled: bool=true

func setup(owner_game) -> void:
	game=owner_game
	if DisplayServer.get_name()=="headless" and OS.get_environment("DESKFRONT_HEADLESS_BRIDGE")!="1":enabled=false;return
	if OS.has_feature("web"):base_url=str(JavaScriptBridge.eval("window.location.origin"))
	elif OS.get_environment("DESKFRONT_URL")!="":base_url=OS.get_environment("DESKFRONT_URL")
	http=HTTPRequest.new();add_child(http);http.timeout=2;http.request_completed.connect(_completed)

func _process(delta: float) -> void:
	if not enabled:return
	elapsed+=delta
	if elapsed<.20 or busy:return
	elapsed=0;busy=true
	var state: Dictionary=game.snapshot()
	if OS.has_feature("web"):JavaScriptBridge.eval("window.__deskfrontState="+JSON.stringify(state)+";window.render_game_to_text=()=>JSON.stringify(window.__deskfrontState)")
	var err=http.request(base_url+"/api/sync",["Content-Type: application/json"],HTTPClient.METHOD_POST,JSON.stringify({"state":state,"acks":acknowledgements}))
	if err!=OK:busy=false

func _completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	busy=false
	if result!=HTTPRequest.RESULT_SUCCESS or code!=200:return
	acknowledgements.clear()
	var data=JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary:return
	for c in data.get("commands",[]):
		if seen_ids.has(c.get("id","")):continue
		seen_ids.append(c.get("id",""))
		if seen_ids.size()>256:seen_ids.pop_front()
		acknowledgements.append(game.command(c))
