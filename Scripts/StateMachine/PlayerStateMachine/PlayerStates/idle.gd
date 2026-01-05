extends Motion

## Idle state: Player is standing still on the ground.
## Transitions to another state when input is detected
## - Can go to: Walk (handles Sprint), Crouch, Jump, Sit, Airborne
##

## Handles input for jumping and aiming while idle
func _state_input(event: InputEvent) -> void:
	var jump_timer: Timer = get_jump_timer()
	if event.is_action_pressed(InputConstants.INPUT_JUMP) and (not jump_timer or jump_timer.is_stopped()):
		if jump_timer:
			jump_timer.start()
		finished.emit("Jump")
		
	if event.is_action_pressed(InputConstants.INPUT_CROUCH):
		finished.emit("Crouch")

## Updates movement, replenishes sprint, and checks for state transitions
## Transitions to Run when movement detected, Fall when leaving ground
## Transitions to Float when gravity is overridden (gravity zone)
func _update(delta: float) -> void:
	# Check if we should transition to Float state (gravity zone active)
	if override_gravity_force >= 0:
		# Gravity zone active - give player a small upward boost to lift off ground
		velocity.y = 1.0
		finished.emit("Float")
		return
	
	set_direction()
	if movement_stats:
		calculate_velocity(speed, direction, movement_stats.acceleration, delta)
	replenish_sprint(delta)
	
	# Apply velocity with stair handling
	apply_velocity(delta)
	
	if direction != Vector3.ZERO:
		finished.emit("Walk")
	
	if not is_on_floor():
		finished.emit("Airborne")

	# TODO: can to Sit or Stand when Idle
		#finished.emit("Sit")
		#finished.emit("Stand")
