extends Resource

## Resource containing ladder climbing and interaction parameters.
## Controls player behavior when climbing ladders, including speed and jump mechanics.
## Create instances of this resource (.tres files) to define different ladder handling profiles.
class_name LadderHandlingStats

## Whether the player can sprint while climbing a ladder
@export var can_sprint_on_ladder: bool = false
## Normal climbing speed on ladder (units per second)
@export var ladder_speed: float = 2.0
## Sprinting speed on ladder when sprint is enabled (units per second)
@export var ladder_sprint_speed: float = 3.3
## Cooldown time in seconds after leaving a ladder before player can re-enter
## Prevents accidental re-entry when jumping off ladder
@export var ladder_cooldown: float = 0.5
## Jump velocity multiplier when jumping off a ladder
## Lower values reduce jump power when exiting ladder (0.5 = half normal jump)
@export var ladder_jump_scale: float = 0.5
