class_name SecondaryClothSimulator
extends SkeletonModifier3D
## Real-time secondary motion for clothes, driven by the real motion of the skeleton.
##
## Each cloth chain (coat panel, cape strip, cord, holster...) is a string of particles
## integrated with time-corrected Verlet in world space:
## [br]- the chain root is pinned to the animated skeleton, so walking, running, jumping,
##   landing, turning and sudden direction changes all create inertia naturally;
## [br]- relative air speed (character motion + [ClothWindZone]) produces drag and flutter;
## [br]- segments are pulled back to the animated pose ([member ClothProfile.pose_stiffness]);
## [br]- neighbouring chains are linked so skirts and capes fold instead of splitting;
## [br]- capsules attached to the body bones keep the fabric out of the legs and torso;
## [br]- bones are only rotated, never translated, so the mesh can never stretch.
##
## Add it as a child of the [Skeleton3D] (after any IK / procedural animation modifier).

@export var groups: Array[ClothChainGroup] = []
@export var colliders: Array[ClothCollider] = []
## At start-up, pre-compensate gravity so the cloth rests exactly on the authored shape
## (assumes the character stands upright when the outfit is loaded).
@export var calibrate_rest_pose := true
## Upper bound of one simulation step (s). Frames longer than this are split into substeps.
@export_range(0.002, 0.05, 0.001) var max_step := 1.0 / 60.0
@export_range(1, 16) var max_substeps := 6
@export var gravity := Vector3(0.0, -9.8, 0.0)
## A root that moves further than this in one frame is treated as a teleport (no whip).
@export var teleport_distance := 2.0
## Read [ClothWindZone] nodes of the scene tree.
@export var use_wind_zones := true
## Extra wind (m/s) added to the zones, handy for scripted events.
@export var extra_wind := Vector3.ZERO
@export var debug_draw := false:
	set(v):
		debug_draw = v
		if is_inside_tree():
			_update_debug_mesh()

const STILL_SPEED := 0.08  # m/s below which the character is considered still
const STILL_TURN := 0.35  # rad/s
const MAX_REL_SPEED := 9.0  # m/s, safety clamp of particle speed relative to the root


class Chain:
	extends RefCounted
	var name := ""
	var bones := PackedInt32Array()
	var parent := -1
	var lengths := PackedFloat32Array()
	var axes: Array[Vector3] = []  # segment direction in bone space
	var angle := 0.0
	var x := PackedVector3Array()  # world positions, size bones + 1 (last = virtual tip)
	var xp := PackedVector3Array()  # previous positions
	var anim_a := PackedVector3Array()  # animated positions at previous frame
	var anim_b := PackedVector3Array()  # animated positions at this frame
	var an := PackedVector3Array()  # animated positions at the current substep
	var base_rot: Array[Quaternion] = []  # animated local rotation of every bone
	var written: Array[Quaternion] = []  # rotation written by the simulator last frame
	var stiff := PackedFloat32Array()  # per-segment stiffness multiplier
	var bias: Array[Vector3] = []  # rest-pose gravity compensation, in parent bone space


class Group:
	extends RefCounted
	var res: ClothChainGroup
	var chains: Array[Chain] = []
	var links: Array[Vector2i] = []  # chain indices
	var still_time := 0.0
	var sleeping := false
	var parent_a := Transform3D()
	var parent_b := Transform3D()
	var caps: Array[Capsule] = []
	var radii := PackedFloat32Array()  # collider radius + fabric thickness, fitted to the rest pose
	# per step cache: capsule start, axis, 1/|axis|², bounding-sphere centre and radius²
	var c_a := PackedVector3Array()
	var c_ab := PackedVector3Array()
	var c_inv := PackedFloat32Array()
	var c_mid := PackedVector3Array()
	var c_reach := PackedFloat32Array()


class Capsule:
	extends RefCounted
	var res: ClothCollider
	var bone := -1
	var end_bone := -1
	var a0 := Vector3.ZERO
	var b0 := Vector3.ZERO
	var a1 := Vector3.ZERO
	var b1 := Vector3.ZERO
	var a := Vector3.ZERO
	var b := Vector3.ZERO


