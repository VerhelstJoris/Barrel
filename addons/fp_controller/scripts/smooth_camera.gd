class_name SmoothCamera extends Camera3D

@export var speed := 44.0

var player: Player
@export var anim_player : AnimationPlayer

func _ready() -> void:
	await owner.ready
	player = owner as Player

	if(anim_player == null):
		push_error("Animation player not assigned on the player camera")	

	player.movement_component.on_player_movement_state_enter.connect(_on_player_enter_movement_state)
	player.movement_component.on_player_movement_state_leave.connect(_on_player_leave_movement_state)


func _on_player_enter_movement_state(_state_entered: PlayerStateMachine.E_StateName) -> void:
	if(_state_entered == PlayerStateMachine.E_StateName.Crouch):
		anim_player.play("Crouch")

func _on_player_leave_movement_state(_state_exited: PlayerStateMachine.E_StateName) -> void:
	if(_state_exited == PlayerStateMachine.E_StateName.Crouch):
		pass

func _physics_process(delta: float) -> void:
	var weight: float = clamp(speed * delta, 0.0, 1.0)
	
	global_transform = global_transform.interpolate_with(
		get_parent().global_transform, weight
	)
	
	global_position = get_parent().global_position
