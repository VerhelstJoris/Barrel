@icon("res://DEBUG/Icons/Ico_Interact.png")
class_name InteractableComponent extends Node

# if a hitbox is provided then the signals will be added to the shapes it is registered to
@export var hitbox : HitboxComponent

@export var interact_shapes_to_detect_overlap : Array[PhysicsBody3D]

@export var outline : OutlineComponent

@export var interact_data : InteractableDataAsset

const hover_start_signal_name : String = "on_interact_hover_start"
const hover_end_signal_name : String = "on_interact_hover_end"

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
			
	if(interact_data):
		_verify_data_asset()
	else:
		push_error("No valid interact data asset assigned on ", self.name)
	#verify some info 
	
func _verify_data_asset() -> void:
	match interact_data.type:
		InteractableDataAsset.InteractionType.Equip:
			if(interact_data.interaction_item == null):
				push_error("No valid interact item set on interact data on ", interact_data.name, " should be a player equipment scene")
		InteractableDataAsset.InteractionType.None:
			push_error("No valid interact type set on  assigned on ", interact_data.name)
		_:
			pass
			
			
func _register_interact_signals_on_shape(body : PhysicsBody3D) -> void:
	if(!body):
		return
	
	body.add_user_signal(hover_start_signal_name, ["Interactor"])
	body.connect(hover_start_signal_name, _on_hover_start)
	body.add_user_signal(hover_end_signal_name, ["Interactor"])
	body.connect(hover_end_signal_name, _on_hover_end)


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

func _interact(_interactor: InteractorComponent) -> void:
	match interact_data.type:
		InteractableDataAsset.InteractionType.Equip:
			_equip_interact_item_on_interactor(_interactor)
		_:
			push_error("interact type currently not implemented")

func _equip_interact_item_on_interactor(_interactor: InteractorComponent) -> void:
	if(interact_data.interaction_item):
		var created_item : PlayerEquipment = interact_data.interaction_item.instantiate()
		_interactor.player.arms.add_child(created_item)
		_interactor.player.equipment_manager._change_equipment(created_item)
	
	
