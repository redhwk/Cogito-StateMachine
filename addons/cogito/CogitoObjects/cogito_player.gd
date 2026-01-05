@icon("res://addons/cogito/Assets/Graphics/Editor/Icon_CogitoPlayer.svg")
## The player class controls movement from input from the mouse, keyboard, and gamepad, as well as behavior parameters like stair and ladder handling.
class_name CogitoPlayer
extends CharacterBody3D

## Emits when ESC/Menu input map action is pressed. Can be used to exit out other interfaces, etc.
signal menu_pressed(player_interaction_component: PlayerInteractionComponent)
signal toggle_inventory_interface()
signal player_state_loaded()
## Used to hide UI elements like the crosshair when another interface is active (like a container or readable)
signal toggled_interface(is_showing_ui:bool) 

signal mouse_movement(relative_mouse_movement:Vector2)

#region Node References
## Reference to Pause menu node
@export var pause_menu : NodePath
## Reference to Player HUD node
@export var player_hud : NodePath
## Toggle printing debug messages or not. Works with the CogitoSceneManager
@export var is_logging : bool

## Item Drop Shapecast
@export var item_drop_shapecast : ShapeCast3D

## Inventory resource that stores the player inventory.
@export var inventory_data : CogitoInventory

@export_group("Audio")
## AudioStream that gets played when the player jumps.
@export var jump_sound : AudioStream
## AudioStream that gets played when the player slides (sprint + crouch).
@export var slide_sound : AudioStream
@export_subgroup ("Footstep Audio")
## Volume in dB for walking footsteps
@export var walk_volume_db : float = -38.0
## Volume in dB for sprinting footsteps
@export var sprint_volume_db : float = -30.0
## Volume in dB for crouching footsteps
@export var crouch_volume_db : float = -60.0
## The time between footstep sounds when walking
@export var walk_footstep_interval : float = 0.6
## The time between footstep sounds when sprinting
@export var sprint_footstep_interval : float = 0.3
## The speed at which the player must be moving before the footsteps change from walk to sprint.
@export var footstep_interval_change_velocity : float = 5.2

@export_subgroup ("Landing Audio")
## Threshold for triggering landing sound
@export var landing_threshold = -2.0  
## Defines Maximum velocity (in negative) for the hardest landing sound
@export var max_landing_velocity = -8
## Defines Minimum velocity (in negative) for the softest landing sound
@export var min_landing_velocity = -2
## Max volume in dB for the landing sound
@export var max_volume_db = 0
## Min volume in dB for the landing sound
@export var min_volume_db = -40
## Highest pitch for lightest landing sound
@export var max_pitch = 0.8
## Lowest pitch for hardest landing sound
@export var min_pitch = 0.7
## Current landing volume (used by FootstepSurfaceDetector)
var LandingVolume: float = 0.0
## Current landing pitch (used by FootstepSurfaceDetector)
var LandingPitch: float = 1.0

@export_group("Fall Damage")
## Damage the player takes if falling from great height. Leave at 0 if you don't want to use this.
@export var fall_damage : int
## Fall velocity at which fall damage is triggered. This is negative y-Axis. -5 is a good starting point but might be a bit too sensitive.
@export var fall_damage_threshold : float = -5

# Used for handling input when UI is open/displayed
var is_showing_ui : bool = false

## Whether movement is currently paused (delegates to PlayerStateMachine)
## Used by PlayerInteractionComponent and other systems
var is_movement_paused: bool:
	get:
		var state_machine = get_node_or_null("StateMachine")
		if state_machine and "is_movement_paused" in state_machine:
			return state_machine.is_movement_paused
		return false
	set(value):
		var state_machine = get_node_or_null("StateMachine")
		if state_machine and "is_movement_paused" in state_machine:
			state_machine.is_movement_paused = value

