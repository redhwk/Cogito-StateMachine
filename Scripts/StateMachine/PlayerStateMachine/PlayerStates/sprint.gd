extends Motion

## Sprint state: Player is moving at maximum speed on the ground.
## Consumes sprint duration over time and transitions when sprint ends, movement stops, or jump is pressed.

## Handles input for jumping, crouching while sprinting, or releasing sprint key
func _state_input(event: InputEvent) -> void:
	var jump_timer: Timer = get_jump_timer()
	if event.is_action_pressed(InputConstants.INPUT_JUMP) and (not jump_timer or jump_timer.is_stopped()):
		if jump_timer:
			jump_timer.start()
		finished.emit("Jump")

	if event.is_action_released(InputConstants.INPUT_SPRINT):
		finished.emit("Walk")
	
	# Crouch while sprinting transitions to Slide
	if event.is_action_pressed(InputConstants.INPUT_CROUCH):
		finished.emit("Slide")
		

## Updates sprint movement, consumes sprint duration, and checks for state transitions
## Transitions to Walk when sprint key released or sprint duration depleted
## Transitions to Idle when movement stops
func _update(delta: float) -> void:
	set_direction()
	if movement_stats:
		calculate_velocity(sprint_speed, direction, movement_stats.acceleration, delta)
	direction_updated.emit(input_dir)
	
	# Consume sprint duration
	sprint_remaining -= delta
	
	# Consume stamina if available
	var player: Node = get_player()
	if player and player.has_method("get") and player.get("stamina_attribute") != null:
		var stamina_attribute = player.get("stamina_attribute")
		if stamina_attribute and stamina_attribute.has_method("get") and stamina_attribute.get("value_current") != null:
			var stamina_value = stamina_attribute.get("value_current")
			if stamina_value > 0:
				# Consume stamina over time (adjust rate as needed)
				if stamina_attribute.has_method("decrease") or player.has_method("decrease_attribute"):
					var stamina_drain: float = delta * 10.0  # Adjust drain rate as needed
					if player.has_method("decrease_attribute"):
						player.decrease_attribute("stamina", stamina_drain)
	
	# Apply headbob for sprinting
	var nodes: Dictionary = get_player_nodes()
	var eyes: Node3D = nodes.get("eyes")
	if eyes and headbob_stats:
		apply_headbob(eyes, delta, headbob_stats.wiggle_on_sprinting_intensity, headbob_stats.wiggle_on_sprinting_speed)
	
	# Play footstep sounds
	var footstep_player = nodes.get("footstep_player")
	if footstep_player:
		var sprint_volume_db: float = -30.0
		if player and player.has_method("get") and player.get("sprint_volume_db") != null:
			sprint_volume_db = player.get("sprint_volume_db")
		try_play_footstep(footstep_player, sprint_volume_db)
	
	# Apply velocity with stair handling
	apply_velocity(delta)
	
	if sprint_remaining <= 0.0:
		finished.emit("Walk")
	
	if direction == Vector3.ZERO:
		finished.emit("Idle")
	
	if not is_on_floor():
		finished.emit("Airborne")