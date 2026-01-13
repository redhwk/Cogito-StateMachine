extends State

## Base class for all movement-related states (Idle, Run, Jump, Sprint, etc.).
## Provides shared movement calculations, gravity handling, and velocity management.
## Uses static variables to share movement data across all Motion state instances.
class_name Motion

## Emitted when velocity is calculated and ready to be applied to the player
## Connected to Player.set_velocity_from_motion
signal velocity_updated(vel: Vector3)
## Emitted when input direction changes (for animation blending)
## Connected to AnimationController.on_character_input_direction_changed
@warning_ignore("unused_signal")
signal direction_updated(dir: Vector2)

# Resource references (set by PlayerStateMachine in _ready)
var movement_stats: MovementStats
var headbob_stats: HeadbobStats
var stair_handling_stats: StairHandlingStats
var ladder_handling_stats: LadderHandlingStats
var input_settings: InputSettings
var free_look_settings: FreeLookSettings

# Calculated movement speeds for different movement types
var speed: float
var sprint_speed: float
var aim_speed: float
# Jump physics values
var jump_velocity: float
var jump_gravity: float
var fall_gravity: float

# Static variables shared across all Motion states (maintains state between transitions)
# Current input direction from WASD keys (normalized Vector2)
static var input_dir : Vector2 = Vector2.ZERO
# World-space movement direction (transformed from input_dir)
static var direction: Vector3 = Vector3.ZERO
# Current velocity vector (x/z: horizontal, y: vertical)
static var velocity: Vector3 = Vector3.ZERO
# Remaining sprint duration in seconds
static var sprint_remaining: float = 0.0

# Gravity override (for gravity zones)
# These values are set by cogito_player.override_gravity() and reset when leaving gravity zones
static var override_gravity_force: float = -1.0  # -1 means use default
static var override_gravity_vector: Vector3 = Vector3.ZERO

# Headbob system (shared across states)
static var wiggle_index: float = 0.0
static var wiggle_current_intensity: float = 0.0
static var wiggle_vector: Vector2 = Vector2.ZERO

# Footstep system (shared across states)
static var can_play_footstep: bool = true

# Slide system (shared across states)
static var slide_vector: Vector2 = Vector2.ZERO
static var jumped_from_slide: bool = false

# Landing/roll system (shared across states)
static var last_velocity: Vector3 = Vector3.ZERO
static var was_in_air: bool = false

# Camera smoothing for stair steps (shared across states)
# Tracks the offset to apply to camera/head to smooth visual jitter from steps
static var camera_step_smoothing_offset: Vector3 = Vector3.ZERO
# Tracks the total offset currently applied to head.position.y (to ensure it fully resets)
static var camera_step_applied_offset: float = 0.0

## Sets all resource references from PlayerStateMachine
## Called by PlayerStateMachine._ready() to pass resources to states
## Parameters: All 6 player resource types
func set_resources(
	_movement_stats: MovementStats,
	_headbob_stats: HeadbobStats,
	_stair_handling_stats: StairHandlingStats,
	_ladder_handling_stats: LadderHandlingStats,
	_input_settings: InputSettings,
	_free_look_settings: FreeLookSettings
) -> void:
	movement_stats = _movement_stats
	headbob_stats = _headbob_stats
	stair_handling_stats = _stair_handling_stats
	ladder_handling_stats = _ladder_handling_stats
	input_settings = _input_settings
	free_look_settings = _free_look_settings
	
	# Initialize motion if resources are now available
	if movement_stats and is_inside_tree():
		_initialize_motion()

## Initializes movement speeds and physics values from MovementStats resource
## Connects velocity_updated signal to player's set_velocity_from_motion method
## Note: Resources may not be set yet when _ready() is called, so initialization is deferred
func _ready() -> void:
	# Defer initialization until resources are set
	# PlayerStateMachine calls set_resources() after _ready() completes
	call_deferred("_initialize_motion")

