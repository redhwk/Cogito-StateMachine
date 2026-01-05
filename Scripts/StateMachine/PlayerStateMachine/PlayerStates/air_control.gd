extends Motion

## AirControl state: Player has enhanced air control while airborne.
## Allows more horizontal movement control in the air compared to normal fall.
## Transitions to Fall when descending, or to grounded states when landing.

## Updates air movement with enhanced control
## Transitions to Fall when vertical velocity becomes negative
func _update(delta: float) -> void:
	set_direction()
	calculate_gravity(delta)
	if movement_stats:
		# Use in_air_acceleration for air control
		calculate_velocity(speed, direction, movement_stats.in_air_acceleration, delta)
	
	# Emit direction for animation (if AnimationController exists)
	direction_updated.emit(input_dir)
	
	# Apply velocity with stair handling
	apply_velocity(delta)
	
	# Transition to Fall when descending
	if velocity.y <= 0:
		finished.emit("Fall")
	
	# Transition to grounded states when landing
	if is_on_floor():
		if direction != Vector3.ZERO:
			finished.emit("Walk")
		else:
			finished.emit("Idle")
