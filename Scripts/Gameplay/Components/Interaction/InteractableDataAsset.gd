class_name InteractableDataAsset extends Resource

enum InteractionType {None, Equip, Pickup, World}

@export var interaction_input : InputActionInfo

@export_group("Interact Type")
@export var type : InteractionType = InteractionType.None

#if this is the equip type, equip this item (assuming it derives from PlayerEquipment)
@export var pick_up_self : bool = true
@export var alternative_interaction_item : PackedScene 

@export_group("Prompt")
@export var interactable_display_name : String = "Item Name"
@export var interaction_description : String = "Use"

