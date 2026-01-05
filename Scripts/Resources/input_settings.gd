extends Resource

## Resource containing input sensitivity and control scheme parameters.
## Controls mouse sensitivity, gamepad settings, and input behavior preferences.
## Create instances of this resource (.tres files) to define different input profiles.
class_name InputSettings

@export_group("Mouse Settings")
## Mouse sensitivity multiplier for camera/head rotation
## Higher values = faster camera movement
@export var mouse_sens: float = 0.25
## Whether Y-axis (vertical) mouse look is inverted
## true = inverted (pulling mouse down looks up), false = normal
@export var invert_y_axis: bool = true

@export_group("Crouch Behavior")
## Whether crouch is toggle mode (true) or hold-to-crouch (false)
## true = press once to crouch, press again to stand
## false = hold key to crouch, release to stand
@export var toggle_crouch: bool = false

@export_group("Gamepad Settings")
## Deadzone threshold for gamepad analog sticks (0.0 to 1.0)
## Input below this value is ignored to prevent drift
@export var joy_deadzone: float = 0.25
## Vertical (Y-axis) sensitivity for gamepad look
## Higher values = faster vertical camera movement
@export var joy_v_sens: float = 2.0
## Horizontal (X-axis) sensitivity for gamepad look
## Higher values = faster horizontal camera movement
@export var joy_h_sens: float = 2.0

