extends Resource

## Container resource that groups all player configuration resources together.
## This allows easy swapping of entire player profiles (e.g., "Fast Player", "Stealth Player").
## Create instances of this resource (.tres files) to define different player configurations.
class_name PlayerResources

## Movement parameters (speeds, jump, crouch, etc.)
@export var movement_stats: MovementStats
## Headbob and camera wiggle parameters
@export var headbob_stats: HeadbobStats
## Stair stepping and traversal parameters
@export var stair_handling_stats: StairHandlingStats
## Ladder climbing parameters
@export var ladder_handling_stats: LadderHandlingStats
## Input sensitivity and control scheme parameters
@export var input_settings: InputSettings
## Free look camera tilt parameters
@export var free_look_settings: FreeLookSettings

