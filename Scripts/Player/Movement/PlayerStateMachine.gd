class_name PlayerStateMachine extends Node

signal transitioned(state: PlayerState)

static var FROM = "from_state"
static var TO = "to_state"

# probably not the best way to store the state constants
static var WALK = 0
static var SPRINT = 1
static var JUMP = 2
static var FALL = 3

static var movement_state : Dictionary = {
	WALK: "Walk",
	SPRINT: "Sprint", 
	JUMP: "Jump", 
	FALL: "Fall", 
}

@export var initial_state := NodePath()

@onready var state: PlayerState = get_node(initial_state)

func _ready() -> void:
	await owner.ready
	for child in get_children():
		child.state_machine = self
		state._enter()
		
func _process(delta: float) -> void:
	state._check_transitions()
	state._update(delta)
	
func _physics_process(delta: float) -> void:
	state._physics_update(delta)


func _transition_to(target_state_name: String) -> void:
	if not has_node(str(target_state_name)):
		push_error("No target node \"" + target_state_name + "\" found")
		return
	
	if state == get_node(target_state_name):
		return
	
	print("Exit ", state.name)
	state._exit()
	state = get_node(target_state_name)
	print("Enter ", state.name)
	state._enter()
	emit_signal("transitioned", state)