var _groups: Array[Group] = []
var _capsules: Array[Capsule] = []
var _ready_done := false
var _time := 0.0
var _h_prev := 0.0
var _wind_zones: Array[Node] = []
var _debug_mesh: MeshInstance3D
var _stats_steps := 0


func _ready() -> void:
	_update_debug_mesh()


## Rebuilds the chains from the skeleton. Call after changing [member groups] at runtime.
func rebuild() -> void:
	_ready_done = false


## Snaps every particle to the animated pose (after a teleport, a cutscene cut...).
func reset_cloth() -> void:
	for g in _groups:
		for c in g.chains:
			c.x = c.anim_b.duplicate()
			c.xp = c.anim_b.duplicate()
			c.anim_a = c.anim_b.duplicate()
		g.still_time = 0.0
		g.sleeping = false


## Number of simulated particles (for profiling / UI).
func get_particle_count() -> int:
	var n := 0
	for g in _groups:
		for c in g.chains:
			n += c.x.size() - 1
	return n


func get_group_names() -> PackedStringArray:
	var out := PackedStringArray()
	for g in _groups:
		out.append(g.res.name)
	return out


## Read-only access used by tests and debug tools: world positions of a chain.
func get_chain_points(group_name: String, chain_index: int) -> PackedVector3Array:
	for g in _groups:
		if g.res.name == group_name and chain_index < g.chains.size():
			return g.chains[chain_index].x
	return PackedVector3Array()


func get_chain_count(group_name: String) -> int:
	for g in _groups:
		if g.res.name == group_name:
			return g.chains.size()
	return 0


func get_chain_rest_lengths(group_name: String, chain_index: int) -> PackedFloat32Array:
	for g in _groups:
		if g.res.name == group_name:
			return g.chains[chain_index].lengths
	return PackedFloat32Array()


func get_chain_animated_points(group_name: String, chain_index: int) -> PackedVector3Array:
	for g in _groups:
		if g.res.name == group_name:
			return g.chains[chain_index].anim_b
	return PackedVector3Array()


func is_group_sleeping(group_name: String) -> bool:
	for g in _groups:
		if g.res.name == group_name:
			return g.sleeping
	return false


## [a, b, radius incl. thickness] of the colliders acting on a group.
func get_group_colliders(group_name: String) -> Array:
	var out := []
	for g in _groups:
		if g.res.name == group_name:
			for k in g.caps.size():
				out.append([g.caps[k].a, g.caps[k].b, g.radii[k]])
	return out


# ------------------------------------------------------------------------------ setup

func _setup(skel: Skeleton3D) -> void:
	_groups.clear()
	_capsules.clear()
	for res in groups:
		if res == null:
			continue
		if res.profile == null:
			res.profile = ClothProfile.classic()
		var g := Group.new()
		g.res = res
		_collect_chains(skel, g)
		if g.chains.is_empty():
			push_warning("SecondaryClothSimulator: no bone matches prefix '%s'" % res.bone_prefix)
			continue
		_build_links(g)
		_groups.append(g)
	for res in colliders:
		if res == null:
			continue
		var cap := Capsule.new()
		cap.res = res
		cap.bone = skel.find_bone(res.bone)
		cap.end_bone = skel.find_bone(res.end_bone) if res.end_bone != "" else -1
		if cap.bone < 0:
			push_warning("SecondaryClothSimulator: collider bone '%s' not found" % res.bone)
			continue
		_capsules.append(cap)
	_update_capsules(skel, true)
	_update_capsules(skel, true)
	for g in _groups:
		_refresh_animation(skel, g, true)
		_fit_colliders(g)
	reset_cloth()
	_ready_done = true
	if calibrate_rest_pose:
		_calibrate()


