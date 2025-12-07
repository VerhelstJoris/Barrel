class_name EquipmentManager extends Node

@export var player : Player

@onready var HUD_equipment_input : HUDEquipmentInput = %HUDEquipment

enum Holster_State {Hidden , Unholstering, Ready, Holstering}

var equipment_holster_state : Holster_State = Holster_State.Hidden:
	set = _change_holster_state

var current_equipment : PlayerEquipment = null:
	set = _change_equipment

signal on_holster_started()
signal on_holster_finish()
signal on_unholster_started()
signal on_unholster_finished()

signal on_holster_input_received(event : InputEvent)
signal on_quick_unholster_input_received(event : InputEvent)

signal on_equipped(new_equipment : PlayerEquipment)
signal on_unequipped(old_equipment : PlayerEquipment)

func _ready() -> void:
	await owner.ready
	player = owner as Player
	current_equipment = player.arms.pistol_equipment
	_change_holster_state(Holster_State.Hidden)
	_setup_input_signals()
	_setup_animation_data()

func _setup_input_signals() -> void:
	on_holster_input_received.connect(_on_holster_input)
	on_quick_unholster_input_received.connect(_on_quick_unholster_input)
	
func _setup_animation_data() -> void:
	player.arms.arms_animation_bus.on_holster_anim_finish.connect(_on_holster_anim_finish)
	player.arms.arms_animation_bus.on_unholster_anim_finish.connect(_on_unholster_anim_finish)

func _change_equipment(new_equipment : PlayerEquipment) -> void:
	if(new_equipment == current_equipment):
		return

	_on_unequip(current_equipment)

	current_equipment = new_equipment

	_on_equip(current_equipment)	

func _on_unequip(old_equipment : PlayerEquipment) -> void:
	if(old_equipment != null):
		old_equipment.input_receiver.on_available_equipment_actions_changed.disconnect(HUD_equipment_input._on_equipment_input_actions_changed)
		old_equipment.input_receiver.on_available_equipment_actions_cleared.disconnect(HUD_equipment_input._clear_current_input_details)
	on_unequipped.emit(old_equipment)

func _on_equip(new_equipment : PlayerEquipment) -> void:
	if(new_equipment != null):
		new_equipment.input_receiver.on_available_equipment_actions_changed.connect(HUD_equipment_input._on_equipment_input_actions_changed)
		new_equipment.input_receiver.on_available_equipment_actions_cleared.connect(HUD_equipment_input._clear_current_input_details)
		new_equipment._on_equipped(player)
	on_equipped.emit(new_equipment)

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
	return equipment_holster_state == Holster_State.Ready && current_equipment._can_be_holstered()

func _change_holster_state(new_state : Holster_State) -> void:
	if(current_equipment == null):
		return

	equipment_holster_state = new_state
	match new_state:
		Holster_State.Holstering:
			on_holster_started.emit()
			current_equipment._on_start_holster()
		Holster_State.Unholstering:
			on_unholster_started.emit()
			current_equipment._on_start_unholster()
		Holster_State.Hidden:
			current_equipment.visible = false
		_:
			pass

func _on_holster_anim_finish() -> void:
	equipment_holster_state = Holster_State.Hidden

func _on_unholster_anim_finish() -> void:
	equipment_holster_state = Holster_State.Ready

func _can_use_equipment() -> bool:
	return equipment_holster_state == Holster_State.Ready
			