@tool
class_name ClothCollider
extends Resource
## Capsule following the skeleton, used to keep the fabric out of the body.
##
## The capsule goes from [member bone] to [member end_bone] (or along the bone axis for
## [member length] metres when no end bone is given). Offsets are in bone space.

@export var name := ""
@export var bone := ""
@export var end_bone := ""
@export var length := 0.0
@export_range(0.0, 1.0, 0.001) var radius := 0.08
@export var start_offset := Vector3.ZERO
@export var end_offset := Vector3.ZERO


static func capsule(collider_name: String, from_bone: String, to_bone: String, r: float,
		from_offset := Vector3.ZERO, to_offset := Vector3.ZERO) -> ClothCollider:
	var c := ClothCollider.new()
	c.name = collider_name
	c.bone = from_bone
	c.end_bone = to_bone
	c.radius = r
	c.start_offset = from_offset
	c.end_offset = to_offset
	return c


static func sphere(collider_name: String, on_bone: String, r: float, offset := Vector3.ZERO) -> ClothCollider:
	var c := ClothCollider.new()
	c.name = collider_name
	c.bone = on_bone
	c.radius = r
	c.start_offset = offset
	c.end_offset = offset
	return c
