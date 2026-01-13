extends Motion

## Crouch state: Player is crouched on the ground.
## Handles crouch depth, collision shapes, and transitions to Slide when sprinting.
## Transitions to Stand when crouch is released, Jump when jumping, or Slide when sprinting.

## Static variable to track crouch toggle state (for toggle_crouch mode)
static var try_crouch: bool = false

## Tracks if we just entered the state (to prevent immediate toggle on entry)
var just_entered: bool = false

## Called when entering Crouch state
## Syncs try_crouch with player property for save/load compatibility
func _enter() -> void:
	super._enter()
	# Set try_crouch to true when entering crouch state
	try_crouch = true
	# Mark that we just entered to prevent immediate toggle
	just_entered = true
	
	# Sync static variable with player property (for save/load)
	# Note: Don't set player.is_crouching here as it's a computed property
	# The collision shapes will be updated in _update() which will make is_crouching return true
	var player = get_player()
	if player:
		player.try_crouch = try_crouch
		# Don't set is_crouching - it's computed from collision shapes
		# Setting it could cause recursion if there's a setter

## Handles input for jumping and releasing crouch
func _state_input(_event: InputEvent) -> void:
	# Handle toggle crouch vs hold crouch
	if input_settings:
		if input_settings.toggle_crouch:
			# In toggle mode, only toggle on just_pressed (not on every frame)
			# Don't toggle if we just entered the state (prevents immediate exit)
			if Input.is_action_just_pressed(InputConstants.INPUT_CROUCH) and not just_entered:
				try_crouch = !try_crouch
			# Clear the just_entered flag after processing input
			if just_entered:
				just_entered = false
		else:
			# Hold mode - crouch only while key is pressed
			try_crouch = Input.is_action_pressed(InputConstants.INPUT_CROUCH)
			just_entered = false
	else:
		# Fallback if input_settings not available - use hold mode
		try_crouch = Input.is_action_pressed(InputConstants.INPUT_CROUCH)
		just_entered = false
	
	# Sync with player's try_crouch property for save/load compatibility
	var player = get_player()
	if player:
		player.try_crouch = try_crouch
		# Don't set is_crouching - it's computed from collision shapes
	
	# Jump from crouch - DISABLED (player shouldn't be able to jump from crouch)
	# Removed jump logic - crouch should not allow jumping
	
	# Sprint from crouch - DISABLED (player shouldn't be able to sprint while crouched)
	# If sprint is pressed while crouched, transition to Stand first, then Sprint will be handled by Stand/Walk
	# Removed sprint logic - crouch should not allow sprinting
	
	# Transition to stand if crouch released (hold mode) or toggled off
	# Only check this if we're not in the middle of entering the state
	if not try_crouch:
		finished.emit("Stand")

## Updates crouch movement, applies crouch depth, and checks for state transitions
func _update(delta: float) -> void:
	var nodes: Dictionary = get_player_nodes()
	var head: Node3D = nodes.get("head")
	var standing_collision: CollisionShape3D = nodes.get("standing_collision_shape")
	var crouching_collision: CollisionShape3D = nodes.get("crouching_collision_shape")
	var crouch_raycast: RayCast3D = nodes.get("crouch_raycast")
	
	if not head or not movement_stats:
		return
	
	# Check if we should stay crouched (toggle mode or raycast blocking)
	var should_crouch: bool = try_crouch
	if crouch_raycast and crouch_raycast.is_colliding():
		should_crouch = true
	
	# Check for exit transition BEFORE processing crouch logic
	# This ensures immediate exit when crouch is released
	# Don't exit if we just entered (prevents immediate exit on state entry)
	if not just_entered and not try_crouch and not (crouch_raycast and crouch_raycast.is_colliding()):
		finished.emit("Stand")
		return
	
	# Clear just_entered flag after first update (gives one frame grace period)
	if just_entered:
		just_entered = false
	
	if should_crouch:
		# Apply crouch depth to head position
		head.position.y = lerp(head.position.y, movement_stats.crouching_depth, delta * movement_stats.lerp_speed)
		
		# Switch collision shapes
		if standing_collision:
			standing_collision.disabled = true
		if crouching_collision:
			crouching_collision.disabled = false
		
		# Update movement
		set_direction()
		if movement_stats:
			calculate_velocity(movement_stats.crouching_speed, direction, movement_stats.acceleration, delta)
		direction_updated.emit(input_dir)
		
		# Apply crouch headbob ONLY when moving
		var eyes: Node3D = nodes.get("eyes")
		if eyes and headbob_stats and direction != Vector3.ZERO:
			apply_headbob(eyes, delta, headbob_stats.wiggle_on_crouching_intensity, headbob_stats.wiggle_on_crouching_speed)
		elif eyes and headbob_stats:
			# Reset headbob when not moving
			reset_headbob(eyes, delta)
		
		# Play footstep sounds
		var footstep_player = nodes.get("footstep_player")
		if footstep_player:
			var player: Node = get_player()
			var crouch_volume_db: float = -60.0
			if player and player.has_method("get") and player.get("crouch_volume_db") != null:
				crouch_volume_db = player.get("crouch_volume_db")
			try_play_footstep(footstep_player, crouch_volume_db)
		
		# Apply velocity with stair handling
		apply_velocity(delta)
		
		# Check for transitions
		if not is_on_floor():
			finished.emit("Airborne")
	else:
		# Transition to stand
		finished.emit("Stand")
