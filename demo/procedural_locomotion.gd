class_name ProceduralLocomotion
extends SkeletonModifier3D
## Demo-only gait for the outfit skeletons (the GLBs ship without animations).
## Your own AnimationPlayer / AnimationTree replaces this node: the cloth simulator only
## needs the skeleton to move.
##
## Feed it every frame with [method drive]. Rotations are built in skeleton (model) space:
## -Z forward, +Y up, ".L" bones on +X.

## Rotation (degrees) that brings the arms from the rest pose down along the body
## (T-pose rigs need ~50°, A-pose rigs 0°).
@export var arm_down := 0.0
@export var step_length := 0.75

var speed := 0.0  # horizontal speed (m/s)
var turn_rate := 0.0  # rad/s, positive = turning left
var accel := 0.0  # forward acceleration (m/s²)
var grounded := true
var vertical_speed := 0.0

var _phase := 0.0
var _air := 0.0
var _lean := 0.0
var _roll := 0.0
var _crouch := 0.0
var _crouch_v := 0.0
var _rest_global := {}
var _order: Array[int] = []
var _bones := {}
var _bound: Skeleton3D


func drive(p_speed: float, p_turn_rate: float, p_accel: float, p_grounded: bool, p_vertical: float) -> void:
	speed = p_speed
	turn_rate = p_turn_rate
	accel = p_accel
	grounded = p_grounded
	vertical_speed = p_vertical


## Landing impact (m/s of downward speed when touching the ground).
func land(impact: float) -> void:
	_crouch_v += clampf(impact, 0.0, 12.0) * 0.55


func _bind(skel: Skeleton3D) -> void:
	_bound = skel
	_rest_global.clear()
	_order.clear()
	_bones.clear()
	var stack: Array[int] = []
	for b in skel.get_parentless_bones():
		stack.append(b)
	while not stack.is_empty():
		var b: int = stack.pop_front()
		_order.append(b)
		var p := skel.get_bone_parent(b)
		_rest_global[b] = (_rest_global[p] if p >= 0 else Basis()) * skel.get_bone_rest(b).basis
		for c in skel.get_bone_children(b):
			stack.append(c)
	for n in ["pelvis", "spine", "chest", "neck", "shoulder.L", "upper_arm.L", "forearm.L", "hand.L",
			"shoulder.R", "upper_arm.R", "forearm.R", "hand.R", "thigh.L", "shin.L", "foot.L",
			"thigh.R", "shin.R", "foot.R"]:
		_bones[n] = skel.find_bone(n)


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	if _bound != skel:
		_bind(skel)
	var dt := clampf(get_process_delta_time(), 0.0, 0.1)
	_animate(skel, dt)


func _animate(skel: Skeleton3D, dt: float) -> void:
	var moving := clampf(speed / 1.0, 0.0, 1.0)
	var run := clampf((speed - 2.2) / 3.5, 0.0, 1.0)
	_phase = fmod(_phase + dt * speed / (2.0 * step_length * lerpf(1.0, 1.35, run)), 1.0)
	var s := sin(_phase * TAU)
	var c := cos(_phase * TAU)
	_air = move_toward(_air, 0.0 if grounded else 1.0, dt * 6.0)
	_lean = lerpf(_lean, moving * lerpf(0.05, 0.22, run) + clampf(accel * 0.015, -0.15, 0.2), 1.0 - exp(-6.0 * dt))
	_roll = lerpf(_roll, clampf(-turn_rate * speed * 0.035, -0.3, 0.3), 1.0 - exp(-8.0 * dt))
	# landing squash: damped spring
	_crouch_v += (-90.0 * _crouch - 13.0 * _crouch_v) * dt
	_crouch = clampf(_crouch + _crouch_v * dt, -0.2, 0.6)

	var ground := 1.0 - _air
	var leg_amp := deg_to_rad(lerpf(26.0, 48.0, run)) * moving * ground
	var knee := deg_to_rad(lerpf(30.0, 85.0, run)) * moving * ground
	var arm_amp := deg_to_rad(lerpf(14.0, 42.0, run)) * moving * ground
	var elbow := deg_to_rad(lerpf(12.0, 75.0, run)) * moving + deg_to_rad(8.0)
	var crouch := maxf(_crouch, 0.0)

	var rot := {}
	var pelvis := Basis(Vector3.BACK, _roll)
	rot["pelvis"] = pelvis
	var spine := pelvis * Basis(Vector3.RIGHT, -_lean - crouch * 0.25) * Basis(Vector3.UP, s * arm_amp * 0.25)
	rot["spine"] = spine
	rot["chest"] = spine * Basis(Vector3.RIGHT, -_lean * 0.3) * Basis(Vector3.UP, s * arm_amp * 0.3)
	rot["neck"] = rot["chest"] * Basis(Vector3.RIGHT, _lean * 0.9)
	for side in [["L", 1.0, 0.0], ["R", -1.0, PI]]:
		var sd: String = side[0]
		var sign_x: float = side[1]
		var ph: float = _phase * TAU + side[2]
		var swing := sin(ph) * leg_amp
		var bend := maxf(0.0, -cos(ph)) * knee + deg_to_rad(4.0) * moving
		var tuck := _air * deg_to_rad(40.0) + crouch * deg_to_rad(55.0)
		var thigh := pelvis * Basis(Vector3.RIGHT, swing + tuck)
		rot["thigh." + sd] = thigh
		var shin := thigh * Basis(Vector3.RIGHT, -bend - tuck * 1.6)
		rot["shin." + sd] = shin
		rot["foot." + sd] = pelvis * Basis(Vector3.RIGHT, (swing - bend) * 0.25)
		var down := deg_to_rad(arm_down) * -sign_x
		var raise := _air * deg_to_rad(12.0) * sign_x + crouch * deg_to_rad(10.0) * sign_x
		var arm: Basis = rot["chest"] * Basis(Vector3.RIGHT, -sin(ph) * arm_amp) * Basis(Vector3.BACK, down + raise)
		rot["shoulder." + sd] = rot["chest"]
		rot["upper_arm." + sd] = arm
		var fore: Basis = arm * Basis(Vector3.RIGHT, elbow + maxf(0.0, -sin(ph)) * elbow * 0.4)
		rot["forearm." + sd] = fore
		rot["hand." + sd] = fore

	# model-space rotation R per bone: new_global = R * rest_global
	var new_global := {}
	for b in _order:
		var p := skel.get_bone_parent(b)
		var parent_global: Basis = new_global[p] if p >= 0 else Basis()
		var bname := skel.get_bone_name(b)
		var g: Basis
		if rot.has(bname) and _bones.get(bname, -1) == b:
			g = rot[bname] * _rest_global[b]
			skel.set_bone_pose_rotation(b, (parent_global.inverse() * g).get_rotation_quaternion())
		else:
			g = parent_global * Basis(skel.get_bone_pose_rotation(b))
		new_global[b] = g
	var pb: int = _bones["pelvis"]
	if pb >= 0:
		var bob := (c * c) * lerpf(0.015, 0.05, run) * moving * ground
		skel.set_bone_pose_position(pb, skel.get_bone_rest(pb).origin + Vector3(0, bob - crouch * 0.16 - _air * 0.04, 0))
