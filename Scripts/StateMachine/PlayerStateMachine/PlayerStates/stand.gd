extends Motion

## Stand state: Player is standing up from crouch position.
## Smoothly transitions head position and collision shapes back to standing.
## Transitions to Idle when standing is complete, or Walk/Sprint when moving.

## Called when entering Stand state
func _enter() -> void:
	super._enter()

## Updates standing up animation and checks for state transitions
func _update(delta: float) -> void:
	var nodes: Dictionary = get_player_nodes()
	var head: Node3D = nodes.get("head")
	var standing_collision: CollisionShape3D = nodes.get("standing_collision_shape")
	var crouching_collision: CollisionShape3D = nodes.get("crouching_collision_shape")
	
	if not head or not movement_stats:
		# If head doesn't exist, just transition to Idle immediately
		finished.emit("Idle")
		return
	
	# Lerp head position back to 0 (standing position)
	var target_y = 0.0
	head.position.y = lerp(head.position.y, target_y, delta * movement_stats.lerp_speed)
	
	# Switch collision shapes when head is high enough
	if head.position.y < movement_stats.crouching_depth / 4.0:
		# Still transitioning - keep crouch collision
		if crouching_collision:
			crouching_collision.disabled = false
		if standing_collision:
			standing_collision.disabled = true
	else:
		# Transition complete - use standing collision
		if standing_collision:
			standing_collision.disabled = false
		if crouching_collision:
			crouching_collision.disabled = true
	
	# Reset headbob
	var eyes: Node3D = nodes.get("eyes")
	if eyes:
		reset_headbob(eyes, delta)
	
	# Update movement
	set_direction()
	if movement_stats:
		calculate_velocity(speed, direction, movement_stats.acceleration, delta)
	direction_updated.emit(input_dir)
	
	# Apply velocity with stair handling
	apply_velocity(delta)
	
	# Check for transitions - ensure head is close to standing position before transitioning
	# This prevents transitioning too early when moving, which would leave head at intermediate position
	var head_close_to_standing: bool = abs(head.position.y - target_y) < 0.1
	
	if head_close_to_standing:
		# Head is at standing position, can transition based on movement
		if direction != Vector3.ZERO:
			# Check if sprinting
			if Input.is_action_pressed(InputConstants.INPUT_SPRINT) and sprint_remaining > movement_stats.minimum_sprint_threshold:
				finished.emit("Sprint")
			else:
				finished.emit("Walk")
		else:
			finished.emit("Idle")
	
	if not is_on_floor():
		finished.emit("Airborne")
