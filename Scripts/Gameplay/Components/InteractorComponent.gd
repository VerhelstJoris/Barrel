@icon("res://DEBUG/Icons/Ico_Interact.png")
class_name InteractorComponent extends Node

@export_group("Targeting")
@export var interact_ray : RayCast3D
var default_raycast_target : Vector3
var DEBUG_draw_target : bool = false


@export var extend_interact_length_on_look_down : bool = true
@export var extend_interact_length_max_mult : float = 2.0
@export var extend_interact_length_max_angle : float = 80.0

@export_group("Components")
@export var interactable_prompt : HUDInteractablePrompt
@export var equipment_manager : EquipmentManager



var current_look_angle: float = 0.0

var current_hovered_object : Object = null
var current_hovered_interactable : InteractableComponent = null

var player : Player

signal on_interact_input_received(event : InputEvent)

func _ready() -> void:
	await owner.ready
	player = owner as Player
	
	if(!interact_ray):
		push_error("Interact Raycast not set on ", self.name, ", on ", owner)
	if(!interactable_prompt):
		push_error("No prompt set on " , self.name , " on " , owner)
	else:
		interactable_prompt._init_with_data(null)
	if(!equipment_manager):
		push_error("No equipment manager set on " , self.name , " on " , owner)

	default_raycast_target = interact_ray.target_position

	on_interact_input_received.connect(_on_interact_input_received)
	
func _physics_process(_delta: float) -> void:
	_decide_current_raycast_target_length()
	_find_current_hovered_object()
	#_check_for_display_promt()
	if(_can_currently_interact_with_hovered()):
		interactable_prompt._init_with_data(current_hovered_interactable)
	else:
		interactable_prompt._init_with_data(null)

	if(DEBUG_draw_target):
		if(interact_ray.is_colliding()):
			DebugDraw3D.draw_sphere(interact_ray.get_collision_point(), 0.03, Color.RED)
		else:
			var forward_offset : Vector3 = (-interact_ray.get_global_basis().y * interact_ray.get_target_position().length())
			DebugDraw3D.draw_sphere(interact_ray.get_global_position() + forward_offset, 0.03, Color.GREEN)


func _decide_current_raycast_target_length() -> void:
	
	current_look_angle= player.player_cam.get_global_rotation_degrees().x
	#extend the target length if we're looking down to ensure we can pick things off the ground
	if(current_look_angle < 0):
		var abs_angle : float = abs(current_look_angle)
		var alpha : float = (abs_angle/ max(abs_angle,extend_interact_length_max_angle))
		interact_ray.target_position = lerp(default_raycast_target, default_raycast_target * extend_interact_length_max_mult, alpha)
	else:
		interact_ray.target_position = default_raycast_target
	
	
func _can_currently_interact() -> bool:
	return true
	
func _can_current_hover_over_interactables() -> bool:
	return true

func _find_current_hovered_object() -> void:
	var new_object : Object= interact_ray.get_collider()
	if(current_hovered_object == new_object):
		return
		
	#unhover over the current object first
	if(current_hovered_object && current_hovered_object.has_user_signal(InteractableComponent.hover_end_signal_name)):
		current_hovered_object.emit_signal(InteractableComponent.hover_end_signal_name, self)
		
	#now start hovering over the new one
	current_hovered_object = new_object
	
	if(new_object):
		if(current_hovered_object.has_user_signal(InteractableComponent.hover_start_signal_name)):
			current_hovered_object.emit_signal(InteractableComponent.hover_start_signal_name, self)
			
func _on_interact_input_received(_event : InputEvent) -> void:
	_attempt_interact()
	
func _attempt_interact() -> void:
	if(_can_currently_interact() && _can_currently_interact_with_hovered()):
		current_hovered_interactable._interact(self)
		
func _try_set_current_interactable(_interactable_component: InteractableComponent)-> void:
	current_hovered_interactable = _interactable_component

func _try_clear_current_interactable(_interactable_component: InteractableComponent) -> void:
	if(current_hovered_interactable == _interactable_component):
		current_hovered_interactable = null
		interactable_prompt._init_with_data(null)
		
func _can_currently_interact_with_hovered() -> bool:
	if(current_hovered_interactable == null):
		return false
	
	match current_hovered_interactable.interact_data.type:
		InteractableDataAsset.EInteractionType.Equip:
			#is left hand slot free?
			return equipment_manager._is_equipment_slot_available(EquipmentManager.EEquipmentSlot.Left)
		_:
			pass

	return true	

