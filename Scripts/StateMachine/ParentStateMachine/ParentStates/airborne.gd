extends State

## Airborne parent state: Container for all air-based movement states.
## Automatically transitions to appropriate child state based on conditions:
## - Jump: If player just jumped (velocity.y > 0)
## - Fall: If player is descending (velocity.y <= 0)
## - AirControl: If enhanced air control is active
## - Float: If player is in zero-gravity, underwater, or space (gravity override active)

## Called when entering Airborne state
## Automatically transitions to appropriate child state based on conditions
func _enter() -> void:
	# Get player to check velocity
	# State hierarchy: Airborne -> StateMachine -> CogitoPlayer
	var state_machine = get_parent()
	var player = state_machine.get_parent() if state_machine else null
	
	if not player or not player is CharacterBody3D:
		# Default to Fall if we can't determine state
		var fall_state = get_node_or_null("Fall")
		if fall_state:
			finished.emit("Fall")
		return
	
	var player_body = player as CharacterBody3D
	var player_velocity = player_body.velocity
	
	# Determine which child state to enter
	if player_velocity.y > 0:
		# Ascending - enter Jump state
		var jump_state = get_node_or_null("Jump")
		if jump_state:
			finished.emit("Jump")
		else:
			finished.emit("Fall")
	else:
		# Descending or stationary - enter Fall state
		var fall_state = get_node_or_null("Fall")
		if fall_state:
			finished.emit("Fall")

## Updates airborne state (parent states typically don't do much)
## Child states handle all the actual logic
func _update(_delta: float) -> void:
	# Parent states are containers - child states do the work
	# Check if player has landed (should transition to Grounded)
	var state_machine = get_parent()
	var player = state_machine.get_parent() if state_machine else null
	
	if player and player is CharacterBody3D:
		var player_body = player as CharacterBody3D
		if player_body.is_on_floor():
			finished.emit("Grounded")
