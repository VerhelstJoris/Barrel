class_name BarrelPlayerSceneDebug extends BarrelSceneDebugNode

var player : Player

var equipment_debug_node : BarrelEquipmentSceneDebug = null

func _ready() -> void:
	super()
	await owner.ready
	player = owner as Player
	BarrelDebugWindow.draw_player_debug.connect(_draw)
	player.on_equipped.connect(_on_new_equipped)
	player.on_unequipped.connect(_on_old_unequipped)
	
func _draw(_delta: float) -> void:
	super(_delta)

func _draw_contents(_delta : float) -> void:
	super(_delta)
		
func _draw_children(_delta : float) -> void:
	super(_delta)
	ImGui.SeparatorText("Current Equipment")
	if(equipment_debug_node != null):
		equipment_debug_node._draw(_delta)
	else:
		_check_current_equipment()
		ImGui.Text("No Equipment Equipped")
	

func _on_new_equipped(new : PlayerEquipment):
	if(new == null):
		return

	_find_current_equipment()	
		
func _find_current_equipment() -> void:
	if(player.current_equipment != null):
		for child in player.current_equipment.get_children():
			if child is BarrelEquipmentSceneDebug:
				equipment_debug_node = child
				break
			
func _on_old_unequipped(old : PlayerEquipment) -> void:
	if(old == null):
		return

	equipment_debug_node = null

func _check_current_equipment() -> void:
	_find_current_equipment()
		
