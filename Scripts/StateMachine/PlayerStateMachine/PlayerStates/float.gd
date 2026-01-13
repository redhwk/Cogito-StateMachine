extends Motion

## Float state: Player is in a gravity zone or underwater.
## Provides full 3D movement control:
## - WASD for horizontal movement in camera direction
## - Jump to rise (ascend)
## - Crouch to descend
## Automatically enters when gravity is overridden and player is not on floor.
## Exits when gravity returns to normal or player lands on ground.

## Tracks if we're actively ascending (jump held)
var is_ascending: bool = false
## Tracks if we're actively descending (crouch held)
var is_descending: bool = false

## Called when entering the Float state
func _enter() -> void:
	super._enter()
	is_ascending = false
	is_descending = false
	# Reset vertical velocity to avoid sudden movements
	velocity.y = velocity.y * 0.5

## Called when exiting the Float state
func _exit() -> void:
	is_ascending = false
	is_descending = false
	# Reset collision shape rotation when exiting Float
	# This prevents falling through floor if collision shape was rotated
	var nodes: Dictionary = get_player_nodes()
	var standing_collision: CollisionShape3D = nodes.get("standing_collision_shape")
	if standing_collision:
		standing_collision.rotation_degrees.x = 0.0

## Handles input for ascending/descending
func _state_input(event: InputEvent) -> void:
	# Jump to ascend
	if event.is_action_pressed(InputConstants.INPUT_JUMP):
		is_ascending = true
	if event.is_action_released(InputConstants.INPUT_JUMP):
		is_ascending = false
	
	# Crouch to descend
	if event.is_action_pressed(InputConstants.INPUT_CROUCH):
		is_descending = true
	if event.is_action_released(InputConstants.INPUT_CROUCH):
		is_descending = false

## Updates floating movement every physics frame
func _update(delta: float) -> void:
	# Get horizontal movement direction from input
	set_direction()
	
	# Calculate horizontal velocity (slower than normal movement)
	var float_speed = speed
	var float_speed_multiplier = 0.6
	var drag = 0.02
	if movement_stats:
		float_speed_multiplier = movement_stats.float_speed_multiplier
		drag = movement_stats.float_drag
		float_speed = speed * float_speed_multiplier
		calculate_velocity(float_speed, direction, movement_stats.in_air_acceleration * 0.5, delta)
	
	# Handle vertical movement based on input (this takes priority over gravity)
	_handle_vertical_movement(delta)
	
	# Apply drag to slow down over time (gives floaty feel)
	velocity *= (1.0 - drag)
	
	# Only apply gravity override if player is NOT actively controlling vertical movement
	# This allows player input to override the gravity zone's effect
	if override_gravity_force >= 0 and not is_ascending and not is_descending:
		# Gravity zone active - apply its gravity (reduced for floaty feel) only when no input
		var gravity_vec = override_gravity_vector.normalized() * override_gravity_force * 0.3 * delta
		velocity += gravity_vec
	
	# Emit direction for animation (connected to AnimationController.on_character_input_direction_changed)
	# The AnimationController handles Float animations automatically via update_animations()
	direction_updated.emit(input_dir)
	
	# Rotate collision shape based on movement (90 degrees in X when moving)
	_update_collision_shape_rotation()
	
	# Apply velocity (no stair handling while floating)
	# IMPORTANT: This must be called BEFORE checking for landing so last_velocity is set correctly
	apply_velocity(delta, false)
	
	# Check if we should exit Float state AFTER apply_velocity() so last_velocity is set
	if _should_exit_float():
		_exit_float_state()
		return

## Updates Float animation blend based on movement direction
## Uses direction_updated signal (already connected to AnimationController)
## The AnimationController handles Float animations automatically via update_animations()
## No direct AnimationController calls needed - proper signal-based communication

## Rotates StandingCollisionShape based on movement state
## When not moving: normal orientation
## When moving: rotated 90 degrees in X axis
func _update_collision_shape_rotation() -> void:
	var nodes: Dictionary = get_player_nodes()
	var standing_collision: CollisionShape3D = nodes.get("standing_collision_shape")
	if not standing_collision:
		return
	
	# Check if we're moving (horizontal movement)
	var is_moving = direction.length_squared() > 0.01
	
	if is_moving:
		# Rotate 90 degrees in X axis when moving
		standing_collision.rotation_degrees.x = 90.0
	else:
		# Normal orientation when not moving
		standing_collision.rotation_degrees.x = 0.0

