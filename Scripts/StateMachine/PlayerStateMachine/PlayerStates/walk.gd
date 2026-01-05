extends Motion

## Run state: Player is moving on the ground at normal speed.
## Transitions to Idle when movement stops, Sprint when sprint is pressed, Jump when jumping, or AimWalk when aiming.

## Handles input for jumping, sprinting, crouching, and aiming while running
func _state_input(event: InputEvent) -> void:
	var jump_timer: Timer = get_jump_timer()
	if event.is_action_pressed(InputConstants.INPUT_JUMP) and (not jump_timer or jump_timer.is_stopped()):
		if jump_timer:
			jump_timer.start()
		finished.emit("Jump")
		
	if movement_stats and event.is_action_pressed(InputConstants.INPUT_SPRINT) and sprint_remaining > movement_stats.minimum_sprint_threshold:
		finished.emit("Sprint")
	
	# Crouch while walking transitions to Crouch (not Slide - Slide only comes from Sprint)
	if event.is_action_pressed(InputConstants.INPUT_CROUCH):
		finished.emit("Crouch")


## Updates movement, emits direction for animation blending, and checks for state transitions
## Transitions to Idle when movement stops, Airborne when leaving ground
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
	direction_updated.emit(input_dir)
	
	# Apply headbob for walking
	var nodes: Dictionary = get_player_nodes()
	var eyes: Node3D = nodes.get("eyes")
	if eyes and headbob_stats:
		apply_headbob(eyes, delta, headbob_stats.wiggle_on_walking_intensity, headbob_stats.wiggle_on_walking_speed)
	
	# Play footstep sounds
	var footstep_player = nodes.get("footstep_player")
	if footstep_player:
		# Get walk volume from player (will be moved to resource later)
		var player: Node = get_player()
		var walk_volume_db: float = -38.0
		if player and player.has_method("get") and player.get("walk_volume_db") != null:
			walk_volume_db = player.get("walk_volume_db")
		try_play_footstep(footstep_player, walk_volume_db)
	
	# Apply velocity with stair handling
	apply_velocity(delta)
	
	if direction == Vector3.ZERO:
		finished.emit("Idle")
	
	if not is_on_floor():
		finished.emit("Airborne")