# Node caching (accessed by states via get_player_nodes())
@onready var player_interaction_component: PlayerInteractionComponent = $PlayerInteractionComponent
@onready var body: Node3D = $Body
@onready var neck: Node3D = $Body/Neck
@onready var head: Node3D = $Body/Neck/Head
@onready var eyes: Node3D = $Body/Neck/Head/Eyes
@onready var camera: Camera3D = $Body/Neck/Head/Eyes/Camera
@onready var animationPlayer: AnimationPlayer = $Body/Neck/Head/Eyes/AnimationPlayer
@onready var standing_collision_shape: CollisionShape3D = $StandingCollisionShape
@onready var crouching_collision_shape: CollisionShape3D = $CrouchingCollisionShape
@onready var crouch_raycast: RayCast3D = $CrouchRayCast
@onready var sliding_timer: Timer = $SlidingTimer
@onready var jump_timer: Timer = $JumpCooldownTimer
@onready var footstep_player = $FootstepPlayer
@onready var footstep_surface_detector : FootstepSurfaceDetector = $FootstepPlayer
@onready var navigation_agent = $NavigationAgent3D
@onready var wieldables = %Wieldables

# Player state tracking
var is_dead : bool = false
var radius : float

# Crouch state properties (for save/load compatibility with cogito_scene_manager)
## Whether the player is trying to crouch (input state)
## Used by save/load system - synced with Crouch state's static variable
var try_crouch: bool = false

## Whether the player is currently crouching (collision state)
## Used by save/load system - reads from collision shapes
var is_crouching: bool:
	get:
		# Check collision shapes to determine if crouching
		if crouching_collision_shape and not crouching_collision_shape.disabled:
			return true
		return false
	set(value):
		# Set crouch state via state machine
		try_crouch = value
		# Sync with Crouch state's static variable
		var state_machine = get_node_or_null("StateMachine")
		if state_machine:
			var crouch_state = state_machine.get_node_or_null("Grounded/Crouch")
			if crouch_state:
				# Access static variable through script
				var crouch_script = crouch_state.get_script()
				if crouch_script:
					# Set static variable (accessed through class)
					crouch_state.set("try_crouch", value)
			# Transition to appropriate state
			if state_machine.has_method("_change_state"):
				if value:
					state_machine._change_state("Crouch")
				else:
					state_machine._change_state("Stand")

# Sitting state properties (for save/load compatibility with cogito_scene_manager)
## Whether the player is currently sitting
## Used by save/load system - managed by Sit state
var is_sitting: bool = false

## Look marker position for sitting (where player should look while sitting)
## Used by save/load system - managed by Sit state
var sittable_look_marker: Vector3 = Vector3()

## Look angle for sitting (rotation angle while sitting)
## Used by save/load system - managed by Sit state
var sittable_look_angle: float = 0.0

## Whether the player is moving between seats
## Used by save/load system - managed by Sit state
var moving_seat: bool = false

## Displacement position from original position when sitting
## Used by save/load system - managed by Sit state
var displacement_position: Vector3 = Vector3()

## Original player position before sitting
## Used by save/load system - managed by Sit state
var original_position: Transform3D = Transform3D()

## Original neck basis before sitting (for restoring head rotation)
## Used by save/load system - managed by Sit state
var original_neck_basis: Basis = Basis()

## Whether the player was ejected from the seat
## Used by save/load system - managed by Sit state
var is_ejected: bool = false

## Whether the player is currently tweening to/from a seat
## Used by save/load system - managed by Sit state
var currently_tweening: bool = false

# Ladder state properties (for compatibility with ladder_area.gd in addons)
## Whether the player is currently on a ladder
## Used by ladder_area.gd - syncs with Ladder state's static variable
var on_ladder: bool:
	get:
		# Try to read from Ladder state's static variable
		var state_machine = get_node_or_null("StateMachine")
		if state_machine:
			var ladder_state = state_machine.get_node_or_null("Climbing/Ladder")
			if ladder_state and "on_ladder" in ladder_state:
				return ladder_state.on_ladder
		return false
	set(value):
		# Sync with Ladder state's static variable
		var state_machine = get_node_or_null("StateMachine")
		if state_machine:
			var ladder_state = state_machine.get_node_or_null("Climbing/Ladder")
			if ladder_state and "on_ladder" in ladder_state:
				ladder_state.on_ladder = value
		# If setting to false and currently in Ladder state, transition out
		if not value and state_machine:
			var current_state = state_machine.current_state if "current_state" in state_machine else null
			if current_state and current_state.name == "Ladder":
				state_machine._change_state("Grounded")

