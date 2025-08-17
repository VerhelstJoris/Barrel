class_name PlayerState extends Node

var state_machine: PlayerStateMachine = null
var mov_comp: PlayerMovementComponent
var player: Player

func _ready() -> void:
	await owner.ready
	player = owner as Player
	assert(player != null)
	mov_comp = player.movement_component
	assert(mov_comp != null)

func update(_delta: float) -> void:
	pass

func physics_update(_delta: float) -> void:
	pass
	
func enter(_msg := {}) -> void:
	pass
	
func exit() -> void:
	pass	
