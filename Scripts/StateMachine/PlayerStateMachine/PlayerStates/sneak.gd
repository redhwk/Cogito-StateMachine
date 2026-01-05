extends Motion

## Sneak state: Player is sneaking (slower, quieter movement).
## Similar to Walk but with reduced speed and quieter footsteps.
## Transitions to Idle when movement stops, or Airborne when leaving ground.

## Handles input for jumping and sprinting while sneaking
func _state_input(event: InputEvent) -> void:
	var jump_timer: Timer = get_jump_timer()
	if event.is_action_pressed(InputConstants.INPUT_JUMP) and (not jump_timer or jump_timer.is_stopped()):
		if jump_timer:
			jump_timer.start()
		finished.emit("Jump")
	
	# Exit sneak when sprint is pressed
	if event.is_action_pressed(InputConstants.INPUT_SPRINT):
		finished.emit("Sprint")

## Updates sneak movement, emits direction for animation blending, and checks for state transitions
## Transitions to Idle when movement stops, Airborne when leaving ground
func _update(delta: float) -> void:
	set_direction()
	if movement_stats:
		# Sneak speed is slower than walking (adjust multiplier as needed)
		var sneak_speed: float = movement_stats.walking_speed * 0.6
		calculate_velocity(sneak_speed, direction, movement_stats.acceleration, delta)
	
	replenish_sprint(delta)
	direction_updated.emit(input_dir)
	
	# Apply headbob for sneaking (can use walking headbob or create separate)
	var nodes: Dictionary = get_player_nodes()
	var eyes: Node3D = nodes.get("eyes")
	if eyes and headbob_stats:
		# Use walking headbob but with reduced intensity for sneaking
		var sneak_intensity: float = headbob_stats.wiggle_on_walking_intensity * 0.5
		apply_headbob(eyes, delta, sneak_intensity, headbob_stats.wiggle_on_walking_speed)
	
	# Play quieter footstep sounds
	var footstep_player = nodes.get("footstep_player")
	if footstep_player:
		var player: Node = get_player()
		var sneak_volume_db: float = -50.0  # Quieter than walk
		if player and player.has_method("get") and player.get("walk_volume_db") != null:
			var walk_volume = player.get("walk_volume_db")
			sneak_volume_db = walk_volume - 12.0  # 12dB quieter than walk
		try_play_footstep(footstep_player, sneak_volume_db)
	
	# Apply velocity with stair handling
	apply_velocity(delta)
	
	if direction == Vector3.ZERO:
		finished.emit("Idle")
	
	if not is_on_floor():
		finished.emit("Airborne")
