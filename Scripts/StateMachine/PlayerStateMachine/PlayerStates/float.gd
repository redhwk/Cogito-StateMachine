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
	# Check if we should exit Float state
	if _should_exit_float():
		_exit_float_state()
		return
	
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
	
	# Emit direction for animation
	direction_updated.emit(input_dir)
	
	# Apply velocity (no stair handling while floating)
	apply_velocity(delta, false)

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
		if direction != Vector3.ZERO:
			finished.emit("Walk")
		else:
			finished.emit("Idle")
	else:
		# Still in air but gravity is normal - transition to Fall
		finished.emit("Fall")

