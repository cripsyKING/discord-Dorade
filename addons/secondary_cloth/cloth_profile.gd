@tool
class_name ClothProfile
extends Resource
## Physical behaviour of one kind of fabric.
##
## All values are frame-rate independent: they are expressed per second and converted
## for the fixed simulation step by [SecondaryClothSimulator].

## How strongly each segment is pulled back toward its animated direction (per second).
## Low = floaty fabric, high = stiff fabric.
@export_range(0.0, 60.0, 0.1) var pose_stiffness := 6.0
## Multiplier of [member pose_stiffness] at the free end of a chain (hems are looser).
@export_range(0.0, 2.0, 0.01) var tip_stiffness_scale := 0.45
## Velocity loss per second while the character moves.
@export_range(0.0, 20.0, 0.01) var damping := 1.6
## Velocity loss per second once the character has stood still for [member settle_time].
@export_range(0.0, 40.0, 0.01) var settle_damping := 6.0
## Seconds of stillness before the fabric reaches [member settle_damping]. The transition is
## progressive so the cloth calms down instead of freezing.
@export_range(0.0, 10.0, 0.01) var settle_time := 1.2
@export_range(0.0, 3.0, 0.01) var gravity_scale := 1.0
## Air resistance (1/s): relative air speed transferred to the cloth. Creates the trailing
## effect during runs and lets the wind push the fabric.
@export_range(0.0, 20.0, 0.01) var air_drag := 1.5
## How much a [ClothWindZone] affects this fabric.
@export_range(0.0, 3.0, 0.01) var wind_sensitivity := 1.0
## Skirts and coat tails open like a parachute when the air flows along them (falls,
## landings, crouching). 0 = no flare.
@export_range(0.0, 2.0, 0.01) var flare := 0.5
## Small high-frequency flutter added on top of the wind (light fabrics).
@export_range(0.0, 2.0, 0.01) var flutter := 0.15
## Part (0..1) of the parent bone motion copied directly to the particles. 0 = all
## motion lags (very floaty), 1 = rigid. Keeps fast animations stable.
@export_range(0.0, 1.0, 0.01) var inertia_transfer := 0.35
## Stiffness (0..1) of the links between neighbouring chains: keeps a skirt closed and
## spreads motion sideways as soft folds.
@export_range(0.0, 1.0, 0.01) var lateral_stiffness := 0.5
## Allowed lateral stretch before the link resists (1.15 = 15 %).
@export_range(1.0, 2.0, 0.01) var lateral_max_stretch := 1.12
## Maximum deviation (degrees) from the animated direction of each segment.
@export_range(1.0, 180.0, 0.5) var max_angle := 70.0
## Maximum bend (degrees) of a joint compared with the authored curvature. Keeps the
## curves smooth: sharp kinks crush the skinned mesh into steps.
@export_range(5.0, 90.0, 0.5) var max_bend := 35.0
## Neighbouring chains never get closer than this ratio of their rest distance
## (prevents panels from crossing each other).
@export_range(0.3, 1.0, 0.01) var lateral_min_ratio := 0.75
## Collision radius of every particle, added to the collider radius.
@export_range(0.0, 0.2, 0.001) var thickness := 0.018
@export_range(1, 12) var iterations := 4


static func light() -> ClothProfile:
	var p := ClothProfile.new()
	p.resource_name = "Tissu léger"
	p.pose_stiffness = 2.5
	p.tip_stiffness_scale = 0.35
	p.damping = 0.9
	p.settle_damping = 4.0
	p.settle_time = 1.6
	p.gravity_scale = 0.75
	p.air_drag = 4.5
	p.wind_sensitivity = 1.8
	p.flutter = 0.6
	p.flare = 0.9
	p.inertia_transfer = 0.15
	p.lateral_stiffness = 0.3
	p.lateral_max_stretch = 1.2
	p.max_angle = 110.0
	p.max_bend = 50.0
	p.lateral_min_ratio = 0.6
	p.thickness = 0.01
	return p


static func classic() -> ClothProfile:
	var p := ClothProfile.new()
	p.resource_name = "Tissu classique"
	return p


static func thick() -> ClothProfile:
	var p := ClothProfile.new()
	p.resource_name = "Tissu épais"
	p.pose_stiffness = 11.0
	p.tip_stiffness_scale = 0.6
	p.damping = 2.6
	p.settle_damping = 8.0
	p.settle_time = 0.8
	p.gravity_scale = 1.15
	p.air_drag = 0.6
	p.wind_sensitivity = 0.35
	p.flutter = 0.0
	p.flare = 0.15
	p.inertia_transfer = 0.5
	p.lateral_stiffness = 0.7
	p.lateral_max_stretch = 1.06
	p.max_angle = 45.0
	p.max_bend = 22.0
	p.lateral_min_ratio = 0.85
	p.thickness = 0.025
	return p


static func long_coat() -> ClothProfile:
	var p := ClothProfile.new()
	p.resource_name = "Manteau long / cape"
	p.pose_stiffness = 4.0
	p.tip_stiffness_scale = 0.3
	p.damping = 1.2
	p.settle_damping = 5.5
	p.settle_time = 1.5
	p.gravity_scale = 1.0
	p.air_drag = 2.2
	p.wind_sensitivity = 1.0
	p.flutter = 0.2
	p.flare = 0.8
	p.inertia_transfer = 0.25
	p.lateral_stiffness = 0.55
	p.lateral_max_stretch = 1.15
	p.max_angle = 85.0
	p.max_bend = 30.0
	p.thickness = 0.02
	p.iterations = 5
	return p
