extends SceneTree
## Headless validation of the secondary cloth system.
## godot --headless -s res://tests/cloth_tests.gd
##
## Every scenario moves the outfit like a character controller would (world motion +
## leg swing) and steps the simulator at 60 fps, then checks stability and behaviour.

const DT := 1.0 / 60.0
const ALL_OUTFITS := {
	"mustang": "res://assets/outfits/tenue_mustang.glb",
	"edward": "res://assets/outfits/tenue_edward.glb",
	"riza": "res://assets/outfits/tenue_riza.glb",
	"olivier": "res://assets/outfits/tenue_olivier.glb",
	"scar": "res://assets/outfits/tenue_scar.glb",
	"winry": "res://assets/outfits/tenue_winry.glb",
}

var failures := 0
var world: Node3D
var outfit: ClothOutfit
var sim: SecondaryClothSimulator
var skel: Skeleton3D
var wind: ClothWindZone
var yaw := 0.0
var phase := 0.0
var rest_rot := {}
var max_len_err := 0.0
var max_angle_excess := 0.0
var max_penetration := 0.0
var max_body_penetration := 0.0
var nan_found := false
var sim_usec := 0
var sim_calls := 0
var scenario := ""
var worst := ""


var OUTFITS := {}


func _initialize() -> void:
	# optional filter: godot -s res://tests/cloth_tests.gd -- olivier scar
	var only := OS.get_cmdline_user_args()
	for k in ALL_OUTFITS:
		if only.is_empty() or only.has(k):
			OUTFITS[k] = ALL_OUTFITS[k]
	await process_frame  # the root viewport must be in the tree before adding scenes
	for key in OUTFITS:
		print("\n=== ", key, " ===")
		_setup(key)
		if sim == null:
			return
		_run_all()
		world.queue_free()
		await process_frame
	print("\n", "ALL TESTS PASSED" if failures == 0 else "%d CHECK(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)


var key_name := ""
var rest_off := 0.0
var last_acc := {}


func _setup(key: String) -> void:
	key_name = key
	world = Node3D.new()
	root.add_child(world)
	wind = ClothWindZone.new()
	wind.enabled = false
	world.add_child(wind)
	outfit = ClothOutfit.new()
	outfit.preset = key
	outfit.add_child(load(OUTFITS[key]).instantiate())
	world.add_child(outfit)
	skel = outfit.skeleton
	sim = outfit.simulator
	if skel == null or sim == null:
		push_error("outfit setup failed")
		quit(2)
		return
	sim.active = false  # stepped manually for determinism
	rest_rot.clear()
	for b in skel.get_bone_count():
		rest_rot[b] = skel.get_bone_pose_rotation(b)
	yaw = 0.0
	phase = 0.0
	max_len_err = 0.0
	max_angle_excess = 0.0
	max_penetration = 0.0
	max_body_penetration = 0.0
	nan_found = false
	sim_usec = 0
	sim_calls = 0
	_frame(Vector3.ZERO)
	print("chains: ", sim.get_particle_count(), " particles, groups ", sim.get_group_names())


func _check(cond: bool, what: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		failures += 1


# --------------------------------------------------------------------------- driving

func _pose_legs(speed: float) -> void:
	# simple gait on the body bones: what an animation would do
	phase += DT * (1.6 + speed * 0.9)
	var amp := clampf(speed / 6.0, 0.0, 1.0) * 0.8 + (0.25 if speed > 0.05 else 0.0)
	for side in [["thigh.L", 0.0], ["thigh.R", PI]]:
		var b := skel.find_bone(side[0])
		var a := sin(phase * TAU * 0.5 + side[1]) * amp * 0.6
		skel.set_bone_pose_rotation(b, Quaternion(Vector3.RIGHT, a) * rest_rot[b])


func _frame(velocity: Vector3, speed_for_legs := -1.0, yaw_rate := 0.0) -> void:
	outfit.global_position += velocity * DT
	yaw += yaw_rate * DT
	outfit.rotation.y = yaw
	_pose_legs(velocity.length() if speed_for_legs < 0.0 else speed_for_legs)
	var t0 := Time.get_ticks_usec()
	sim.simulate(skel, DT)
	sim_usec += Time.get_ticks_usec() - t0
	sim_calls += 1
	_measure()


func _measure() -> void:
	for g in sim.get_group_names():
		var caps := sim.get_group_colliders(g)
		var prof: ClothProfile
		for res in sim.groups:
			if res.name == g:
				prof = res.profile
		for c in sim.get_chain_count(g):
			var pts := sim.get_chain_points(g, c)
			var anim := sim.get_chain_animated_points(g, c)
			var lens := sim.get_chain_rest_lengths(g, c)
			for i in range(1, pts.size()):
				if not pts[i].is_finite():
					nan_found = true
					continue
				var seg := pts[i] - pts[i - 1]
				max_len_err = maxf(max_len_err, absf(seg.length() - lens[i - 1]) / lens[i - 1])
				var ad := anim[i] - anim[i - 1]
				var ang := rad_to_deg(seg.angle_to(ad))
				max_angle_excess = maxf(max_angle_excess, ang - prof.max_angle)
				for k in caps.size():
					var a: Vector3 = caps[k][0]
					var b: Vector3 = caps[k][1]
					var r: float = caps[k][2]
					var ab := b - a
					var t := clampf((pts[i] - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
					var d := pts[i].distance_to(a + ab * t)
					max_body_penetration = maxf(max_body_penetration, r - prof.thickness - d)
					if r - d > max_penetration:
						max_penetration = r - d
						worst = "%s %s chain %d particle %d capsule %d during %s | r=%.3f d=%.3f root_d=%.3f prev_d=%.3f ang_to_anim=%.1f" % [key_name, g, c, i, k, scenario,
							r, d, SecondaryClothSimulator._seg_dist(pts[0], a, b), SecondaryClothSimulator._seg_dist(pts[i - 1], a, b), ang]


## Mean offset of the coat tips from their animated position (world space).
func _tip_offset(group := "coat") -> Vector3:
	var acc := Vector3.ZERO
	var n := sim.get_chain_count(group)
	for c in n:
		var pts := sim.get_chain_points(group, c)
		var anim := sim.get_chain_animated_points(group, c)
		acc += pts[pts.size() - 1] - anim[anim.size() - 1]
	return acc / maxf(n, 1)


## Mean distance of the coat tips from their animated position (does not cancel out
## around a closed skirt, unlike the mean vector).
func _tip_spread(group := "coat") -> float:
	var acc := 0.0
	var n := sim.get_chain_count(group)
	for c in n:
		var pts := sim.get_chain_points(group, c)
		var anim := sim.get_chain_animated_points(group, c)
		acc += pts[pts.size() - 1].distance_to(anim[anim.size() - 1])
	return acc / maxf(n, 1)


func _tip_speed(group := "coat") -> float:
	var a := _tip_offset(group)
	_frame(Vector3.ZERO)
	return (_tip_offset(group) - a).length() / DT


func _idle(seconds: float) -> void:
	for i in int(seconds / DT):
		_frame(Vector3.ZERO)


# --------------------------------------------------------------------------- scenarios

func _run_all() -> void:
	_idle(3.0)
	rest_off = _tip_spread()
	_check(rest_off < 0.06, "at rest the coat hangs on its animated pose (tip offset %.3f m)" % rest_off)

	# walk forward (-Z), 1.4 m/s
	scenario = "walk"
	var walk_trail := 0.0
	for i in 150:
		_frame(Vector3(0, 0, -1.4))
		walk_trail += _tip_offset().z / 150.0
	# run 6 m/s
	scenario = "run"
	var run_trail := 0.0
	for i in 120:
		_frame(Vector3(0, 0, -6.0))
		if i >= 60:
			run_trail += _tip_offset().z / 60.0
	print("  walk trail %.3f m, run trail %.3f m (backward = +Z)" % [walk_trail, run_trail])
	_check(walk_trail > 0.005, "walking: light trailing of the fabric")
	_check(run_trail > walk_trail * 2.0 and run_trail > 0.04, "running: clearly stronger drag than walking")

	# abrupt stop: the coat swings forward (-Z) past the legs then settles progressively
	scenario = "stop"
	var min_z := 0.0
	var samples := []
	for i in 180:
		_frame(Vector3.ZERO)
		min_z = minf(min_z, _tip_offset().z)
		samples.append(_tip_offset().length())
	print("  stop overshoot %.3f m, offset after 1 s %.3f, after 3 s %.3f" % [-min_z, samples[59], samples[179]])
	_check(min_z < -0.02, "sudden stop: inertia carries the coat forward")
	var peak := 0.0
	for i in 30:
		peak = maxf(peak, samples[i])
	_check(absf(samples[179] - rest_off) < 0.02 and samples[179] < peak * 0.5,
		"the fabric returns progressively to equilibrium")
	# jitter = acceleration of a tip that flips direction every frame (frame-rate shaking).
	# A swinging coat may accelerate strongly, but smoothly.
	var flips := 0
	last_acc.clear()
	var n_chains := sim.get_chain_count("coat")
	var hist := []
	for _k in 3:
		hist.append([])
	for i in 90:
		_frame(Vector3.ZERO)
		var tips := []
		for c in n_chains:
			var pts := sim.get_chain_points("coat", c)
			tips.append(pts[pts.size() - 1])
		hist.pop_front()
		hist.append(tips)
		if i >= 3 and not hist[0].is_empty():
			for c in n_chains:
				var a1: Vector3 = hist[2][c] - 2.0 * hist[1][c] + hist[0][c]
				var a0: Vector3 = last_acc.get(c, Vector3.ZERO)
				if a1.length() > 0.0005 and a0.length() > 0.0005 and a1.dot(a0) < -0.5 * a1.length() * a0.length():
					flips += 1
				last_acc[c] = a1
	_check(flips <= 2, "no jitter while settling (%d frame-rate direction flips)" % flips)

	# settle long enough to sleep
	scenario = "idle"
	_idle(4.0)
	_check(sim.is_group_sleeping("coat"), "still character: simulation goes to sleep (no CPU, no micro-jitter)")

	# jump: ballistic 4.5 m/s up, then landing
	scenario = "jump"
	var vy := 4.5
	var y := 0.0
	var air_react := 0.0
	var fall_lift := 0.0
	while true:
		vy -= 9.8 * DT
		y += vy * DT
		if y <= 0.0:
			break
		_frame(Vector3(0, vy, 0), 0.0)
		air_react = maxf(air_react, _tip_spread())
		if vy < -2.0:
			fall_lift = maxf(fall_lift, _tip_offset().y)
	outfit.global_position.y = 0.0
	var land_peak := 0.0
	var land_after := 0.0
	for i in 90:
		_frame(Vector3.ZERO)
		if i < 30:
			land_peak = maxf(land_peak, _tip_spread())
		land_after = _tip_spread()
	print("  jump: max reaction in the air %.3f m, lift while falling %.3f m, landing %.3f m -> %.3f m after 1.5 s"
		% [air_react, fall_lift, land_peak, land_after])
	_check(air_react > 0.015, "jump: the fabric follows the impulse with its own motion")
	var hem_len := 0.0
	for l in sim.get_chain_rest_lengths("coat", 0):
		hem_len += l
	_check(fall_lift > hem_len * 0.015, "fall: air opens / lifts the hem (%.1f %% of the %.2f m panel)"
		% [fall_lift / hem_len * 100.0, hem_len])
	_check(land_peak > land_after * 1.5 and land_after < rest_off + 0.03, "landing: impact reaction, then back to rest")
	_idle(2.0)

	# fast 180° turn in 0.35 s
	scenario = "turn"
	var side_swing := 0.0
	for i in 21:
		_frame(Vector3.ZERO, 0.0, PI / 0.35)
		side_swing = maxf(side_swing, _tip_spread())
	for i in 30:
		_frame(Vector3.ZERO)
		side_swing = maxf(side_swing, _tip_spread())
	print("  turn: secondary swing %.3f m" % side_swing)
	_check(side_swing > 0.03, "fast rotation: secondary swing of the fabric")
	_idle(2.0)

	# zig-zag (sudden change of direction while running)
	scenario = "zigzag"
	var zig := 0.0
	for i in 90:
		var dir := 1.0 if (i / 30) % 2 == 0 else -1.0
		_frame(Vector3(dir * 5.0, 0, -3.0))
		zig = maxf(zig, absf(_tip_offset().x))
	_check(zig > 0.04, "change of direction: lateral inertia (%.3f m)" % zig)
	_idle(2.0)

	# wind
	scenario = "wind"
	wind.enabled = true
	wind.strength = 7.0
	wind.rotation = Vector3(0, PI * 0.5, 0)  # blows toward -X
	var wsum := Vector3.ZERO
	var wvals := []
	for i in 240:
		_frame(Vector3.ZERO)
		if i >= 60:
			var o := _tip_offset()
			wsum += o / 180.0
			wvals.append(o.x)
	var mean := 0.0
	for v in wvals:
		mean += v / wvals.size()
	var variance := 0.0
	for v in wvals:
		variance += (v - mean) * (v - mean) / wvals.size()
	print("  wind: mean tip offset %s, std %.4f m" % [wsum, sqrt(variance)])
	_check(wsum.x < -0.02, "wind pushes the fabric downwind")
	_check(sqrt(variance) > 0.002, "wind ripples are irregular (gusts + turbulence)")
	wind.enabled = false
	_idle(3.0)

	# teleport
	scenario = "teleport"
	outfit.global_position += Vector3(30, 0, 0)
	_frame(Vector3.ZERO)
	_check(_tip_offset().length() < 0.08, "teleport: no whip across the map")

	var ms := float(sim_usec) / sim_calls / 1000.0
	print("  max segment length error %.5f %%, max angle excess %.2f°, max penetration %.4f m, %.3f ms/frame"
		% [max_len_err * 100.0, max_angle_excess, max_penetration, ms])
	_check(not nan_found, "numerically stable (no NaN/inf)")
	_check(max_len_err < 0.002, "no stretching: segment lengths are preserved")
	_check(max_angle_excess < 30.0, "angle limit respected; only body collisions may push past it (%.1f°)" % max_angle_excess)
	print("  worst penetration of the fabric margin: ", worst)
	_check(max_body_penetration < 0.005, "fabric never goes through the body (max %.4f m)" % max_body_penetration)
	_check(max_penetration < 0.025, "fabric thickness margin mostly respected (max %.4f m)" % max_penetration)
	_check(ms < 1.5, "real-time budget (%.3f ms per frame in GDScript)" % ms)
