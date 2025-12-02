@icon("res://DEBUG/Icons/Ico_Interact.png")
class_name InteractableComponent extends Node

# if a hitbox is provided then the signals will be added to the shapes it is registered to
@export var hitbox : HitboxComponent

@export var interact_shapes_to_detect_overlap : Array[PhysicsBody3D]

@export var outline : OutlineComponent

@export var outline_material : Material

@export var interact_data : InteractableDataAsset

const hover_start_signal_name : String = "on_interact_hover_start"
const hover_end_signal_name : String = "on_interact_hover_end"
const on_interact_signal_name : String = "on_interact_signal_name"

func _ready() -> void:
	if(!hitbox && interact_shapes_to_detect_overlap.is_empty()):
		push_error("No Hitbox assigned on " ,self.name , ", interactable cannot initialize properly")
		return

	if(hitbox):
		for hitbox_shape in hitbox.shapes_to_register_hits_from:
			_register_interact_signals_on_shape(hitbox_shape)
	else:
		for shape in hitbox.interact_shapes_to_detect_overlap:
			_register_interact_signals_on_shape(shape)
			
			
func _register_interact_signals_on_shape(body : PhysicsBody3D) -> void:
	if(!body):
		return
	
	body.add_user_signal(hover_start_signal_name, ["Interactor"])
	body.connect(hover_start_signal_name, _on_hover_start)
	body.add_user_signal(hover_end_signal_name, ["Interactor"])
	body.connect(hover_end_signal_name, _on_hover_end)
	body.add_user_signal(on_interact_signal_name, ["Interactor"])
	body.connect(on_interact_signal_name, _on_interact)


func _on_hover_start(_interactor: InteractorComponent) -> void:
	if(outline):
		outline.enabled = true
	
	if(_interactor):
		_interactor._try_set_current_interactable(self)
		
func _on_hover_end(_interactor: InteractorComponent) -> void:
	if(outline):
		outline.enabled = false
	
	if(_interactor):
		_interactor._try_clear_current_interactable(self)

func _on_interact(_interactor: InteractorComponent) -> void:
	pass