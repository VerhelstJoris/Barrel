class_name BarrelPlayerSceneDebug extends BarrelSceneDebugNode

var player : Player
var equipment_manager : EquipmentManager

var equipment_debug_node : BarrelEquipmentSceneDebug = null

func _ready() -> void:
	super()
	await owner.ready
	player = owner as Player
	equipment_manager = player.equipment_manager
	BarrelDebugWindow.draw_player_debug.connect(_draw)
	BarrelDebugWindow._register_player_node(self)
	equipment_manager.on_equipped.connect(_on_new_equipped)
	equipment_manager.on_unequipped.connect(_on_old_unequipped)
	
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
	

func _on_new_equipped(new : PlayerEquipment, _slot : EquipmentManager.EEquipmentSlot) -> void:
	if(new == null):
		return

	_find_current_equipment(_slot)	
		
func _find_current_equipment(_slot : EquipmentManager.EEquipmentSlot) -> void:
	var equipment : PlayerEquipment = equipment_manager.current_equipment[_slot]
	if(equipment != null):
		for child in equipment.get_children():
			if child is BarrelEquipmentSceneDebug:
				equipment_debug_node = child
				break
			
func _on_old_unequipped(old : PlayerEquipment, _slot : EquipmentManager.EEquipmentSlot) -> void:
	if(old == null):
		return

	equipment_debug_node = null

func _check_current_equipment() -> void:
	_find_current_equipment(EquipmentManager.EEquipmentSlot.Right)
		