func _calibrate() -> void:
	var saved_wind := use_wind_zones
	var saved_extra := extra_wind
	use_wind_zones = false
	extra_wind = Vector3.ZERO
	_wind_zones = []
	for _pass in 4:
		for _s in 90:
			for g in _groups:
				g.still_time = 0.0  # keep the normal damping: we want the true equilibrium
				_step_group(g, max_step, 0.0, 1.0)
			_h_prev = max_step
		for g in _groups:
			var pinv := g.parent_b.basis.orthonormalized().inverse()
			for c in g.chains:
				for i in range(1, c.x.size()):
					c.bias[i - 1] += pinv * (c.anim_b[i] - c.x[i])
	reset_cloth()
	use_wind_zones = saved_wind
	extra_wind = saved_extra


func _collect_chains(skel: Skeleton3D, g: Group) -> void:
	var re := RegEx.new()
	re.compile("^" + _regex_escape(g.res.bone_prefix) + "(.+)_(\\d+)$")
	var found := {}
	for b in skel.get_bone_count():
		var m := re.search(skel.get_bone_name(b))
		if m == null:
			continue
		var id := g.res.bone_prefix + m.get_string(1)
		if not found.has(id):
			found[id] = {}
		found[id][int(m.get_string(2))] = b
	var skel_rest := {}
	for id in found:
		var idx: Array = found[id].keys()
		idx.sort()
		var c := Chain.new()
		c.name = id
		for k in idx:
			c.bones.append(found[id][k])
		var ok := true
		for i in range(1, c.bones.size()):
			if skel.get_bone_parent(c.bones[i]) != c.bones[i - 1]:
				ok = false
		if not ok:
			push_warning("SecondaryClothSimulator: chain %s is not a parent/child sequence" % id)
			continue
		c.parent = skel.get_bone_parent(c.bones[0])
		var n := c.bones.size()
		for i in n:
			if i < n - 1:
				var off := skel.get_bone_rest(c.bones[i + 1]).origin
				c.lengths.append(off.length())
				c.axes.append(off.normalized())
			else:
				var l := c.lengths[i - 1] * g.res.tip_length_scale if i > 0 else 0.15 * g.res.tip_length_scale
				c.lengths.append(l)
				c.axes.append(c.axes[i - 1] if i > 0 else Vector3.UP)
			var r := skel.get_bone_pose_rotation(c.bones[i])
			c.base_rot.append(r)
			c.written.append(Quaternion(INF, INF, INF, INF))
			var t := float(i) / maxf(1.0, float(n - 1))
			c.stiff.append(lerpf(1.0, g.res.profile.tip_stiffness_scale, t))
			c.bias.append(Vector3.ZERO)
		c.x.resize(n + 1)
		c.xp.resize(n + 1)
		c.anim_a.resize(n + 1)
		c.anim_b.resize(n + 1)
		# angle of the chain around the parent's vertical axis (rest pose, skeleton space)
		var pg := _rest_global(skel, c.parent, skel_rest)
		var tip := _rest_global(skel, c.bones[n - 1], skel_rest)
		var local := pg.affine_inverse() * tip.origin
		c.angle = atan2(local.x, local.z)
		g.chains.append(c)
	g.chains.sort_custom(func(a: Chain, b: Chain) -> bool: return a.angle < b.angle)


func _build_links(g: Group) -> void:
	if not g.res.link_neighbours or g.chains.size() < 2:
		return
	var slit := {}
	for s in g.res.slits:
		var p := s.split(":")
		if p.size() == 2:
			slit[p[0] + ":" + p[1]] = true
			slit[p[1] + ":" + p[0]] = true
	var n := g.chains.size()
	var count := n if g.res.closed_loop else n - 1
	for i in count:
		var j := (i + 1) % n
		var a := g.chains[i]
		var b := g.chains[j]
		var gap := absf(wrapf(b.angle - a.angle, -PI, PI))
		if rad_to_deg(gap) > g.res.max_link_angle:
			continue
		if slit.has(a.name + ":" + b.name):
			continue
		g.links.append(Vector2i(i, j))


