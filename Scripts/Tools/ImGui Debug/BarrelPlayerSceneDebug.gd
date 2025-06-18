class_name BarrelPlayerSceneDebug extends BarrelSceneDebugNode


var player : Player

func _ready() -> void:
	await owner.ready
	player = owner as Player
	super()
	BarrelDebugWindow.draw_player_debug.connect(_imgui_debug)
	
func _imgui_debug(_delta : float) -> void:
	ImGui.Text("testing")
	ImGui.Text("movement input: " + str(player.input_direction))
	pass
