extends CharacterBody3D
## Third-person controller of the demo. Moves the character for real (world-space motion),
## which is what the cloth reacts to: acceleration, stops, jumps, landings, turns.

const WALK_SPEED := 1.7
const RUN_SPEED := 6.2
const ACCEL := 9.0
const DECEL := 14.0  # snappy stops: the coat keeps going
const JUMP_SPEED := 4.8
const TURN_SPEED := 11.0

var outfit: ClothOutfit
var locomotion: ProceduralLocomotion
var visual: Node3D
var camera_yaw := 0.0
var _prev_yaw := 0.0
var _prev_speed := 0.0
var _was_on_floor := true
var _fall_speed := 0.0


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var running := Input.is_action_pressed("run")
	var wish := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, camera_yaw)
	var target := wish * (RUN_SPEED if running else WALK_SPEED)
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var rate := ACCEL if target.length() > hv.length() else DECEL
	if not is_on_floor():
		rate *= 0.25
	hv = hv.move_toward(target, rate * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_SPEED
	else:
		velocity.y -= 9.8 * delta
		_fall_speed = maxf(_fall_speed, -velocity.y)
	move_and_slide()

	if is_on_floor() and not _was_on_floor:
		locomotion.land(_fall_speed)
		_fall_speed = 0.0
	_was_on_floor = is_on_floor()

	# face the movement direction with a smooth (but quick) turn
	if hv.length() > 0.2:
		var yaw := atan2(-hv.x, -hv.z)
		visual.rotation.y = lerp_angle(visual.rotation.y, yaw, 1.0 - exp(-TURN_SPEED * delta))
	var turn := wrapf(visual.rotation.y - _prev_yaw, -PI, PI) / delta
	_prev_yaw = visual.rotation.y
	var speed := hv.length()
	locomotion.drive(speed, turn, (speed - _prev_speed) / delta, is_on_floor(), velocity.y)
	_prev_speed = speed
