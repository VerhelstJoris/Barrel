class_name Player extends CharacterBody3D

@export_range(1.0, 10.0) var camera_sensitivity: float = 2.0

@export_range(0.0, 0.5) var camera_start_deadzone: float = .2

@export_range(0.0, 0.5) var camera_end_deadzone: float = .1

@export_group("Components")
@export var input_receiver : PlayerInputReceiver
@onready var player_cam: Camera3D = %WorldCamera
@onready var movement_component : PlayerMovementComponent = %PlayerMovementComponent
@onready var equipment_manager : EquipmentManager = %EquipmentManager
@onready var interactor : InteractorComponent = %InteractorComponent

@onready var arms: FPArms = %FP_Arms


func _ready() -> void:
	_setup_animation_data()
	
func _setup_animation_data() -> void:
	var anim_bus : FPArmsAnimationBus = NodeUtils._retrieve_node_meta_from_self(FPArmsAnimationBus.arms_anim_bus_node_name, arms) as FPArmsAnimationBus
	if(anim_bus == null):
		push_error("No valid FP Arms animation bus found on player")
		return

	anim_bus._init_player_data(self)
	
func _on_mouse_motion_input(event : InputEvent) -> void:
	player_cam.mouse_motion = -event.relative * 0.001
	

	