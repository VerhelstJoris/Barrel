class_name PlayerMovementComponentDebugNode extends BarrelSceneDebugNode

var player : Player
var mov_comp : PlayerMovementComponent

func _ready() -> void:
	super()
	await owner.ready
	player = owner as Player
	mov_comp = player.movement_component
	
func _get_name() -> String:
	return "Movement Component"

func _draw_contents(_delta : float) -> void:
	super(_delta)
	ImGui.SeparatorText("Input")
	ImGui.Text("Movement Input: " + str(mov_comp.input_direction))
	ImGui.Text("Sprint Input: " + str(mov_comp.sprint_down))

	ImGui.Text("Current Movement State: " + str(mov_comp.state_machine.current_state.name))
	ImGui.Indent()
	_debug_draw_state(mov_comp.state_machine.current_state)
	ImGui.Unindent()
	
	
	
func _debug_draw_state(state : PlayerState) -> void:
	if(ImGui.CollapsingHeader(state.name)):
		ImGui.Text("Settings")
		ImGui.BeginDisabled()
		var can_move : Array[bool] = [state.can_move]
		ImGui.Checkbox("Can Move?", can_move)
		ImGui.EndDisabled()
		ImGui.Text("FWD Speed: " + str(state.forward_movement_speed))
		ImGui.Text("BWD Speed: " + str(state.backward_movement_speed))
		ImGui.Text("SID Speed: " + str(state.sideways_movement_speed))
		
		ImGui.Separator()
