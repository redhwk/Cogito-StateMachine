extends Resource

## Resource containing all headbob and camera wiggle parameters.
## Controls the camera movement effects during walking, sprinting, and crouching.
## Create instances of this resource (.tres files) to define different headbob profiles.
class_name HeadbobStats

## Head bob strength multiplier. Controls overall intensity of camera movement.
## 0.1 = Minimal movement, 0.7 = Average movement, 1.0 = Full movement
@export_enum("Minimal:0.1", "Average:0.7", "Full:1") var headbob_strength: int = 1

@export_group("Walking Headbob")
## Intensity of camera wiggle when walking (higher = more movement)
@export var wiggle_on_walking_intensity: float = 0.03
## Speed of camera wiggle animation when walking (higher = faster oscillation)
@export var wiggle_on_walking_speed: float = 12.0

@export_group("Sprinting Headbob")
## Intensity of camera wiggle when sprinting (higher = more movement)
@export var wiggle_on_sprinting_intensity: float = 0.05
## Speed of camera wiggle animation when sprinting (higher = faster oscillation)
@export var wiggle_on_sprinting_speed: float = 16.0

@export_group("Crouching Headbob")
## Intensity of camera wiggle when crouching (higher = more movement)
@export var wiggle_on_crouching_intensity: float = 0.08
## Speed of camera wiggle animation when crouching (higher = faster oscillation)
@export var wiggle_on_crouching_speed: float = 8.0

