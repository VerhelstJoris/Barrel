class_name PlayerMovementComponentDebugNode extends BarrelSceneDebugNode

var player : Player
var mov_comp : PlayerMovementComponent

func _ready() -> void:
	super()
	await owner.ready
	player = owner as Player
	mov_comp = player.movement_component
	

func _draw_contents(_delta : float) -> void:
	super(_delta)
	ImGui.Text("Current Movement State: " + str(mov_comp.state_machine.state.name))