## Handles vertical movement based on jump/crouch input
func _handle_vertical_movement(delta: float) -> void:
	var vertical_speed = 4.0
	if movement_stats:
		vertical_speed = movement_stats.float_vertical_speed
	
	if is_ascending:
		# Rise up when jump is held - directly set velocity for responsive control
		velocity.y = vertical_speed
	elif is_descending:
		# Descend when crouch is held - directly set velocity for responsive control
		velocity.y = -vertical_speed
	else:
		# Apply drag to vertical when no input
		velocity.y = move_toward(velocity.y, 0.0, vertical_speed * 0.5 * delta)

## Checks if we should exit the Float state
func _should_exit_float() -> bool:
	# Exit if gravity is back to normal AND we're on the ground
	if override_gravity_force < 0 and is_on_floor():
		return true
	
	# Also exit if gravity is normal and we were just passing through
	if override_gravity_force < 0:
		# Check if we're clearly falling (normal gravity behavior)
		# Give a small grace period before exiting
		return true
	
	return false

## Transitions to appropriate state when exiting Float
func _exit_float_state() -> void:
	if is_on_floor():
		# Check if this was a hard landing (should trigger roll)
		# Use last_velocity which is updated in motion.gd's apply_velocity() BEFORE move_and_slide()
		# This ensures we capture the velocity just before landing
		# Threshold: -7.5 for hard landing (roll), -5.0 for medium landing (landing animation)
		# Note: last_velocity.y is negative when falling, so <= -7.5 means falling faster than 7.5 units/sec
		if last_velocity.y <= -7.5:
			# Hard landing - transition to Roll state
			finished.emit("Roll")
		elif last_velocity.y <= -5.0:
			# Medium landing - play landing sound and transition to grounded state
			_play_landing_sound()
			
			# Transition to grounded state
			if direction != Vector3.ZERO:
				finished.emit("Walk")
			else:
				finished.emit("Idle")
		else:
			# Soft landing - transition to grounded state
			if direction != Vector3.ZERO:
				finished.emit("Walk")
			else:
				finished.emit("Idle")
	else:
		# Still in air but gravity is normal - transition to Fall
		finished.emit("Fall")

## Plays landing sound with dynamic volume and pitch based on landing velocity
## Uses movement_stats resource instead of accessing player properties directly
func _play_landing_sound() -> void:
	if not movement_stats:
		return
	
	var nodes: Dictionary = get_player_nodes()
	var footstep_player = nodes.get("footstep_player")
	if not footstep_player or not footstep_player.has_method("_play_interaction"):
		return
	
	var player: Node = get_player()
	if not player:
		return
	
	# Get landing sound parameters from movement_stats resource
	var landing_threshold: float = movement_stats.landing_threshold
	var min_landing_velocity: float = movement_stats.min_landing_velocity
	var max_landing_velocity: float = movement_stats.max_landing_velocity
	var min_volume_db: float = movement_stats.min_volume_db
	var max_volume_db: float = movement_stats.max_volume_db
	var max_pitch: float = movement_stats.max_pitch
	var min_pitch: float = movement_stats.min_pitch
	
	# Only play if velocity exceeds threshold
	if last_velocity.y < landing_threshold:
		var velocity_ratio: float = clamp((last_velocity.y - min_landing_velocity) / (max_landing_velocity - min_landing_velocity), 0.0, 1.0)
		var landing_volume: float = lerp(min_volume_db, max_volume_db, velocity_ratio)
		var landing_pitch: float = lerp(max_pitch, min_pitch, velocity_ratio)
		
		# Set LandingVolume and LandingPitch on player for FootstepSurfaceDetector
		# (This is still needed for the footstep system to work)
		if player.has_method("set"):
			player.set("LandingVolume", landing_volume)
			player.set("LandingPitch", landing_pitch)
		
		if footstep_player.has_method("set"):
			if footstep_player.get("volume_db") != null:
				footstep_player.set("volume_db", landing_volume)
			if footstep_player.get("pitch_scale") != null:
				footstep_player.set("pitch_scale", landing_pitch)
		
		footstep_player._play_interaction("landing")