## Initializes motion values from resources (called deferred after resources are set)
func _initialize_motion() -> void:
	if not movement_stats:
		# Resources not set yet, try again next frame
		if not is_inside_tree():
			return
		call_deferred("_initialize_motion")
		return
	
	# Connect velocity signal if not already connected
	if not velocity_updated.is_connected(owner.set_velocity_from_motion):
		velocity_updated.connect(owner.set_velocity_from_motion)
	
	# Initialize speeds from movement_stats
	# Note: These calculations may need adjustment based on your new MovementStats structure
	# For now, using direct values from the resource
	speed = movement_stats.walking_speed
	sprint_speed = movement_stats.sprinting_speed
	aim_speed = movement_stats.walking_speed * 0.5  # Reduced speed when aiming
	
	# Initialize jump values
	# Using Godot's default gravity and calculating jump velocity
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	jump_gravity = gravity
	fall_gravity = gravity
	jump_velocity = movement_stats.jump_velocity
	
	# Initialize sprint remaining
	if movement_stats:
		sprint_remaining = movement_stats.sprint_duration

## Called when entering state
## With blend tree system, movement animations are handled automatically via update_animations()
## State-specific animations (Jump, Crouch, Sit, etc.) are handled by AnimationController.on_state_machine_state_change()
func _enter()-> void:
	pass

## Calculates movement direction from input and transforms it to world space
## Updates static input_dir and direction variables
## Pauses movement if player is rotating a carried object
func set_direction() -> void:
	var player = get_player()
	
	# Check if player is rotating a carried object - if so, pause movement
	if player and _is_rotating_carried_object(player):
		input_dir = Vector2.ZERO
		direction = Vector3.ZERO
		return
	
	input_dir = Input.get_vector(InputConstants.INPUT_LEFT, InputConstants.INPUT_RIGHT, InputConstants.INPUT_FORWARD, InputConstants.INPUT_BACKWARD)
	if player:
		# Get the body node for rotation (camera look direction)
		var body_node = player.get_node_or_null("Body") as Node3D
		if body_node:
			# Get the PlayerStateMachine to check for saved forward direction
			# Walk up the tree to find the StateMachine (PlayerStateMachine)
			var state_machine = get_parent()
			while state_machine and not state_machine is StateMachine:
				state_machine = state_machine.get_parent()
			
			# Use body's transform for direction (body rotates with camera)
			var input_vec = Vector3(input_dir.x, 0.0, input_dir.y)
			var transformed = body_node.global_transform.basis * input_vec
			direction = transformed.normalized()
		else:
			# Fallback to player transform if body not found
			var input_vec = Vector3(input_dir.x, 0.0, input_dir.y)
			var transformed = player.global_transform.basis * input_vec
			direction = transformed.normalized()
	else:
		direction = Vector3.ZERO

## Checks if the player is currently rotating a carried object
## Returns true if player has a carried object and action_secondary is pressed
func _is_rotating_carried_object(player: Node) -> bool:
	# Get player_interaction_component
	var pic = player.get_node_or_null("PlayerInteractionComponent")
	if not pic:
		return false
	
	# Check if player is carrying something
	if not pic.get("is_carrying"):
		return false
	
	# Check if the carried object allows manual rotation
	var carried = pic.get("carried_object")
	if not carried:
		return false
	
	# Check if the carryable has manual rotation enabled
	if carried.has_method("get") and carried.get("enable_manual_rotating"):
		# Check if action_secondary is pressed (right mouse button)
		if Input.is_action_pressed("action_secondary"):
			return true
	
	return false

## Calculates horizontal velocity using acceleration-based movement
## Smoothly interpolates velocity toward target speed using move_toward
## Emits velocity_updated signal with the calculated velocity
## Parameter _speed: Target horizontal speed in units per second
## Parameter _direction: Normalized world-space direction vector
## Parameter acceleration: Acceleration rate in units per second squared
## Parameter delta: Time elapsed since last frame
func calculate_velocity(_speed: float, _direction: Vector3, acceleration: float, delta: float) -> void:
	velocity.x = move_toward(velocity.x, _direction.x*_speed, acceleration*delta)
	velocity.z = move_toward(velocity.z, _direction.z*_speed, acceleration*delta)
	velocity_updated.emit(velocity)

