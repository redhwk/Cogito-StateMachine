extends Motion

## Push state: Player is pushing a RigidBody3D object.
## Handles slower movement while pushing objects.
## Transitions to Walk when no longer pushing, or Airborne when leaving ground.

## Updates push movement and checks for state transitions
func _update(delta: float) -> void:
	set_direction()
	if movement_stats:
		# Push movement is slower than normal walking
		var push_speed: float = movement_stats.walking_speed * 0.7
		calculate_velocity(push_speed, direction, movement_stats.acceleration, delta)
	
	direction_updated.emit(input_dir)
	
	# Apply velocity with stair handling (RigidBody pushing happens in apply_velocity)
	apply_velocity(delta)
	
	# Check if we should exit push state
	# TODO: Detect if player is no longer pushing (check collision with RigidBody)
	# For now, transition based on input and floor state
	if direction == Vector3.ZERO:
		finished.emit("Idle")
	
	if not is_on_floor():
		finished.emit("Airborne")
