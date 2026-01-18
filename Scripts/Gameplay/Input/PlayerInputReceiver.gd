class_name PlayerInputReceiver extends InputReceiver

func _ready() -> void:
	_connect_input_signals_to_functions()

func _connect_input_signals_to_functions():
	on_sprint_input_received.connect(_on_sprint_input)
	on_crouch_input_received.connect(_on_crouch_input)
	on_jump_input_received.connect(_on_jump_input)
	on_movement_input_received.connect(_on_movement_input)

signal on_sprint_input_received(event: InputEvent)
signal on_player_sprint_toggle(new_val)

var sprint_down : bool = false

func _on_sprint_input(_event: InputEvent) -> void:
	sprint_down = _event.is_pressed()
	on_player_sprint_toggle.emit(sprint_down)

signal on_crouch_input_received(event : InputEvent)
signal on_player_crouch_toggle(new_val)

var crouch_down : bool = false

func _on_crouch_input(_event : InputEvent) -> void:
	crouch_down = _event.is_pressed()
	on_player_crouch_toggle.emit(crouch_down)


signal on_jump_input_received(event : InputEvent)
signal on_player_jump_toggle(new_val)

var jump_down : bool = false

func _on_jump_input(_event : InputEvent) -> void:
	var new_state : bool = _event.is_pressed()
	if(new_state != jump_down):
		jump_down = new_state
		on_player_jump_toggle.emit(jump_down)
	
signal on_movement_input_received(event: InputEvent)
signal on_player_movement(direction)

const MOVE_FORWARD: String = "move_forward"
const MOVE_BACK: String = "move_back"
const MOVE_LEFT: String = "move_left"
const MOVE_RIGHT: String = "move_right"

@export_group("General Control Settings")
@export var movement_deadzone : Vector2 = Vector2(0.1,0.1)
var input_direction: Vector2

func _on_movement_input(_event : InputEvent) -> void:
	if Input.get_vector(MOVE_LEFT, MOVE_RIGHT, MOVE_BACK, MOVE_FORWARD):
		input_direction = Input.get_vector(MOVE_LEFT, MOVE_RIGHT, MOVE_BACK, MOVE_FORWARD)
		if(abs(input_direction.x) < movement_deadzone.x):
			input_direction.x = 0
		if(abs(input_direction.y) < movement_deadzone.y):
			input_direction.y = 0
	else:
		input_direction = Vector2.ZERO

	on_player_movement.emit(input_direction)