# Movement state properties (for compatibility with CogitoStaminaAttribute and other systems)
## Whether the player is currently sprinting
## Used by stamina attribute system - checks state machine
var is_sprinting: bool:
	get:
		var state_machine = get_node_or_null("StateMachine")
		if state_machine:
			# Access current_state directly (it's a public variable)
			var current_state = state_machine.current_state if "current_state" in state_machine else null
			if current_state:
				# Check if current state is Sprint by checking the state name
				return current_state.name == "Sprint"
		return false

## Whether the player is currently in the air (airborne)
## Used by sittable system and other interactions - checks if player is in Airborne parent state
## This is a computed property that checks the state machine (avoids calling is_on_floor() to prevent recursion)
var is_in_air: bool:
	get:
		# Check state machine for airborne states (more reliable than is_on_floor() which can cause recursion)
		var state_machine = get_node_or_null("StateMachine")
		if state_machine:
			var current_state = null
			if "current_state" in state_machine:
				current_state = state_machine.current_state
			
			if current_state:
				# Check if current state is under Airborne parent
				var check_node = current_state
				var depth = 0  # Prevent infinite loops
				while check_node and check_node != state_machine and depth < 10:
					if check_node.name == "Airborne":
						return true
					check_node = check_node.get_parent()
					depth += 1
		
		# Fallback: check velocity (if falling/jumping, likely in air)
		# This avoids calling is_on_floor() which could cause recursion
		if velocity.y > 0.1 or velocity.y < -0.1:
			return true
		
		return false

## Current movement speed of the player
## Used by stamina attribute system - reads from velocity
var current_speed: float:
	get:
		return velocity.length()

## Main velocity vector (horizontal movement)
## Used by stamina attribute system - provides horizontal velocity for slope calculations
var main_velocity: Vector3:
	get:
		return Vector3(velocity.x, 0, velocity.z)

## Walking speed constant (for compatibility with old stamina system)
## Used by stamina attribute system - reads from MovementStats resource
var WALKING_SPEED: float:
	get:
		var state_machine = get_node_or_null("StateMachine")
		if state_machine and state_machine.has_method("get"):
			var player_resources = state_machine.get("player_resources")
			if player_resources and player_resources.has_method("get"):
				var movement_stats = player_resources.get("movement_stats")
				if movement_stats and movement_stats.has_method("get"):
					return movement_stats.get("walking_speed") if movement_stats.has_method("get") else 5.0
		return 5.0  # Default fallback

# Player attributes and currencies (managed by CogitoAttribute and CogitoCurrency nodes)
var player_attributes : Dictionary = {}
var stamina_attribute : CogitoAttribute = null
var visibility_attribute : CogitoAttribute = null
var player_currencies: Dictionary = {}

# Slide audio player (initialized in _ready)
var slide_audio_player : AudioStreamPlayer3D
#endregion

