class_name EquipmentManager extends Node

@export var player : Player

@export var HUD_equipment_input_arr : Array[HUDEquipmentInput]

enum Holster_State {Hidden , Unholstering, Ready, Holstering}

enum Equipment_Slot {None, Left, Right}

var current_equipment : Dictionary[Equipment_Slot, PlayerEquipment]
var current_holster_states : Dictionary[Equipment_Slot,Holster_State]

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
	_setup_input_signals()
	_setup_animation_data()
	_setup_ui_data()
	_setup_initial_equipment_data()

	
func _setup_initial_equipment_data() -> void:
	current_holster_states[Equipment_Slot.Left] = Holster_State.Hidden
	current_holster_states[Equipment_Slot.Right] = Holster_State.Hidden
	current_equipment[Equipment_Slot.Left] = null
	current_equipment[Equipment_Slot.Right] = null

	_change_equipment(player.arms.pistol_equipment, false)
	_change_holster_state(Holster_State.Hidden, Equipment_Slot.Left)
	_change_holster_state(Holster_State.Hidden, Equipment_Slot.Right)

func _setup_input_signals() -> void:
	on_holster_input_received.connect(_on_holster_input)
	on_quick_unholster_input_received.connect(_on_quick_unholster_input)
	
func _setup_ui_data()-> void:
	for equipment_hud in HUD_equipment_input_arr:
		if(equipment_hud):
			equipment_hud._intialize(player)

func _setup_animation_data() -> void:
	player.arms.arms_animation_bus.on_holster_anim_finish.connect(_on_holster_anim_finish)
	player.arms.arms_animation_bus.on_unholster_anim_finish.connect(_on_unholster_anim_finish)

func _change_equipment(new_equipment : PlayerEquipment, _unholster_immediately : bool = false) -> void:
	var equipment_to_replace : PlayerEquipment = current_equipment[new_equipment.slot]		
	
	if(new_equipment == equipment_to_replace):
		return

	_on_unequip(equipment_to_replace)

	current_equipment[new_equipment.slot] = new_equipment
	if(new_equipment.slot == EquipmentManager.Equipment_Slot.Right):
		player.arms.arms_animation_bus._reparent_to_prop_bone(new_equipment, FPArmsAnimationBus.E_prop_bone_type.Right, true)
		print("equip new right slot ", new_equipment)
	elif(new_equipment.slot == EquipmentManager.Equipment_Slot.Left):
		print("equip new left slot ", new_equipment)
		player.arms.arms_animation_bus._reparent_to_prop_bone(new_equipment, FPArmsAnimationBus.E_prop_bone_type.Left, true)
	
	_on_equip(new_equipment)	
	if(_unholster_immediately):
		new_equipment._on_start_unholster()

func _on_unequip(old_equipment : PlayerEquipment) -> void:
	var slot : Equipment_Slot = EquipmentManager.Equipment_Slot.None
	print("unequip ", old_equipment)
	if(old_equipment != null):
		old_equipment._on_unequipped()
		for hud_info in HUD_equipment_input_arr:
			if(hud_info.equipment_slot_to_track == old_equipment.slot):
				old_equipment.input_receiver.on_available_equipment_actions_changed.disconnect(hud_info._on_equipment_input_actions_changed)
				old_equipment.input_receiver.on_available_equipment_actions_cleared.disconnect(hud_info._on_equipment_input_actions_cleared)
		slot = old_equipment.slot

	on_unequipped.emit(old_equipment, slot)


func _remove_equipment_from_slot(slot : Equipment_Slot) -> void:
	var equipment_to_remove : PlayerEquipment = current_equipment[slot]
	if(!equipment_to_remove):
		return
		
	_on_unequip(equipment_to_remove)
	
	current_equipment[slot] = null

func _on_equip(new_equipment : PlayerEquipment) -> void:
	var slot : Equipment_Slot = EquipmentManager.Equipment_Slot.None
	if(new_equipment != null):
		for hud_info in HUD_equipment_input_arr:
			if(hud_info.equipment_slot_to_track == new_equipment.slot):
				new_equipment.input_receiver.on_available_equipment_actions_changed.connect(hud_info._on_equipment_input_actions_changed)
				new_equipment.input_receiver.on_available_equipment_actions_cleared.connect(hud_info._on_equipment_input_actions_cleared)
		new_equipment._on_equipped(player)
		slot = new_equipment.slot

	on_equipped.emit(new_equipment, slot)

