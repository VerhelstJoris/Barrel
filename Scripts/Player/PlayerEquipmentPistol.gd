class_name PlayerEquipmentPistol extends "PlayerEquipment.gd"

const log_pistol : String = "PlayerPistol" 
const anim_fire_condition : String = "parameters/conditions/try_fire"
const anim_pull_hammer_condition : String = "parameters/conditions/try_pull_hammer"

var ready_to_shoot: bool = true

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


func _try_use_equipment():
	#parameters/conditions/try_fire
	if ready_to_shoot:
		anim_tree[anim_fire_condition] = true
		anim_tree[anim_pull_hammer_condition] = false
	else:
		anim_tree[anim_fire_condition] = false
		anim_tree[anim_pull_hammer_condition] = true

	ready_to_shoot = !ready_to_shoot

