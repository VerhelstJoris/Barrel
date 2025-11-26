class_name VFXInstance extends Node3D

@export var lifetime : float = 5
@export var particles_emit_on_spawn : Array[GPUParticles3D]

func _ready() -> void:
	_toggle_emit_vfx(particles_emit_on_spawn, true)
	
	await get_tree().create_timer(lifetime).timeout
	queue_free()
	
func _toggle_emit_vfx(vfx_to_toggle: Array[GPUParticles3D], emit : bool) -> void:
	for vfx in vfx_to_toggle:
		if(vfx != null):
			vfx.emitting = emit