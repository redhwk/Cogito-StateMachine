extends Resource

## Resource containing stair stepping and traversal parameters.
## Controls how the player handles stepping up and down stairs and small obstacles.
## Create instances of this resource (.tres files) to define different stair handling profiles.
class_name StairHandlingStats

## Camera smoothing speed when stepping up/down stairs (higher = smoother camera movement)
@export var step_height_camera_lerp: float = 2.5
## Maximum height considered a step instead of a wall (in meters)
## Player will automatically step up obstacles below this height
@export var step_height_default: Vector3 = Vector3(0, 0.5, 0)
## Maximum slope angle in degrees for step detection
## Lower values = stricter detection (0 = very strict, prevents tiny edges from stopping player)
@export var step_max_slope_degree: float = 0.0

