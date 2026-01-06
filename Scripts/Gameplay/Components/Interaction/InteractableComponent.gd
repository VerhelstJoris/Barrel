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
			if(interact_data.alternative_interaction_item == null && !interact_data.pick_up_self):
				push_error("No valid interact item set on interact data on ", owner.name, " should be a player equipment scene")
		InteractableDataAsset.InteractionType.None:
			push_error("No valid interact type set on  assigned on ", owner.name)
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
	var equipment_to_pickup : PlayerEquipment = null

	if(interact_data.alternative_interaction_item != null):
		equipment_to_pickup = interact_data.alternative_interaction_item.instantiate()
		_interactor.player.arms.add_child(equipment_to_pickup)
	elif(interact_data.pick_up_self):
		if(!owner.has_meta(PlayerEquipment.equipment_node_name)):
			push_error("Interactable Component Cannot find equipment node via metadata")
			return
		equipment_to_pickup = owner.get_meta(PlayerEquipment.equipment_node_name) as PlayerEquipment
		owner.reparent(_interactor.player.arms, false)

	if(!equipment_to_pickup):
		push_error("No equipment can be picked up from the interaction on ", owner.name)
		return

	equipment_to_pickup.owner.transform = Transform3D.IDENTITY
	
	_interactor.player.equipment_manager._change_equipment(equipment_to_pickup, true)
	equipment_to_pickup.owner.rotation = Vector3.ZERO
	equipment_to_pickup.owner.position = Vector3.ZERO
