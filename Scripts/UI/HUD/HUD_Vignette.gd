class_name HUDVignette extends ColorRect

@export var default_alpha : float = 0.1

var player: Player

var vignette_tween : Tween

const shader_alpha : String = "shader_parameter/alpha"

func _ready() -> void:
	material.set(shader_alpha, default_alpha)
	
func _transition_vignette(new_alpha : float , target_lerp_time: float) -> void:
	var target_alpha : float = new_alpha
	
	var transition_start_alpha : float = 0
	if(vignette_tween && vignette_tween.is_running()):
		transition_start_alpha = vignette_tween.get_total_elapsed_time() / target_lerp_time
		vignette_tween.stop()

	vignette_tween = create_tween()
	vignette_tween.tween_property(material,shader_alpha,target_alpha,target_lerp_time * (1-transition_start_alpha)).set_ease(Tween.EASE_OUT)
	