## Applies gravity to vertical velocity based on whether player is ascending or descending
## Uses jump_gravity when moving up, fall_gravity when moving down
## Supports gravity override from gravity zones
## Parameter delta: Time elapsed since last frame
func calculate_gravity(delta: float) -> void:
	var player = get_player()
	if not player or not player is CharacterBody3D:
		return
	
	var player_body: CharacterBody3D = player as CharacterBody3D
	if not player_body.is_on_floor():
		# Check for gravity override (from gravity zones)
		if override_gravity_force >= 0:
			# Apply overridden gravity in the specified direction
			var gravity_vec = override_gravity_vector.normalized() * override_gravity_force * delta
			velocity += gravity_vec
		else:
			# Use default gravity behavior
			if velocity.y > 0:
				velocity.y -= jump_gravity * delta
			else:
				velocity.y -= fall_gravity * delta

## Checks if the player character is on the floor
## Returns: True if player CharacterBody3D is on floor, false otherwise
func is_on_floor() -> bool:
	var player = get_player()
	if not player or not player is CharacterBody3D:
		return false
	var player_body: CharacterBody3D = player as CharacterBody3D
	return player_body.is_on_floor()

## Gets the jump cooldown timer from the player node
## Returns: Timer node if found, null otherwise
func get_jump_timer() -> Timer:
	var player = get_player()
	if player and player.has_method("get_node"):
		return player.get_node_or_null("JumpCooldownTimer") as Timer
	return null

## Gets player node references for states that need them
## Returns: Dictionary with keys: body, neck, head, eyes, standing_collision_shape, crouching_collision_shape, crouch_raycast, sliding_timer, footstep_player
func get_player_nodes() -> Dictionary:
	var player = get_player()
	if not player or not player.has_method("get_node"):
		return {}
	
	var nodes: Dictionary = {}
	nodes["body"] = player.get_node_or_null("Body") as Node3D
	nodes["neck"] = player.get_node_or_null("Body/Neck") as Node3D
	nodes["head"] = player.get_node_or_null("Body/Neck/Head") as Node3D
	nodes["eyes"] = player.get_node_or_null("Body/Neck/Head/Eyes") as Node3D
	nodes["standing_collision_shape"] = player.get_node_or_null("StandingCollisionShape") as CollisionShape3D
	nodes["crouching_collision_shape"] = player.get_node_or_null("CrouchingCollisionShape") as CollisionShape3D
	nodes["crouch_raycast"] = player.get_node_or_null("CrouchRayCast") as RayCast3D
	nodes["sliding_timer"] = player.get_node_or_null("SlidingTimer") as Timer
	nodes["footstep_player"] = player.get_node_or_null("FootstepPlayer")
	nodes["animation_player"] = player.get_node_or_null("Body/Neck/Head/Eyes/AnimationPlayer") as AnimationPlayer
	
	return nodes

## Gets the player CogitoPlayer instance
## Returns: CogitoPlayer instance if owner is CogitoPlayer, null otherwise
func get_player() -> Node:
	if not owner:
		return null
	
	# Check if owner is already the player (CharacterBody3D)
	if owner is CharacterBody3D:
		return owner
	
	# Owner is the StateMachine node, player is the parent (CogitoPlayer)
	# Try to get player from StateMachine's parent
	var parent = owner.get_parent()
	
	# Check if parent is CharacterBody3D (which CogitoPlayer extends)
	if parent and parent is CharacterBody3D:
		return parent
	
	# Fallback: try to get player from StateMachine's player property (if it exists)
	# PlayerStateMachine has a player reference
	if owner.has_method("get") and owner.has("player"):
		var player_ref = owner.get("player")
		if player_ref:
			return player_ref
	
	# Another fallback: search up the tree for a CharacterBody3D
	var current = owner
	while current:
		current = current.get_parent()
		if current and current is CharacterBody3D:
			return current
	
	return null

## Replenishes sprint duration over time
## Used to restore sprint meter when not sprinting
## Note: Sprint duration is now managed by stamina system in cogito_player, this may need refactoring
## Parameter delta: Time elapsed since last frame
## Parameter replenishment_rate: Multiplier for replenishment speed (default 1.0)
func replenish_sprint(delta: float, replenishment_rate: float = 1.0) -> void:
	if movement_stats:
		sprint_remaining = min(sprint_remaining + (delta * replenishment_rate), movement_stats.sprint_duration)