## Colliders never intersect the animated pose: a capsule that would cut through the
## garment at rest is shrunk for this group (or dropped when it can't fit).
func _fit_colliders(g: Group) -> void:
	g.caps.clear()
	g.radii.clear()
	for cap in _capsules:
		if g.res.ignored_colliders.has(cap.res.name):
			continue
		var r := cap.res.radius + g.res.profile.thickness
		for c in g.chains:
			for i in c.anim_b.size():  # roots included: a pinned point inside a capsule is unsolvable
				r = minf(r, _seg_dist(c.anim_b[i], cap.a, cap.b) - 0.006)
		if r < 0.025:
			continue
		g.caps.append(cap)
		g.radii.append(r)


static func _seg_dist(q: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var ab2 := ab.length_squared()
	var t := 0.0 if ab2 < 1e-12 else clampf((q - a).dot(ab) / ab2, 0.0, 1.0)
	return q.distance_to(a + ab * t)


func _rest_global(skel: Skeleton3D, bone: int, cache: Dictionary) -> Transform3D:
	if bone < 0:
		return Transform3D()
	if cache.has(bone):
		return cache[bone]
	var t := _rest_global(skel, skel.get_bone_parent(bone), cache) * skel.get_bone_rest(bone)
	cache[bone] = t
	return t


static func _regex_escape(s: String) -> String:
	var out := ""
	for ch in s:
		if "\\^$.|?*+()[]{}".contains(ch):
			out += "\\"
		out += ch
	return out


# ------------------------------------------------------------------------------ per frame

func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	# engine delta: follows Engine.time_scale (slow motion, pause) and fixed-fps captures
	var dt := get_physics_process_delta_time() \
		if skel.modifier_callback_mode_process == Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS \
		else get_process_delta_time()
	if not _ready_done:
		_setup(skel)
		return
	simulate(skel, dt)


## Advances the simulation by [param dt] seconds and writes the bones. Called automatically;
## exposed for deterministic tests (call it instead of letting the skeleton process).
func simulate(skel: Skeleton3D, dt: float) -> void:
	if not _ready_done:
		_setup(skel)
	dt = clampf(dt, 0.0, 0.1)
	_update_capsules(skel, false)
	for g in _groups:
		_refresh_animation(skel, g, false)
	if dt > 0.0:
		_wind_zones = get_tree().get_nodes_in_group(ClothWindZone.GROUP) if use_wind_zones and is_inside_tree() else []
		var steps := clampi(ceili(dt / max_step - 0.001), 1, max_substeps)
		var h := dt / steps
		for g in _groups:
			_update_settle(g, dt)
		for s in steps:
			var f := float(s + 1) / steps
			_time += h
			for cap in _capsules:
				cap.a = cap.a0.lerp(cap.a1, f)
				cap.b = cap.b0.lerp(cap.b1, f)
			for g in _groups:
				_step_group(g, h, float(s) / steps, f)
			_h_prev = h
			_stats_steps += 1
	for g in _groups:
		_write_bones(skel, g)
	if debug_draw:
		_draw_debug()


func _refresh_animation(skel: Skeleton3D, g: Group, first: bool) -> void:
	var sk := skel.global_transform
	var pg := skel.get_bone_global_pose(g.chains[0].parent)
	g.parent_a = g.parent_b if not first else sk * pg
	g.parent_b = sk * pg
	for c in g.chains:
		var parent_global := skel.get_bone_global_pose(c.parent)
		c.anim_a = c.anim_b.duplicate() if not first else c.anim_a
		var n := c.bones.size()
		var gpose := parent_global
		for i in n:
			var b := c.bones[i]
			var cur := skel.get_bone_pose_rotation(b)
			# keep the animated rotation unless the pose is the one we wrote last frame
			if not cur.is_equal_approx(c.written[i]):
				c.base_rot[i] = cur
			gpose = gpose * Transform3D(Basis(c.base_rot[i]).scaled(skel.get_bone_pose_scale(b)), skel.get_bone_pose_position(b))
			c.anim_b[i] = sk * gpose.origin
			if i == n - 1:
				c.anim_b[n] = sk * (gpose.origin + gpose.basis * c.axes[i] * c.lengths[i])
		if first:
			c.anim_a = c.anim_b.duplicate()
	# teleport: no whip
	if not first and g.parent_a.origin.distance_to(g.parent_b.origin) > teleport_distance:
		for c in g.chains:
			c.anim_a = c.anim_b.duplicate()
			c.x = c.anim_b.duplicate()
			c.xp = c.anim_b.duplicate()
		g.parent_a = g.parent_b


func _update_capsules(skel: Skeleton3D, first: bool) -> void:
	var sk := skel.global_transform
	for cap in _capsules:
		var bt := sk * skel.get_bone_global_pose(cap.bone)
		var a := bt * cap.res.start_offset
		var b: Vector3
		if cap.end_bone >= 0:
			b = (sk * skel.get_bone_global_pose(cap.end_bone)) * cap.res.end_offset
		elif cap.res.length > 0.0:
			b = bt * (cap.res.end_offset + Vector3.UP * cap.res.length)
		else:
			b = bt * cap.res.end_offset
		cap.a0 = a if first else cap.a1
		cap.b0 = b if first else cap.b1
		cap.a1 = a
		cap.b1 = b
		cap.a = a
		cap.b = b


func _update_settle(g: Group, dt: float) -> void:
	var p := g.res.profile
	var lin := g.parent_a.origin.distance_to(g.parent_b.origin) / dt
	var rot := (g.parent_a.basis.orthonormalized().inverse() * g.parent_b.basis.orthonormalized()).get_rotation_quaternion().get_angle() / dt
	var wind := _wind_at(g.parent_b.origin).length() * p.wind_sensitivity
	if lin > STILL_SPEED or rot > STILL_TURN or wind > 0.75:
		g.still_time = 0.0
		g.sleeping = false
	else:
		g.still_time += dt
	if g.sleeping:
		return
	if g.still_time > p.settle_time + 1.0:
		var max_v := 0.0
		for c in g.chains:
			for i in range(1, c.x.size()):
				max_v = maxf(max_v, c.x[i].distance_squared_to(c.xp[i]))
		if max_v < 1e-10:
			g.sleeping = true


func _wind_at(pos: Vector3) -> Vector3:
	var w := extra_wind
	for z in _wind_zones:
		w += z.sample(pos, _time)
	return w


func _step_group(g: Group, h: float, f0: float, f1: float) -> void:
	# Hot path. Packed arrays are copied to locals and written back once: in GDScript,
	# writing an element of another object's packed array copies the whole array.
	var p := g.res.profile
	var settle := smoothstep(0.0, maxf(p.settle_time, 0.001), g.still_time)
	var damp := exp(-lerpf(p.damping, p.settle_damping, settle) * h)
	var h_ratio := h / _h_prev if _h_prev > 0.0 else 1.0
	# parent motion during this substep, partially transferred to the particles
	var pa := g.parent_a.interpolate_with(g.parent_b, f0)
	var pb := g.parent_a.interpolate_with(g.parent_b, f1)
	var delta := pb * pa.affine_inverse()
	var transfer := 1.0 if g.sleeping else p.inertia_transfer
	var acc_g := gravity * p.gravity_scale
	var t := _time
	var up := -gravity.normalized() if gravity.length_squared() > 0.0 else Vector3.UP
	var hh := h * h
	var lim := MAX_REL_SPEED * h
	var pbasis := pb.basis.orthonormalized()
	var flutter := p.flutter
	var flare := p.flare * p.air_drag
	var drag := p.air_drag
	var ci := 0
	for c in g.chains:
		var n := c.x.size()
		var an := PackedVector3Array()
		an.resize(n)
		var aa := c.anim_a
		var ab := c.anim_b
		for i in n:
			an[i] = aa[i].lerp(ab[i], f1)
		c.an = an
		var x := c.x
		var xp := c.xp
		var root := an[0]
		var root_move := root - x[0]
		x[0] = root
		xp[0] = root
		var air := Vector3.ZERO if g.sleeping else _wind_at(x[n >> 1]) * p.wind_sensitivity
		for i in range(1, n):
			if transfer > 0.0:
				x[i] = x[i].lerp(delta * x[i], transfer)
				xp[i] = xp[i].lerp(delta * xp[i], transfer)
			if g.sleeping:
				continue
			var xi := x[i]
			var v := (xi - xp[i]) * (h_ratio * damp)
			var rel := air - v / h
			var along := float(i) / (n - 1)
			if flutter > 0.0:
				# incommensurate sines: irregular flapping that grows with the relative air speed
				var fl := rel.length() * flutter * along * 0.6
				var k := ci * 1.73 + i * 2.31
				rel += Vector3(sin(t * 11.0 + k) + sin(t * 4.3 + k * 1.9) * 0.6,
					sin(t * 7.7 + k * 0.7) * 0.5,
					sin(t * 13.1 + k * 1.3) + sin(t * 5.1 + k * 2.7) * 0.6) * fl
			var a := acc_g + rel * drag
			if flare > 0.0:
				# air flowing from the hem toward the waist opens the skirt outward
				var seg := xi - x[i - 1]
				var axial := rel.dot(seg) / maxf(seg.length(), 1e-5)
				if axial < 0.0:
					var radial := xi - pb.origin
					radial -= up * radial.dot(up)
					if radial.length_squared() > 1e-6:
						a += radial.normalized() * (-axial * flare * along)
			var step := v + a * hh
			# safety: limit speed relative to the root so fast animations stay stable
			var rel_step := step - root_move
			if rel_step.length_squared() > lim * lim:
				step = root_move + rel_step.normalized() * lim
			xp[i] = xi
			x[i] = xi + step
		if not g.sleeping:
			# pull every segment toward its animated direction (local, cascades down the chain)
			var bias := c.bias
			var stiff := c.stiff
			for i in range(1, n):
				var target := x[i - 1] + (an[i] - an[i - 1]) + pbasis * bias[i - 1]
				x[i] += (target - x[i]) * (1.0 - exp(-p.pose_stiffness * stiff[i - 1] * h))
		c.x = x
		c.xp = xp
		ci += 1
	if g.sleeping:
		for c in g.chains:
			_follow_the_leader(c, g, true)
		return
	_prepare_caps(g)
	# rest distances of the links for this substep
	var lat := p.lateral_stiffness * 0.35
	var lo := p.lateral_min_ratio
	var hi := p.lateral_max_stretch
	var rests: Array[PackedFloat32Array] = []
	for l in g.links:
		var a_an := g.chains[l.x].an
		var b_an := g.chains[l.y].an
		var r := PackedFloat32Array()
		r.resize(mini(a_an.size(), b_an.size()))
		for i in r.size():
			r[i] = a_an[i].distance_to(b_an[i])
		rests.append(r)
	var mid_iter := p.iterations >> 1
	for it in p.iterations:
		# links between neighbouring chains: soft, hard limits on stretch and on overlap
		for li in g.links.size():
			var l := g.links[li]
			var ca := g.chains[l.x]
			var cb := g.chains[l.y]
			var xa := ca.x
			var xb := cb.x
			var r := rests[li]
			for i in range(1, r.size()):
				var d := xb[i] - xa[i]
				var dl := d.length()
				if dl < 1e-6:
					continue
				var target := clampf(lerpf(dl, r[i], lat), r[i] * lo, r[i] * hi)
				var corr := d * ((dl - target) / dl * 0.5)
				xa[i] += corr
				xb[i] -= corr
			ca.x = xa
			cb.x = xb
		# inextensible segments
		for c in g.chains:
			var x := c.x
			var lens := c.lengths
			for i in range(1, x.size()):
				var d := x[i] - x[i - 1]
				var dl := d.length()
				if dl < 1e-6:
					continue
				var corr := d * ((dl - lens[i - 1]) / dl)
				if i == 1:
					x[i] -= corr
				else:
					x[i] -= corr * 0.5
					x[i - 1] += corr * 0.5
			c.x = x
			if it == mid_iter:
				_collide(c, g, 0.0)
	# collisions last: they win over the angle limit (cloth inside the body is worse
	# than a wide swing) and keep the segment lengths
	for c in g.chains:
		_follow_the_leader(c, g, true)
		if _collide(c, g, 0.2):
			_collide(c, g, 0.0)  # a push near the root can move a child into another capsule


## Enforces exact segment lengths, the max angle to the animated pose and the max bend
## of every joint relative to the authored curvature.
func _follow_the_leader(c: Chain, g: Group, limit_angle := true) -> void:
	var prof := g.res.profile
	var max_cos := cos(deg_to_rad(prof.max_angle))
	var max_a := deg_to_rad(prof.max_angle)
	var bend_cos := cos(deg_to_rad(prof.max_bend))
	var bend_a := deg_to_rad(prof.max_bend)
	var prev_sim := Vector3.ZERO
	var prev_anim := Vector3.ZERO
	var x := c.x
	var an := c.an
	var lens := c.lengths
	for i in range(1, x.size()):
		var d := x[i] - x[i - 1]
		var ad := (an[i] - an[i - 1]).normalized()
		var dn := d.normalized() if d.length_squared() > 1e-12 else ad
		if limit_angle:
			if dn.dot(ad) < max_cos:
				dn = _clamp_dir(dn, ad, max_a)
			if i > 1 and prev_anim.dot(prev_sim) < 0.99999:
				# authored bend carried by the parent segment
				var expected := _arc(prev_anim, prev_sim) * ad
				if dn.dot(expected) < bend_cos:
					dn = _clamp_dir(dn, expected, bend_a)
			elif i > 1 and dn.dot(ad) < bend_cos:
				dn = _clamp_dir(dn, ad, bend_a)
		x[i] = x[i - 1] + dn * lens[i - 1]
		prev_sim = dn
		prev_anim = ad
	c.x = x


static func _clamp_dir(dir: Vector3, center: Vector3, max_angle: float) -> Vector3:
	var axis := center.cross(dir)
	if axis.length_squared() < 1e-10:
		axis = center.cross(Vector3.RIGHT if absf(center.x) < 0.9 else Vector3.FORWARD)
	return center.rotated(axis.normalized(), max_angle)


func _prepare_caps(g: Group) -> void:
	var n := g.caps.size()
	g.c_a.resize(n)
	g.c_ab.resize(n)
	g.c_inv.resize(n)
	g.c_mid.resize(n)
	g.c_reach.resize(n)
	for k in n:
		var cap := g.caps[k]
		var ab := cap.b - cap.a
		var ab2 := ab.length_squared()
		g.c_a[k] = cap.a
		g.c_ab[k] = ab
		g.c_inv[k] = 0.0 if ab2 < 1e-12 else 1.0 / ab2
		g.c_mid[k] = (cap.a + cap.b) * 0.5
		var reach := sqrt(ab2) * 0.5 + g.radii[k]
		g.c_reach[k] = reach * reach


func _collide(c: Chain, g: Group, friction: float) -> bool:
	var hit := false
	var ncap := g.caps.size()
	if ncap == 0:
		return false
	var x := c.x
	var xp := c.xp
	var lens := c.lengths
	var c_mid := g.c_mid
	var c_reach := g.c_reach
	var c_a := g.c_a
	var c_ab := g.c_ab
	var c_inv := g.c_inv
	var radii := g.radii
	for i in range(1, x.size()):
		var start := x[i]
		# solve on the sphere of the segment length around the parent: converges locally,
		# even between two capsules (knee) or next to the attachment point
		for _iter in 8:
			var moved := false
			for k in ncap:
				var q := x[i]
				if q.distance_squared_to(c_mid[k]) > c_reach[k]:
					continue
				var a := c_a[k]
				var ab := c_ab[k]
				var closest := a + ab * clampf((q - a).dot(ab) * c_inv[k], 0.0, 1.0)
				var d := q - closest
				var r := radii[k]
				var dl2 := d.length_squared()
				if dl2 >= r * r:
					continue
				var dl := sqrt(dl2)
				var nrm := d / dl if dl > 1e-6 else (x[i] - x[0]).normalized()
				var pushed := closest + nrm * (r + 0.001)
				x[i] = x[i - 1] + (pushed - x[i - 1]).normalized() * lens[i - 1]
				moved = true
			if not moved:
				break
			hit = true
		if x[i] != start:
			# move the history with the particle: no bounce. Friction on the final pass only.
			xp[i] += x[i] - start
			if friction > 0.0:
				xp[i] = xp[i].lerp(x[i], friction)
			# children follow rigidly so the chain keeps its lengths
			for k in range(i + 1, x.size()):
				var dd := x[k] - x[k - 1]
				x[k] = x[k - 1] + (dd.normalized() if dd.length_squared() > 1e-12 else Vector3.DOWN) * lens[k - 1]
	if hit:
		c.x = x
		c.xp = xp
	return hit


func _write_bones(skel: Skeleton3D, g: Group) -> void:
	var sk_inv := skel.global_transform.affine_inverse()
	var w := g.res.influence
	for c in g.chains:
		var parent_global := skel.get_bone_global_pose(c.parent)
		var pg_basis := parent_global.basis
		var origin := parent_global.origin
		var n := c.bones.size()
		for i in n:
			var b := c.bones[i]
			var lp := Transform3D(Basis(c.base_rot[i]).scaled(skel.get_bone_pose_scale(b)), skel.get_bone_pose_position(b))
			var gb := pg_basis * lp.basis
			var go := origin + pg_basis * lp.origin
			var cur_dir := (gb * c.axes[i]).normalized()
			var want := (sk_inv * c.x[i + 1] - sk_inv * c.x[i]).normalized()
			var q := Quaternion.IDENTITY
			if cur_dir.dot(want) < 0.99999 and want.length_squared() > 0.5:
				q = _arc(cur_dir, want)
			if w < 1.0:
				q = Quaternion.IDENTITY.slerp(q, w)
			var new_gb := Basis(q) * gb
			var local := (pg_basis.inverse() * new_gb).get_rotation_quaternion().normalized()
			skel.set_bone_pose_rotation(b, local)
			c.written[i] = skel.get_bone_pose_rotation(b)
			pg_basis = new_gb
			origin = go


static func _arc(from: Vector3, to: Vector3) -> Quaternion:
	var d := from.dot(to)
	if d < -0.99999:
		var axis := from.cross(Vector3.RIGHT)
		if axis.length_squared() < 1e-6:
			axis = from.cross(Vector3.UP)
		return Quaternion(axis.normalized(), PI)
	return Quaternion(from, to)


# ------------------------------------------------------------------------------ debug

func _update_debug_mesh() -> void:
	if debug_draw and _debug_mesh == null:
		_debug_mesh = MeshInstance3D.new()
		_debug_mesh.top_level = true
		_debug_mesh.mesh = ImmediateMesh.new()
		_debug_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.no_depth_test = true
		_debug_mesh.material_override = mat
		add_child(_debug_mesh, false, Node.INTERNAL_MODE_BACK)
	if _debug_mesh:
		_debug_mesh.visible = debug_draw


func _draw_debug() -> void:
	if _debug_mesh == null:
		return
	_debug_mesh.global_transform = Transform3D.IDENTITY
	var im: ImmediateMesh = _debug_mesh.mesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for g in _groups:
		var col := Color.ORANGE if not g.sleeping else Color.DIM_GRAY
		for c in g.chains:
			for i in range(1, c.x.size()):
				im.surface_set_color(col)
				im.surface_add_vertex(c.x[i - 1])
				im.surface_add_vertex(c.x[i])
		for l in g.links:
			var a := g.chains[l.x]
			var b := g.chains[l.y]
			for i in range(1, mini(a.x.size(), b.x.size())):
				im.surface_set_color(Color(0.3, 0.8, 1.0, 0.6))
				im.surface_add_vertex(a.x[i])
				im.surface_add_vertex(b.x[i])
	for cap in _capsules:
		im.surface_set_color(Color.LIME_GREEN)
		im.surface_add_vertex(cap.a)
		im.surface_add_vertex(cap.b)
		var side := (cap.b - cap.a).cross(Vector3.FORWARD)
		if side.length_squared() < 1e-6:
			side = Vector3.RIGHT
		side = side.normalized() * cap.res.radius
		for o in [side, -side]:
			im.surface_add_vertex(cap.a + o)
			im.surface_add_vertex(cap.b + o)
	im.surface_end()
