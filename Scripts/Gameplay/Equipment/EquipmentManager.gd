class_name EquipmentManager extends Node

@export var player : Player

@onready var HUD_equipment_input : HUDEquipmentInput = %HUDEquipment_Right

enum Holster_State {Hidden , Unholstering, Ready, Holstering}

enum Equipment_Slot {None, Left, Right}

var equipment_holster_state : Holster_State   = Holster_State.Hidden:
	set = _change_holster_state

var current_right_equipment : PlayerEquipment = null
var current_left_equipment : PlayerEquipment = null
	
signal on_holster_started()
signal on_holster_finish()
signal on_unholster_started()
signal on_unholster_finished()

signal on_holster_input_received(event : InputEvent)
signal on_quick_unholster_input_received(event : InputEvent)

signal on_equipped(new_equipment : PlayerEquipment, slot : Equipment_Slot)
signal on_unequipped(old_equipment : PlayerEquipment, slot : Equipment_Slot)

func _ready() -> void:
	await owner.ready
	player = owner as Player
	_change_equipment(player.arms.pistol_equipment, false)
	_change_holster_state(Holster_State.Hidden)
	_setup_input_signals()
	_setup_animation_data()

func _setup_input_signals() -> void:
	on_holster_input_received.connect(_on_holster_input)
	on_quick_unholster_input_received.connect(_on_quick_unholster_input)
	
func _setup_animation_data() -> void:
	player.arms.arms_animation_bus.on_holster_anim_finish.connect(_on_holster_anim_finish)
	player.arms.arms_animation_bus.on_unholster_anim_finish.connect(_on_unholster_anim_finish)

func _change_equipment(new_equipment : PlayerEquipment, _unholster_immediately : bool = false) -> void:
	var equipment_to_replace : PlayerEquipment = current_right_equipment if (new_equipment.slot == EquipmentManager.Equipment_Slot.Right) else current_left_equipment		
	
	if(new_equipment == equipment_to_replace):
		return

	_on_unequip(equipment_to_replace)

	if(new_equipment.slot == EquipmentManager.Equipment_Slot.Right):
		current_right_equipment = new_equipment
		player.arms.arms_animation_bus._reparent_to_prop_bone(current_right_equipment, FPArmsAnimationBus.E_prop_bone_type.Right, true)
		print("equip new right slot ", new_equipment)
	elif(new_equipment.slot == EquipmentManager.Equipment_Slot.Left):
		print("equip new left slot ", new_equipment)
		current_left_equipment = new_equipment
		player.arms.arms_animation_bus._reparent_to_prop_bone(current_left_equipment, FPArmsAnimationBus.E_prop_bone_type.Left, true)
	
	_on_equip(new_equipment)	
	if(_unholster_immediately):
		new_equipment._on_start_unholster()

func _on_unequip(old_equipment : PlayerEquipment) -> void:
	var slot : Equipment_Slot = EquipmentManager.Equipment_Slot.None
	print("unequip ", old_equipment)
	if(old_equipment != null):
		old_equipment.input_receiver.on_available_equipment_actions_changed.disconnect(HUD_equipment_input._on_equipment_input_actions_changed)
		old_equipment.input_receiver.on_available_equipment_actions_cleared.disconnect(HUD_equipment_input._on_equipment_input_actions_cleared)
		slot = old_equipment.slot
	on_unequipped.emit(old_equipment, slot)

func _on_equip(new_equipment : PlayerEquipment) -> void:
	var slot : Equipment_Slot = EquipmentManager.Equipment_Slot.None
	print("equip ", new_equipment)
	if(new_equipment != null):
		new_equipment.input_receiver.on_available_equipment_actions_changed.connect(HUD_equipment_input._on_equipment_input_actions_changed)
		new_equipment.input_receiver.on_available_equipment_actions_cleared.connect(HUD_equipment_input._on_equipment_input_actions_cleared)
		new_equipment._on_equipped(player)
		slot = new_equipment.slot

	on_equipped.emit(new_equipment, slot)

func _on_quick_unholster_input(_event : InputEvent) -> void:
	if(equipment_holster_state == Holster_State.Hidden):
		_change_holster_state(Holster_State.Unholstering)

func _on_holster_input(_event : InputEvent) -> void:
	match equipment_holster_state:
		Holster_State.Hidden:
			_change_holster_state(Holster_State.Unholstering)
		Holster_State.Ready:
			if(_can_holster_equipment()):
				_change_holster_state(Holster_State.Holstering)
		_:
			pass

func _can_holster_equipment() -> bool:
	var right_valid : bool = current_right_equipment!= null
	var left_valid : bool = current_left_equipment!= null
	if(!right_valid && !left_valid):
		return false
	
	return equipment_holster_state == Holster_State.Ready && (!right_valid || current_right_equipment._can_be_holstered()) && (!left_valid || current_left_equipment._can_be_holstered())

func _change_holster_state(new_state : Holster_State) -> void:
	if(current_right_equipment == null && current_left_equipment == null):
		return

	equipment_holster_state = new_state
	match new_state:
		Holster_State.Holstering:
			on_holster_started.emit()
			if(current_right_equipment):
				current_right_equipment._on_start_holster()
			if(current_left_equipment):
				current_left_equipment._on_start_holster()
		Holster_State.Unholstering:
			on_unholster_started.emit()
			if(current_right_equipment):
				current_right_equipment._on_start_unholster()
			if(current_left_equipment):	
				current_left_equipment._on_start_unholster()
		Holster_State.Hidden:
			if(current_right_equipment):
				current_right_equipment.visible = false
			if(current_left_equipment):
				current_left_equipment.visible = false
		_:
			pass

func _on_holster_anim_finish() -> void:
	equipment_holster_state = Holster_State.Hidden

func _on_unholster_anim_finish() -> void:
	equipment_holster_state = Holster_State.Ready

func _can_use_equipment() -> bool:
	return equipment_holster_state == Holster_State.Ready

func _is_equipment_slot_available(slot : Equipment_Slot) -> bool:
	match slot:
		Equipment_Slot.Left:
			return current_left_equipment == null && (current_right_equipment == null || !current_right_equipment._is_currently_using_both_hands())
		Equipment_Slot.Right:
			return current_right_equipment == null && (current_left_equipment == null || !current_left_equipment._is_currently_using_both_hands())
		_:
			return false
	
			
	
func _can_enter_two_handed_action( from_slot : Equipment_Slot ) -> bool:
	if(from_slot == Equipment_Slot.Right):
		return current_left_equipment == null
		
	return true