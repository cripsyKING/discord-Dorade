@tool
class_name ClothWindZone
extends Node3D
## Wind source read by every [SecondaryClothSimulator] in the scene.
##
## The wind blows along -Z of this node. It is never constant: a slow gust signal modulates
## its strength and a 3D turbulence field travels with the wind, so neighbouring parts of
## the fabric ripple at different times (progressive, irregular waves).

const GROUP := &"cloth_wind"

@export var enabled := true
## Average wind speed (m/s).
@export_range(0.0, 40.0, 0.1) var strength := 4.0
## Gust amplitude relative to [member strength].
@export_range(0.0, 2.0, 0.01) var gust_amount := 0.6
## Gusts per second (roughly).
@export_range(0.01, 4.0, 0.01) var gust_frequency := 0.25
## Amplitude of the swirling turbulence (m/s).
@export_range(0.0, 20.0, 0.1) var turbulence := 1.5
## Size of the turbulence eddies (m).
@export_range(0.1, 20.0, 0.1) var turbulence_scale := 1.2
## 0 = infinite (global wind). Otherwise spherical zone with a soft border.
@export_range(0.0, 500.0, 0.1) var radius := 0.0

var _noise := FastNoiseLite.new()


func _init() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 2


func _enter_tree() -> void:
	add_to_group(GROUP)


func _exit_tree() -> void:
	remove_from_group(GROUP)


## Wind velocity (m/s, world space) at [param pos] and time [param t].
func sample(pos: Vector3, t: float) -> Vector3:
	if not enabled or (strength <= 0.0 and turbulence <= 0.0):
		return Vector3.ZERO
	var falloff := 1.0
	if radius > 0.0:
		var d := pos.distance_to(global_position)
		falloff = clampf(1.0 - (d - radius * 0.8) / (radius * 0.2), 0.0, 1.0)
		if falloff <= 0.0:
			return Vector3.ZERO
	var dir := -global_basis.z.normalized()
	var gust := 1.0 + gust_amount * _noise.get_noise_1d(t * gust_frequency * 4.0)
	# the turbulence field is advected along the wind: ripples travel across the cloth
	var q := (pos - dir * strength * t * 0.6) / turbulence_scale
	var swirl := Vector3(
		_noise.get_noise_3d(q.x, q.y + 31.7, q.z + t * 0.7),
		_noise.get_noise_3d(q.x + 57.1, q.y, q.z + t * 0.7) * 0.5,
		_noise.get_noise_3d(q.x - 13.3, q.y + 7.9, q.z + t * 0.7))
	return (dir * strength * maxf(gust, 0.0) + swirl * turbulence) * falloff
