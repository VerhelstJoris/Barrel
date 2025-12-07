class_name InteractableDataAsset extends Resource

enum InteractionType {None, Pickup, World}

@export var type : InteractionType = InteractionType.None
@export var interactable_display_name : String = "Item Name"
@export var interaction_description : String = "Use"

@export var interaction_input : InputActionInfo 