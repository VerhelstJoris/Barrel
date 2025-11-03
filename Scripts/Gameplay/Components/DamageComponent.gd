class_name DamageComponent extends  Node


@export var shapes_to_register_hits_from : Array[PhysicsBody3D]

const damaged_signal_name : String = "on_damaged"

func _ready() -> void:
	_register_shape_signals()
	
func _register_shape_signals() -> void:
	for shape in shapes_to_register_hits_from:
		shape.add_user_signal(damaged_signal_name, ["Hit", "Damage"])
		shape.connect(damaged_signal_name, Callable(self, "_on_shape_damaged"))

func _on_shape_damaged(_hit : Dictionary, _damage : float) -> void:
	print("ON SHAPE DAMAGED FOR ", _damage)