## Updates headbob/camera wiggle based on current intensity and speed
## Parameter intensity: Current wiggle intensity (from HeadbobStats)
## Parameter wiggle_speed: Current wiggle speed (from HeadbobStats)
## Parameter delta: Time elapsed since last frame
## Returns: Updated wiggle_vector for use in camera positioning
func update_headbob(intensity: float, wiggle_speed: float, delta: float) -> Vector2:
	wiggle_index += wiggle_speed * delta
	wiggle_current_intensity = intensity
	wiggle_vector.y = sin(wiggle_index)
	wiggle_vector.x = sin(wiggle_index / 2.0) + 0.5
	return wiggle_vector

## Applies headbob to camera/eyes position
## Parameter eyes: The Eyes Node3D to apply headbob to
## Parameter delta: Time elapsed since last frame
## Parameter intensity: Current wiggle intensity (from HeadbobStats)
## Parameter wiggle_speed: Current wiggle speed (from HeadbobStats)
func apply_headbob(eyes: Node3D, delta: float, intensity: float, wiggle_speed: float) -> void:
	if not eyes:
		return
	
	var wiggle: Vector2 = update_headbob(intensity, wiggle_speed, delta)
	var headbob_strength: float = 1.0
	if headbob_stats:
		# Convert enum to float (0.1, 0.7, or 1.0)
		match headbob_stats.headbob_strength:
			0: headbob_strength = 0.1
			1: headbob_strength = 0.7
			2: headbob_strength = 1.0
	
	if movement_stats:
		eyes.position.y = lerp(eyes.position.y, wiggle.y * (intensity * headbob_strength / 2.0), delta * movement_stats.lerp_speed)
		eyes.position.x = lerp(eyes.position.x, wiggle.x * intensity * headbob_strength, delta * movement_stats.lerp_speed)

## Resets headbob to zero (smoothly lerps back)
## Parameter eyes: The Eyes Node3D to reset headbob on
## Parameter delta: Time elapsed since last frame
func reset_headbob(eyes: Node3D, delta: float) -> void:
	if not eyes or not movement_stats:
		return
	eyes.position.y = lerp(eyes.position.y, 0.0, delta * movement_stats.lerp_speed)
	eyes.position.x = lerp(eyes.position.x, 0.0, delta * movement_stats.lerp_speed)

## Plays footstep sound if conditions are met
## Parameter footstep_player: The footstep audio player node
## Parameter volume_db: Volume in decibels for the footstep
## Parameter min_velocity: Minimum velocity required to play footstep (default 0.2)
## Returns: True if footstep was played, false otherwise
func try_play_footstep(footstep_player: Node, volume_db: float, min_velocity: float = 0.2) -> bool:
	if not footstep_player or not is_on_floor():
		return false
	
	if velocity.length() < min_velocity:
		return false
	
	# Only play when wiggle is at peak (wiggle_vector.y > 0.9)
	if can_play_footstep and wiggle_vector.y > 0.9:
		if footstep_player.has_method("get") and footstep_player.get("volume_db") != null:
			footstep_player.set("volume_db", volume_db)
		if footstep_player.has_method("_play_interaction"):
			footstep_player._play_interaction("footstep")
		can_play_footstep = false
		return true
	
	# Reset can_play_footstep when wiggle goes down
	if not can_play_footstep and wiggle_vector.y < 0.9:
		can_play_footstep = true
	
	return false