func _on_quick_unholster_input(_event : InputEvent) -> void:
	if(current_holster_states[Equipment_Slot.Right] == Holster_State.Hidden):
		_change_holster_state(Holster_State.Unholstering, Equipment_Slot.Right)
	if(current_holster_states[Equipment_Slot.Left] == Holster_State.Hidden):
		_change_holster_state(Holster_State.Unholstering, Equipment_Slot.Left)

func _on_holster_input(_event : InputEvent) -> void:
	match current_holster_states[Equipment_Slot.Right]:
		Holster_State.Hidden:
			_change_holster_state(Holster_State.Unholstering, Equipment_Slot.Right)
		Holster_State.Ready:
			if(_can_holster_equipment()):
				_change_holster_state(Holster_State.Holstering, Equipment_Slot.Right)
		_:
			pass

func _can_holster_equipment() -> bool:
	var right_valid : bool = current_equipment[Equipment_Slot.Right] != null
	var left_valid : bool = current_equipment[Equipment_Slot.Left] != null
	if(!right_valid && !left_valid):
		return false
	
	return current_holster_states[Equipment_Slot.Right] == Holster_State.Ready && (!right_valid || current_equipment[Equipment_Slot.Right]._can_be_holstered()) && (!left_valid || current_equipment[Equipment_Slot.Left]._can_be_holstered())

func _change_holster_state(new_state : Holster_State, _slot : Equipment_Slot) -> void:
	if(current_equipment[Equipment_Slot.Right] == null && current_equipment[Equipment_Slot.Left] == null):
		return

	current_holster_states[_slot] = new_state
	match new_state:
		Holster_State.Holstering:
			on_holster_started.emit()
			if(current_equipment[_slot] != null):
				current_equipment[_slot]._on_start_holster()
		Holster_State.Unholstering:
			on_unholster_started.emit()
			if(current_equipment[_slot] != null):
				current_equipment[_slot]._on_start_unholster()
		Holster_State.Hidden:
			if(current_equipment[_slot] != null):
				current_equipment[_slot].visible = false
		_:
			pass

func _on_holster_anim_finish(_slot : EquipmentManager.Equipment_Slot) -> void:
	_change_holster_state(Holster_State.Hidden, _slot)

func _on_unholster_anim_finish(_slot : EquipmentManager.Equipment_Slot) -> void:
	_change_holster_state(Holster_State.Ready, _slot)


func _can_use_equipment(slot : Equipment_Slot) -> bool:
	return current_holster_states[slot] == Holster_State.Ready

func _is_equipment_slot_available(slot : Equipment_Slot) -> bool:
	match slot:
		Equipment_Slot.Left:
			return current_equipment[Equipment_Slot.Left] == null && (current_equipment[Equipment_Slot.Right] == null || !current_equipment[Equipment_Slot.Right]._is_currently_using_both_hands())
		Equipment_Slot.Right:
			return current_equipment[Equipment_Slot.Right] == null && (current_equipment[Equipment_Slot.Left] == null || !current_equipment[Equipment_Slot.Left]._is_currently_using_both_hands())
		_:
			return false
			
func _get_input_receivers_to_process()-> Array[InputReceiver]:
	var ret : Array[InputReceiver]
	if(current_equipment[Equipment_Slot.Left] && _can_use_equipment(Equipment_Slot.Left)):
		ret.append(current_equipment[Equipment_Slot.Left].input_receiver)
		
	if(current_equipment[Equipment_Slot.Right] && _can_use_equipment(Equipment_Slot.Right)):
		ret.append(current_equipment[Equipment_Slot.Right].input_receiver)
	
	return ret
	

func _can_enter_two_handed_action( from_slot : Equipment_Slot ) -> bool:
	if(from_slot == Equipment_Slot.Right):
		return current_equipment[Equipment_Slot.Left] == null

	return true