func _ready():
	# Setup steps
	CogitoSceneManager._current_player_node = self
	player_interaction_component.exclude_player(get_rid())
	
	randomize() 
	
	radius = _calculate_player_radius()
	
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	### NEW PLAYER ATTRIBUTE SETUP:
	# Grabs all attached player attributes
	for attribute in find_children("","CogitoAttribute",false):
		player_attributes[attribute.attribute_name] = attribute
		CogitoGlobals.debug_log(is_logging, "cogito_player.gd", "Cogito Attribute found: " + attribute.attribute_name)

	# If found, hookup health attribute signal to detect player death
	var health_attribute = player_attributes.get("health")
	if health_attribute:
		health_attribute.death.connect(_on_death)
	# Save reference to stamina attribute for movements that require stamina checks (null if not found)
	stamina_attribute = player_attributes.get("stamina")
	# Save reference to visibility attribute for that require visibility checks (null if not found)
	visibility_attribute = player_attributes.get("visibility")
	# Hookup sanity attribute to visibility attribute
	var sanity_attribute = player_attributes.get("sanity")
	if sanity_attribute and visibility_attribute:
		visibility_attribute.attribute_changed.connect(sanity_attribute.on_visibility_changed)
		visibility_attribute.check_current_visibility()

	### CURRENCY SETUP
	for currency in find_children("", "CogitoCurrency", false):
		player_currencies[currency.currency_name] = currency
		CogitoGlobals.debug_log(is_logging, "cogito_player.gd", "Cogito Currency found: " + currency.currency_name)

	# Pause Menu setup
	if pause_menu:
		var pause_menu_node = get_node(pause_menu)
		pause_menu_node.resume.connect(_on_pause_menu_resume)
		pause_menu_node.close_pause_menu()
	else:
		printerr("Player has no reference to pause menu.")
	
	# Sittable Signals setup (handled by Sit state, but signals need to be connected here)
	CogitoSceneManager.connect("sit_requested", Callable(self, "_on_sit_requested"))
	CogitoSceneManager.connect("stand_requested", Callable(self, "_on_stand_requested"))
	CogitoSceneManager.connect("seat_move_requested", Callable(self, "_on_seat_move_requested"))
	
	call_deferred("slide_audio_init")

func slide_audio_init():
	# Setup sound effect for sliding
	if slide_sound:
		slide_audio_player = Audio.play_sound_3d(slide_sound, false)
		if slide_audio_player:
			slide_audio_player.reparent(self, false)

# Use these functions to manipulate player attributes.
func increase_attribute(attribute_name: String, value: float, value_type: ConsumableItemPD.ValueType) -> bool:
	var attribute = player_attributes.get(attribute_name)
	if not attribute:
		CogitoGlobals.debug_log(is_logging, "cogito_player.gd", "Increase attribute: Attribute not found")
		return false
	if value_type == ConsumableItemPD.ValueType.CURRENT:
		if attribute.value_current == attribute.value_max:
			return false
		attribute.add(value)
		return true
	elif value_type == ConsumableItemPD.ValueType.MAX:
		attribute.value_max += value
		attribute.add(value)
		return true
	return false

func decrease_attribute(attribute_name: String, value: float):
	var attribute = player_attributes.get(attribute_name)
	if not attribute:
		CogitoGlobals.debug_log(is_logging, "cogito_player.gd", "Decrease attribute: " + attribute_name + " - Attribute not found")
		return
	attribute.subtract(value)

# Use these functions to manipulate player currencies.
func increase_currency(currency_name: String, value: float) -> bool:
	var currency = player_currencies.get(currency_name)
	if not currency:
		CogitoGlobals.debug_log(is_logging, "cogito_player.gd", "Increase currency: Currency not found")
		return false
	else:
		currency.add(value)
		return true

func decrease_currency(currency_name: String, value: float):
	var currency = player_currencies.get(currency_name)
	if not currency:
		CogitoGlobals.debug_log(is_logging, "cogito_player.gd", "Decrease currency: Currency not found")
		return
	currency.subtract(value)

func _on_death():
	is_dead = true
	# TODO: Handle death logic (disable input, show death screen, etc.)

func _on_pause_menu_resume():
	# Called by PauseMenu when resuming
	# Resume movement and capture mouse
	_on_resume_movement()

## Pauses movement (called by HUD manager and other systems)
## Delegates to PlayerStateMachine
func _on_pause_movement() -> void:
	var state_machine = get_node_or_null("StateMachine")
	if state_machine and state_machine.has_method("_on_pause_movement"):
		state_machine._on_pause_movement()

## Resumes movement (called by HUD manager and other systems)
## Delegates to PlayerStateMachine
func _on_resume_movement() -> void:
	var state_machine = get_node_or_null("StateMachine")
	if state_machine and state_machine.has_method("_on_resume_movement"):
		state_machine._on_resume_movement()

# Sittable signal handlers (delegate to Sit state via state machine)
func _on_sit_requested(sittable: Node):
	# Transition to Sit state via state machine
	var state_machine = get_node_or_null("StateMachine")
	if state_machine and state_machine.has_method("_change_state"):
		state_machine._change_state("Sit")
	else:
		pass