## Applies calculated velocity to the player CharacterBody3D
## Handles stair stepping, gravity, and RigidBody pushing
## Tracks last_velocity and was_in_air for landing detection
## Parameter delta: Time elapsed since last physics frame
## Parameter apply_stairs: Whether to apply stair stepping (default true)
func apply_velocity(delta: float, apply_stairs: bool = true) -> void:
	var player = get_player()
	if not player or not player is CharacterBody3D:
		push_error("Motion.apply_velocity: get_player() must return CharacterBody3D. Got: ", player)
		return
	
	var player_body: CharacterBody3D = player as CharacterBody3D
	
	# Store last velocity before applying
	last_velocity = velocity
	
	# Track airborne state
	if player_body.is_on_floor():
		was_in_air = false
	else:
		was_in_air = true
	
	# Apply stair handling if enabled
	if apply_stairs and stair_handling_stats:
		var step_result: StepResult = StepResult.new()
		var is_jumping: bool = velocity.y > 0
		var is_step: bool = step_check(delta, is_jumping, step_result, player_body)
		
		# Get head node reference for camera smoothing (used in both step detection and smoothing)
		var nodes: Dictionary = get_player_nodes()
		var head: Node3D = nodes.get("head")
		
		if is_step:
			# Apply step offset immediately to player body (required for physics to work correctly)
			player_body.global_transform.origin += step_result.diff_position
			
			# Add inverse step offset to camera smoothing to reduce visual jitter
			# Apply offset to head node (not eyes) to avoid interfering with headbob on eyes
			var immediate_offset_factor: float = 0.6  # Apply 60% immediately, smooth the rest
			var immediate_offset: Vector3 = -step_result.diff_position * immediate_offset_factor
			if head:
				head.position.y += immediate_offset.y
				camera_step_applied_offset += immediate_offset.y
			
			# Store remaining offset to smooth over time
			camera_step_smoothing_offset -= step_result.diff_position * (1.0 - immediate_offset_factor)
		
		# Smoothly apply camera offset to head node to reduce visual jitter
		# Using head instead of eyes to avoid interfering with headbob system
		
		if head and (camera_step_smoothing_offset.length_squared() > 0.0001 or abs(camera_step_applied_offset) > 0.0001):
			if stair_handling_stats and stair_handling_stats.step_height_camera_lerp > 0.0:
				var lerp_speed: float = stair_handling_stats.step_height_camera_lerp
				
				# Store previous offset to calculate difference
				var previous_offset: Vector3 = camera_step_smoothing_offset
				
				# Use move_toward for linear interpolation (more predictable behavior)
				# lerp_speed is in units per second - this is the speed at which offset reduces
				# Higher values = faster smoothing (offset reduces more quickly)
				var max_move_per_second: float = lerp_speed
				var max_move: float = max_move_per_second * delta
				
				camera_step_smoothing_offset.y = move_toward(camera_step_smoothing_offset.y, 0.0, max_move)
				
				# Also handle x and z components (though they should be zero for steps)
				if abs(camera_step_smoothing_offset.x) > 0.0001:
					camera_step_smoothing_offset.x = move_toward(camera_step_smoothing_offset.x, 0.0, max_move)
				if abs(camera_step_smoothing_offset.z) > 0.0001:
					camera_step_smoothing_offset.z = move_toward(camera_step_smoothing_offset.z, 0.0, max_move)
				
				# Calculate difference and apply only the difference to head position
				var offset_difference: Vector3 = camera_step_smoothing_offset - previous_offset
				head.position.y += offset_difference.y
				camera_step_applied_offset += offset_difference.y
				
				# If smoothing offset is nearly zero but applied offset remains, force reset
				if camera_step_smoothing_offset.length_squared() < 0.0001 and abs(camera_step_applied_offset) > 0.0001:
					# Smoothly return applied offset to zero
					var applied_reset_speed: float = lerp_speed * 2.0  # Reset applied offset faster
					var applied_reset_move: float = applied_reset_speed * delta
					var reset_amount: float = move_toward(camera_step_applied_offset, 0.0, applied_reset_move)
					var reset_difference: float = camera_step_applied_offset - reset_amount
					head.position.y -= reset_difference
					camera_step_applied_offset = reset_amount
			else:
				# If no smoothing, reset immediately (don't apply offset)
				if abs(camera_step_applied_offset) > 0.0001:
					head.position.y -= camera_step_applied_offset
					camera_step_applied_offset = 0.0
				camera_step_smoothing_offset = Vector3.ZERO
		else:
			# Reset when close to zero to prevent floating point drift
			if abs(camera_step_applied_offset) > 0.0001:
				if head:
					head.position.y -= camera_step_applied_offset
				camera_step_applied_offset = 0.0
			camera_step_smoothing_offset = Vector3.ZERO
	
	# Apply gravity
	calculate_gravity(delta)
	
	# Set velocity and move
	player_body.velocity = velocity
	player_body.move_and_slide()
	
	# Update velocity from actual movement (for next frame)
	velocity = player_body.velocity
	
	# Push RigidBody3D objects
	if movement_stats:
		for col_idx in player_body.get_slide_collision_count():
			var col := player_body.get_slide_collision(col_idx)
			if col.get_collider() is RigidBody3D:
				col.get_collider().apply_central_impulse(-col.get_normal() * movement_stats.player_push_force)

