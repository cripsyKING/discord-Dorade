class_name BonePoseCopier
extends SkeletonModifier3D
## Copies the animated pose of another skeleton (the character wearing the outfit) onto the
## outfit skeleton, bone by bone, matching names. Rotations are transferred relative to the
## rest poses, so the two skeletons may have different bone rolls. Bones that only exist on
## the outfit (cloth chains) are left to the cloth simulator.

@export var source: Skeleton3D
## Bone whose translation is copied (scaled by the height ratio of the two rests).
@export var root_bone := "pelvis"
## Optional renames: outfit bone name → source bone name.
@export var bone_map := {}

var _pairs: Array[Vector2i] = []
var _src_rest: Array[Quaternion] = []
var _dst_rest: Array[Quaternion] = []
var _root := Vector2i(-1, -1)
var _scale := 1.0
var _bound_to: Skeleton3D


func _bind(dst: Skeleton3D) -> void:
	_pairs.clear()
	_src_rest.clear()
	_dst_rest.clear()
	for b in dst.get_bone_count():
		var n := dst.get_bone_name(b)
		var s := source.find_bone(bone_map.get(n, n))
		if s < 0:
			continue
		_pairs.append(Vector2i(s, b))
		_src_rest.append(source.get_bone_rest(s).basis.get_rotation_quaternion())
		_dst_rest.append(dst.get_bone_rest(b).basis.get_rotation_quaternion())
		if n == root_bone:
			_root = Vector2i(s, b)
			var hs := source.get_bone_global_rest(s).origin.length()
			var hd := dst.get_bone_global_rest(b).origin.length()
			_scale = hd / hs if hs > 0.001 else 1.0
	_bound_to = dst


func _process_modification() -> void:
	var dst := get_skeleton()
	if dst == null or source == null:
		return
	if _bound_to != dst:
		_bind(dst)
	for i in _pairs.size():
		var p := _pairs[i]
		# delta from rest on the source, re-expressed on the destination rest
		var delta := _src_rest[i].inverse() * source.get_bone_pose_rotation(p.x)
		dst.set_bone_pose_rotation(p.y, _dst_rest[i] * delta)
	if _root.x >= 0:
		var off := source.get_bone_pose_position(_root.x) - source.get_bone_rest(_root.x).origin
		dst.set_bone_pose_position(_root.y, dst.get_bone_rest(_root.y).origin + off * _scale)
