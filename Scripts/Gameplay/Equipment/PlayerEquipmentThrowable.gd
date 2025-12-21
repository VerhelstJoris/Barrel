class_name PlayerEquipmentThrowable extends  PlayerEquipment

signal drop_equipment_input(event: InputEvent)

@export var rigid_body : CollisionPhysicsBody
@export var hitboxes : Array[HitboxComponent]

@export var meshes : Array[MeshInstance3D]

func _ready() -> void:
	super()
	drop_equipment_input.connect(_try_drop_equipment)
	

func _on_start_unholster():
	super()
	print("throwable unholster")
	player.arms.arms_animation_bus.throwable_unholstered = true
	if(input_receiver):
		input_receiver._change_HUD_available_actions(input_receiver.input_dictionary.keys(), self)
		
func _on_start_holster():
	super()
	print("throwable holster")
	player.arms.arms_animation_bus.throwable_unholstered = false
	
func _can_be_holstered() -> bool:
	return false
	
func _on_equipped(_player : Player) -> void:
	super(_player)
	if(rigid_body):
		rigid_body.set_transform(Transform3D.IDENTITY)
		
	for hitbox in hitboxes:
		hitbox._set_collisions_enabled(false)
		
	for mesh in meshes:
		mesh.set_layer_mask_value(2,true)
		mesh.set_layer_mask_value(1,false)

func _try_use_equipment(_event : InputEvent) -> void:
	print("Try Use throwable")
		
func _try_drop_equipment(_event : InputEvent) -> void:
	print("try drop throwabe")