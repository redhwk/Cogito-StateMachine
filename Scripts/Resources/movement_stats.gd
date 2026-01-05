extends Resource

## Resource containing all player movement parameters.
## Used by Motion states to control movement speeds, jump behavior, and physics interactions.
## Create instances of this resource (.tres files) to define different movement profiles.
class_name MovementStats

@export_group("Jump Properties")
## Vertical velocity applied when jumping from standing position
@export var jump_velocity: float = 4.5
## Vertical velocity applied when jumping from crouched position
@export var crouch_jump_velocity: float = 3.0
## Whether the player can jump while crouched
@export var can_crouch_jump: bool = true

@export_group("Movement Speeds")
## Walking speed in units per second
@export var walking_speed: float = 5.0
## Sprinting speed in units per second
@export var sprinting_speed: float = 8.0
## Crouching speed in units per second
@export var crouching_speed: float = 3.0
## Sliding speed in units per second (when sprinting + crouching)
@export var sliding_speed: float = 5.0

@export_group("Crouch Properties")
## Vertical offset applied to head/camera when crouching (negative value)
@export var crouching_depth: float = -0.9

@export_group("Lerp & Smoothing")
## Speed at which movement values interpolate on the ground (units per second)
@export var lerp_speed: float = 10.0
## Speed at which movement values interpolate in the air (units per second)
@export var air_lerp_speed: float = 6.0

@export_group("Acceleration")
## Ground acceleration rate in units per second squared
@export var acceleration: float = 100.0
## Air acceleration rate in units per second squared (lower than ground for air control)
@export var in_air_acceleration: float = 5.0

@export_group("Sprint System")
## Maximum duration in seconds the player can sprint continuously
@export var sprint_duration: float = 3.0
## Minimum sprint remaining time required to enter sprint state (prevents stuttering)
@export var minimum_sprint_threshold: float = 0.5

@export_group("Slide Properties")
## Speed multiplier applied to jump velocity when jumping from a slide
@export var slide_jump_mod: float = 1.5

@export_group("Bunny Hop")
## Whether bunny hopping is enabled (allows speed accumulation on consecutive jumps)
@export var can_bunnyhop: bool = true
## Speed increase per bunny hop jump (additive)
@export var bunny_hop_acceleration: float = 0.1

@export_group("Physics Interaction")
## Force applied when pushing RigidBody3D objects
@export var player_push_force: float = 1.3

@export_group("Animation")
## Disables the roll animation when landing from high falls
@export var disable_roll_anim: bool = false

@export_group("Float Properties")
## Speed multiplier for floating/swimming movement (slower than walking)
@export var float_speed_multiplier: float = 0.6
## Vertical movement speed when pressing jump/crouch while floating
@export var float_vertical_speed: float = 4.0
## Drag factor to slow down over time while floating (0 = no drag, 1 = instant stop)
@export var float_drag: float = 0.02
