class_name BarrelPlayerSceneDebug extends BarrelSceneDebugNode

var player : Player

func _ready() -> void:
	await owner.ready
	player = owner as Player
	super()
	BarrelDebugWindow.draw_player_debug.connect(_imgui_debug)
	
func _imgui_debug(_delta : float) -> void:
	ImGui.Text("movement input: " + str(player.input_direction))
	if(player.current_equipment != null):
		ImGui.Text("we have equipment: " + str(player.current_equipment))
		BarrelDebugWindow.draw_current_equipment.emit(_delta)
	else:
		ImGui.Text("No Equipment Equipped")
	pass
