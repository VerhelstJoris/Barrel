class_name BarrelGlobalDebugWindow extends Node

const debug_toggle_input : String = "debug_toggle"
const debug_toggle_mouse_capture : String = "debug_toggle_mouse_capture"

var tool_open :bool = false;

signal draw_player_debug(_delta)
signal draw_favourited_debug(_delta)
signal draw_environment_debug(_delta)

var environment_node : BarrelEnvironmentDebugNode
static var player_node : BarrelPlayerSceneDebug

func _ready() -> void:
	environment_node = BarrelEnvironmentDebugNode.new()
	add_child(environment_node)
	draw_environment_debug.connect(environment_node._draw)

func _input(event: InputEvent) -> void:
	if(event.is_action_pressed(debug_toggle_input)):
		_toggle_window()
	elif(event.is_action_pressed(debug_toggle_mouse_capture)):
		_toggle_mouse_capture()
		
func _toggle_window() -> void:
	tool_open = !tool_open
	if(tool_open):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _toggle_mouse_capture() -> void:
	pass
	#if(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED):
	#	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	#else:
	#	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	if(tool_open):
		if(ImGui.Begin("Demo")):
			ImGui.BeginTabBar("Categories")
			if(ImGui.BeginTabItem("Player")):
				draw_player_debug.emit(_delta)
				ImGui.EndTabItem()
			if(ImGui.BeginTabItem("Environment")):
				draw_environment_debug.emit(_delta)
				ImGui.EndTabItem()
			if(ImGui.BeginTabItem("Favourites")):
				draw_favourited_debug.emit(_delta)
				ImGui.EndTabItem()	
			ImGui.EndTabBar()	
			
		ImGui.End()
		
func _get_environment_node() -> BarrelEnvironmentDebugNode:
	return environment_node

func _register_player_node(node : BarrelSceneDebugNode) -> void:
	player_node = node
	
static func _get_player_node() -> BarrelSceneDebugNode:
	return player_node	