## Checks for step up/down and handles stair traversal
## Returns true if a step was detected and handled
## Parameter delta: Time elapsed since last physics frame
## Parameter is_jumping_: Whether the player is currently jumping
## Parameter step_result: StepResult object to populate with step information
## Parameter player: The CharacterBody3D player instance
func step_check(delta: float, is_jumping_: bool, step_result: StepResult, player: CharacterBody3D) -> bool:
	if not stair_handling_stats:
		return false
	
	var is_step: bool = false
	var step_height_main: Vector3 = stair_handling_stats.step_height_default
	var step_incremental_check_height: Vector3 = step_height_main / 2.0  # STEP_CHECK_COUNT = 2
	
	const _WALL_MARGIN: float = 0.001
	const STEP_DOWN_MARGIN: float = 0.01
	const STEP_CHECK_COUNT: int = 2
	
	if velocity.y >= 0:
		for i in range(STEP_CHECK_COUNT):
			var test_motion_result: PhysicsTestMotionResult3D = PhysicsTestMotionResult3D.new()
			var step_height: Vector3 = step_height_main - i * step_incremental_check_height
			var transform3d: Transform3D = player.global_transform
			var motion: Vector3 = step_height
			var test_motion_params: PhysicsTestMotionParameters3D = PhysicsTestMotionParameters3D.new()
			test_motion_params.from = transform3d
			test_motion_params.motion = motion
			
			var is_player_collided: bool = PhysicsServer3D.body_test_motion(player.get_rid(), test_motion_params, test_motion_result)
			
			if is_player_collided and test_motion_result.get_collision_normal().y < 0:
				continue
			
			transform3d.origin += step_height
			motion = velocity * delta
			test_motion_params.from = transform3d
			test_motion_params.motion = motion
			
			is_player_collided = PhysicsServer3D.body_test_motion(player.get_rid(), test_motion_params, test_motion_result)
			
			if not is_player_collided:
				transform3d.origin += motion
				motion = -step_height
				test_motion_params.from = transform3d
				test_motion_params.motion = motion
				
				is_player_collided = PhysicsServer3D.body_test_motion(player.get_rid(), test_motion_params, test_motion_result)
				
				if is_player_collided:
					if test_motion_result.get_collision_normal().angle_to(Vector3.UP) <= deg_to_rad(stair_handling_stats.step_max_slope_degree):
						is_step = true
						step_result.is_step_up = true
						step_result.diff_position.y = -test_motion_result.get_remainder().y
						step_result.normal = test_motion_result.get_collision_normal()
						break
	
	# Step down detection
	if not is_jumping_ and not is_step and player.is_on_floor():
		step_result.is_step_up = false
		var test_motion_result: PhysicsTestMotionResult3D = PhysicsTestMotionResult3D.new()
		var transform3d: Transform3D = player.global_transform
		var motion: Vector3 = velocity * delta
		var test_motion_params: PhysicsTestMotionParameters3D = PhysicsTestMotionParameters3D.new()
		test_motion_params.from = transform3d
		test_motion_params.motion = motion
		test_motion_params.recovery_as_collision = true
		
		var is_player_collided: bool = PhysicsServer3D.body_test_motion(player.get_rid(), test_motion_params, test_motion_result)
		
		if not is_player_collided:
			transform3d.origin += motion
			motion = -step_height_main
			test_motion_params.from = transform3d
			test_motion_params.motion = motion
			
			is_player_collided = PhysicsServer3D.body_test_motion(player.get_rid(), test_motion_params, test_motion_result)
			
			if is_player_collided and test_motion_result.get_travel().y < -STEP_DOWN_MARGIN:
				if test_motion_result.get_collision_normal().angle_to(Vector3.UP) <= deg_to_rad(stair_handling_stats.step_max_slope_degree):
					is_step = true
					step_result.diff_position.y = test_motion_result.get_travel().y
					step_result.normal = test_motion_result.get_collision_normal()
	
	return is_step

## Helper class for step detection results
class StepResult:
	var diff_position: Vector3 = Vector3.ZERO
	var normal: Vector3 = Vector3.ZERO
	var is_step_up: bool = false
