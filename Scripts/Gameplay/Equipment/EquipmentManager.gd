@icon("res://DEBUG/Icons/Ico_Hand.png")
class_name EquipmentManager extends Node

@export var player : Player

@export var HUD_equipment_input_arr : Array[HUDEquipmentInput]

@export var left_arm_pivot : Node3D
@export var right_arm_pivot : Node3D

@export var pickup_equipment_scale_modifier : float = 0.25

enum EHolsterState {Hidden , Unholstering, Ready, Holstering}
enum EEquipmentSlot {None, Left, Right}
enum EEquipmentType {Permanent , Consumable, Temporary}


var current_equipment : Dictionary[EEquipmentSlot, PlayerEquipment]
var current_holster_states : Dictionary[EEquipmentSlot,EHolsterState]

signal on_holster_started(equipment : PlayerEquipment, slot : EEquipmentSlot)
signal on_holster_finished(equipment : PlayerEquipment, slot : EEquipmentSlot)
signal on_unholster_started(equipment : PlayerEquipment, slot : EEquipmentSlot)
signal on_unholster_finished(equipment : PlayerEquipment, slot : EEquipmentSlot)

signal on_holster_input_received(event : InputEvent)
signal on_quick_unholster_input_received(event : InputEvent)

signal on_equipped(new_equipment : PlayerEquipment, slot : EEquipmentSlot)
signal on_unequipped(old_equipment : PlayerEquipment, slot : EEquipmentSlot)

func _ready() -> void:
	await owner.ready
	player = owner as Player
	_setup_input_signals()
	_setup_animation_data()
	_setup_ui_data()
	_setup_initial_equipment_data()
	
func _setup_initial_equipment_data() -> void:
	current_holster_states[EEquipmentSlot.Left] = EHolsterState.Hidden
	current_holster_states[EEquipmentSlot.Right] = EHolsterState.Hidden
	current_equipment[EEquipmentSlot.Left] = null
	current_equipment[EEquipmentSlot.Right] = null

	_change_equipment(player.arms.pistol_equipment, false)
	_change_holster_state(EHolsterState.Hidden, EEquipmentSlot.Left)
	_change_holster_state(EHolsterState.Hidden, EEquipmentSlot.Right)

func _setup_input_signals() -> void:
	on_holster_input_received.connect(_on_holster_input)
	on_quick_unholster_input_received.connect(_on_quick_unholster_input)
	
func _setup_ui_data()-> void:
	for equipment_hud in HUD_equipment_input_arr:
		if(equipment_hud):
			equipment_hud._intialize(player)

func _setup_animation_data() -> void:
	var arms_animation_bus : FPArmsAnimationBus = NodeUtils._retrieve_node_meta_from_node(FPArmsAnimationBus.arms_anim_bus_node_name,player.arms)
	if(arms_animation_bus == null):
		push_error("Failed to retrieve the FP Arms animation bus on the equipment manager")
	
	arms_animation_bus.on_holster_anim_finish.connect(_on_holster_anim_finish)
	arms_animation_bus.on_unholster_anim_finish.connect(_on_unholster_anim_finish)

func _change_equipment(new_equipment : PlayerEquipment, _unholster_immediately : bool = false) -> void:
	var equipment_to_replace : PlayerEquipment = current_equipment[new_equipment.slot]		
	
	if(new_equipment == equipment_to_replace):
		return

	_on_unequip(equipment_to_replace)

	current_equipment[new_equipment.slot] = new_equipment

	_on_equip(new_equipment)	
	if(_unholster_immediately):
		_change_holster_state(EHolsterState.Unholstering, new_equipment.slot)

func _on_unequip(old_equipment : PlayerEquipment) -> void:
	var slot : EEquipmentSlot = EEquipmentSlot.None
	print("unequip ", old_equipment)
	if(old_equipment != null):
		old_equipment._on_unequipped()
		for hud_info in HUD_equipment_input_arr:
			if(hud_info.equipment_slot_to_track == old_equipment.slot):
				old_equipment.input_receiver.on_available_equipment_actions_changed.disconnect(hud_info._on_equipment_input_actions_changed)
				old_equipment.input_receiver.on_available_equipment_actions_cleared.disconnect(hud_info._on_equipment_input_actions_cleared)
		slot = old_equipment.slot

	on_unequipped.emit(old_equipment, slot)


func _remove_equipment_from_slot(slot : EEquipmentSlot) -> void:
	var equipment_to_remove : PlayerEquipment = current_equipment[slot]
	if(!equipment_to_remove):
		return
		
	_on_unequip(equipment_to_remove)
	
	current_equipment[slot] = null

func _on_equip(new_equipment : PlayerEquipment) -> void:
	var slot : EEquipmentSlot = EquipmentManager.EEquipmentSlot.None
	if(new_equipment != null):
		for hud_info in HUD_equipment_input_arr:
			if(hud_info.equipment_slot_to_track == new_equipment.slot):
				new_equipment.input_receiver.on_available_equipment_actions_changed.connect(hud_info._on_equipment_input_actions_changed)
				new_equipment.input_receiver.on_available_equipment_actions_cleared.connect(hud_info._on_equipment_input_actions_cleared)
		new_equipment._on_equipped(player)
		slot = new_equipment.slot

	on_equipped.emit(new_equipment, slot)