func _on_stand_requested():
	# Exit Sit state (will transition to Grounded)
	var state_machine = get_node_or_null("StateMachine")
	if state_machine and state_machine.has_method("_change_state"):
		# If currently in Sit state, transition to Grounded
		if state_machine.current_state and state_machine.current_state.name == "Sit":
			state_machine._change_state("Grounded")

func _on_seat_move_requested(sittable: Node):
	# Already in Sit state, just update the sittable reference
	# The Sit state will handle the seat move
	pass

## Called by Motion states to set velocity from state machine
## Parameter vel: The velocity vector calculated by the state
func set_velocity_from_motion(vel: Vector3) -> void:
	velocity = vel

## Calculates player radius from collision shapes
## Returns: The radius of the player collision shape
func _calculate_player_radius() -> float:
	var radius : float = 0.0
	for child in find_children("*", "CollisionShape3D", false, false):
		if child.shape is BoxShape3D:
			var edge = max(child.shape.size.x, child.shape.size.z)
			var r = sqrt(2 * pow(edge / 2, 2))
			radius = max(r, radius)
		elif child.shape is CylinderShape3D or child.shape is CapsuleShape3D:
			radius = max(child.shape.radius, radius)
	
	return radius

## Applies external force to player (called by external systems)
## Parameter force_vector: The force vector to apply
func apply_external_force(force_vector: Vector3):
	if force_vector and force_vector.length() > 0:
		CogitoGlobals.debug_log(is_logging, "cogito_player.gd", "Applying external force " + str(force_vector))
		velocity += force_vector
		move_and_slide()

## Overrides gravity (called by external systems like gravity zones)
## Parameter _external_gravity_force: The gravity force value
## Parameter _external_gravity_vector: The gravity direction vector
func override_gravity(_external_gravity_force : float, _external_gravity_vector: Vector3):
	CogitoGlobals.debug_log(true, "cogito_player.gd", "override gravity with " + str(_external_gravity_force) + ", " + str(_external_gravity_vector))
	# Pass gravity override to Motion states
	# Check if this is a reset to default (default gravity vector is DOWN)
	var default_gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
	var default_vector = ProjectSettings.get_setting("physics/3d/default_gravity_vector")
	
	if abs(_external_gravity_force - default_gravity) < 0.01 and _external_gravity_vector.is_equal_approx(default_vector):
		# Reset to default - use -1 to indicate no override
		Motion.override_gravity_force = -1.0
		Motion.override_gravity_vector = Vector3.ZERO
	else:
		# Apply override
		Motion.override_gravity_force = _external_gravity_force
		Motion.override_gravity_vector = _external_gravity_vector

func _on_player_state_loaded():
	# TODO - reset look on load if needed
	# Sync crouch state with state machine after load
	var state_machine = get_node_or_null("StateMachine")
	if state_machine:
		var crouch_state = state_machine.get_node_or_null("Grounded/Crouch")
		if crouch_state:
			# Sync static variable with player property
			# Access static variable through the script
			var crouch_script = crouch_state.get_script()
			if crouch_script:
				# We can't directly set static vars, but we can trigger state transition
				# The state will sync on enter
				if try_crouch:
					state_machine._change_state("Crouch")
				else:
					state_machine._change_state("Stand")
	pass

## Called by ladder_area.gd to enter ladder state
## Forwards to Ladder state's enter_ladder method
## Parameter ladder: The ladder CollisionShape3D
## Parameter ladderDir: The direction vector of the ladder
func enter_ladder(ladder: CollisionShape3D, ladderDir: Vector3):
	var state_machine = get_node_or_null("StateMachine")
	if state_machine and state_machine.has_method("get") and state_machine.get("current_state") != null:
		var current_state = state_machine.get("current_state")
		# Find Ladder state in the state machine
		var ladder_state = state_machine.get_node_or_null("Climbing/Ladder")
		if ladder_state and ladder_state.has_method("enter_ladder"):
			ladder_state.enter_ladder(ladder, ladderDir)
