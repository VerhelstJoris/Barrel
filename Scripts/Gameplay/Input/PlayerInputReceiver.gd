class_name PlayerInputReceiver extends InputReceiver

func _ready() -> void:
	_connect_input_signals_to_functions()

func _connect_input_signals_to_functions():
	on_sprint_input_received.connect(_on_sprint_input)
	on_crouch_input_received.connect(_on_crouch_input)
	on_jump_input_received.connect(_on_jump_input)


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