func _on_quick_unholster_input(_event : InputEvent) -> void:
	if(current_holster_states[EEquipmentSlot.Right] == EHolsterState.Hidden  && current_equipment[EEquipmentSlot.Right] != null):
		_change_holster_state(EHolsterState.Unholstering, EEquipmentSlot.Right)
	if(current_holster_states[EEquipmentSlot.Left] == EHolsterState.Hidden && current_equipment[EEquipmentSlot.Left] != null):
		_change_holster_state(EHolsterState.Unholstering, EEquipmentSlot.Left)

func _on_holster_input(_event : InputEvent) -> void:
	match current_holster_states[EEquipmentSlot.Right]:
		EHolsterState.Hidden:
			_change_holster_state(EHolsterState.Unholstering, EEquipmentSlot.Right)
		EHolsterState.Ready:
			if(_can_holster_equipment()):
				_change_holster_state(EHolsterState.Holstering, EEquipmentSlot.Right)
		_:
			pass

func _can_holster_equipment() -> bool:
	var right_valid : bool = current_equipment[EEquipmentSlot.Right] != null
	var left_valid : bool = current_equipment[EEquipmentSlot.Left] != null
	if(!right_valid && !left_valid):
		return false
	
	return current_holster_states[EEquipmentSlot.Right] == EHolsterState.Ready && (!right_valid || current_equipment[EEquipmentSlot.Right]._can_be_holstered()) && (!left_valid || current_equipment[EEquipmentSlot.Left]._can_be_holstered())

func _change_holster_state(new_state : EHolsterState, _slot : EEquipmentSlot) -> void:
	if(current_equipment[EEquipmentSlot.Right] == null && current_equipment[EEquipmentSlot.Left] == null):
		return

	current_holster_states[_slot] = new_state
	match new_state:
		EHolsterState.Holstering:
			on_holster_started.emit(current_equipment[_slot], _slot)
			if(current_equipment[_slot] != null):
				current_equipment[_slot]._on_start_holster()
		EHolsterState.Unholstering:
			on_unholster_started.emit(current_equipment[_slot], _slot)
			if(current_equipment[_slot] != null):
				current_equipment[_slot]._on_start_unholster()
		EHolsterState.Hidden:
			if(current_equipment[_slot] != null):
				current_equipment[_slot].owner.visible = false
		_:
			pass

func _on_holster_anim_finish(_slot : EquipmentManager.EEquipmentSlot) -> void:
	_change_holster_state(EHolsterState.Hidden, _slot)
	on_holster_finished.emit(current_equipment[_slot], _slot)

func _on_unholster_anim_finish(_slot : EquipmentManager.EEquipmentSlot) -> void:
	_change_holster_state(EHolsterState.Ready, _slot)
	on_unholster_finished.emit(current_equipment[_slot], _slot)

func _can_use_equipment(slot : EEquipmentSlot) -> bool:
	return current_holster_states[slot] == EHolsterState.Ready

func _is_equipment_slot_available(slot : EEquipmentSlot) -> bool:
	if(current_holster_states[slot] != EHolsterState.Hidden):
		return false

	match slot:
		EEquipmentSlot.Left:
			return current_equipment[EEquipmentSlot.Left] == null && (current_equipment[EEquipmentSlot.Right] == null || !current_equipment[EEquipmentSlot.Right]._is_currently_using_both_hands())
		EEquipmentSlot.Right:
			return current_equipment[EEquipmentSlot.Right] == null && (current_equipment[EEquipmentSlot.Left] == null || !current_equipment[EEquipmentSlot.Left]._is_currently_using_both_hands())
		_:
			return false
			
func _get_input_receivers_to_process()-> Array[InputReceiver]:
	var ret : Array[InputReceiver]
	if(current_equipment[EEquipmentSlot.Left] && _can_use_equipment(EEquipmentSlot.Left)):
		ret.append(current_equipment[EEquipmentSlot.Left].input_receiver)
		
	if(current_equipment[EEquipmentSlot.Right] && _can_use_equipment(EEquipmentSlot.Right)):
		ret.append(current_equipment[EEquipmentSlot.Right].input_receiver)
	
	return ret

func _get_equipment_world_pivot_point (from_slot : EEquipmentSlot ) -> Node3D:
	match from_slot:
		EEquipmentSlot.Left:
			return left_arm_pivot
		EEquipmentSlot.Right:
			return right_arm_pivot
		EEquipmentSlot.None:
			pass		
	
	return null

func _can_enter_two_handed_action( from_slot : EEquipmentSlot ) -> bool:
	if(from_slot == EEquipmentSlot.Right):
		return current_equipment[EEquipmentSlot.Left] == null

	return true
