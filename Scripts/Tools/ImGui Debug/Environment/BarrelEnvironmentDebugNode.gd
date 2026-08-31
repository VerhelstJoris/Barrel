class_name BarrelEnvironmentDebugNode extends BarrelSceneDebugNode

enum EDebugEnvNodeType { Foliage }

# Maps each environment debug node type to the list of all nodes registered for that type.
var _registered_nodes : Dictionary[EDebugEnvNodeType, Array] = {}
var manager_node : BarrelEnvironmentManagerDebugNode

# Per-type "currently selected index" storage. wrapped in array so it can be passed to ImGui easier
var _selected_index_by_type : Dictionary[EDebugEnvNodeType, Array] = {}

func _ready() -> void:
	super()
	manager_node = BarrelEnvironmentManagerDebugNode.new()
	add_child(manager_node)

func _get_name() -> String:
	return "Global Environment Debug"

func _draw(_delta: float) -> void:
	if(manager_node):
		manager_node._draw(_delta)
	else:
		ImGui.TextColored(Color.FIREBRICK, "No Environment Manger Debug Node!")	
	
	ImGui.Separator()
	for type : EDebugEnvNodeType in _registered_nodes.keys():
		_draw_type_section(type, _delta)
		ImGui.Separator()

func _draw_type_section(type: EDebugEnvNodeType, _delta: float) -> void:
	var nodes : Array = _registered_nodes.get(type, [])
	if nodes.is_empty():
		return

	var type_name : String = EDebugEnvNodeType.keys()[type]

	if not ImGui.CollapsingHeader(type_name):
		return

	# Make sure we have a selection slot for this type, and keep it in range
	if !_selected_index_by_type.has(type):
		_selected_index_by_type[type] = [0]
	var selected_ref : Array = _selected_index_by_type[type]
	selected_ref[0] = clampi(selected_ref[0], 0, nodes.size() - 1)

	var node_names : PackedStringArray = []
	for node : BarrelSceneDebugNode in nodes:
		node_names.append(node._get_name())

	ImGui.Combo("Selected Node", selected_ref, node_names)

	ImGui.SameLine()
	if ImGui.Button("Select Closest"):
		var closest_index : int = _get_closest_node_index(nodes)
		print("closest index : ", closest_index)
		if closest_index != -1:
			selected_ref[0] = closest_index

	ImGui.Indent()
	var selected_node : BarrelSceneDebugNode = nodes[selected_ref[0]]
	selected_node._draw(_delta)
	ImGui.Unindent()

func _get_closest_node_index(nodes: Array) -> int:
	var player_node := BarrelGlobalDebugWindow.player_node
	if(!player_node):
		return -1
	if player_node.player == null:
		return -1
 
	var player_position : Vector3 = player_node.player.global_position
	var closest_index : int = -1
	var closest_distance_sq : float = INF
 
	for i in nodes.size():
		var node : BarrelSceneDebugNode = nodes[i]
		if not (node.owner is Node3D):
			continue
 
		var distance_sq : float = (node.get_parent() as Node3D).global_position.distance_squared_to(player_position)
		if distance_sq < closest_distance_sq:
			closest_distance_sq = distance_sq
			closest_index = i
 
	return closest_index

func _register_environment_node(new_node: BarrelSceneDebugNode, type: EDebugEnvNodeType) -> void:
	if not _registered_nodes.has(type):
		_registered_nodes[type] = []
	_registered_nodes[type].append(new_node)

func _unregister_environment_node(node: BarrelSceneDebugNode, type: EDebugEnvNodeType) -> void:
	if _registered_nodes.has(type):
		_registered_nodes[type].erase(node)
