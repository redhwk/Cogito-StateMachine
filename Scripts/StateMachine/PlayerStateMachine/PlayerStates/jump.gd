extends Motion

## Jump state: Player is ascending after jumping.
## Handles jump from standing, crouch, or slide positions.
## Applies initial jump velocity and transitions to Fall when vertical velocity becomes negative.

## Applies initial jump velocity when entering jump state
func _enter() -> void:
	_jump()
	super._enter()

## Updates gravity and horizontal movement while ascending
## Transitions to Fall when vertical velocity reaches zero or becomes negative
## Does NOT transition to Float - Float is only entered from Fall when gravity is overridden
func _update(delta: float) -> void:
	set_direction()
	calculate_gravity(delta)
	if movement_stats:
		calculate_velocity(speed, direction, movement_stats.in_air_acceleration, delta)
	
	# Emit direction for animation (if AnimationController exists)
	direction_updated.emit(input_dir)
	
	# Apply velocity with stair handling
	apply_velocity(delta)
	
	# Only transition to Fall when velocity is negative (actually falling)
	# This ensures we reach full jump height before transitioning
	# NOTE: Do NOT check for Float here - Float should only be entered from Fall when gravity is overridden
	if velocity.y < 0:
		finished.emit("Fall")

## Applies initial upward velocity for the jump
## Handles different jump types: normal, crouch, slide, and bunny hop
func _jump() -> void:
	if not movement_stats:
		return
	
	var player: Node = get_player()
	if not player:
		return
	
	# Check if we can jump (stamina, crouch jump allowed, etc.)
	var can_jump: bool = true
	var jump_vel: float = movement_stats.jump_velocity
	
	# Check stamina if available
	if player.has_method("get") and player.get("stamina_attribute") != null:
		var stamina_attribute = player.get("stamina_attribute")
		if stamina_attribute and stamina_attribute.has_method("get"):
			var jump_exhaustion: float = 0.0
			if stamina_attribute.get("jump_exhaustion") != null:
				jump_exhaustion = stamina_attribute.get("jump_exhaustion")
			# Reduce jump stamina cost to 50% of configured value (make jumping less restrictive)
			jump_exhaustion = jump_exhaustion * 0.5
			
			var current_stamina: float = 0.0
			if stamina_attribute.get("value_current") != null:
				current_stamina = stamina_attribute.get("value_current")
			
			if current_stamina < jump_exhaustion:
				can_jump = false
			else:
				# Consume stamina (reduced amount)
				if player.has_method("decrease_attribute"):
					player.decrease_attribute("stamina", jump_exhaustion)
	
	# Check if crouch jump is allowed
	var nodes: Dictionary = get_player_nodes()
	var crouching_collision: CollisionShape3D = nodes.get("crouching_collision_shape")
	var is_crouching: bool = false
	if crouching_collision and not crouching_collision.disabled:
		is_crouching = true
		if not movement_stats.can_crouch_jump:
			can_jump = false
		else:
			jump_vel = movement_stats.crouch_jump_velocity
	
	if not can_jump:
		# Can't jump, return to previous state
		finished.emit("Grounded")
		return
	
	# Handle slide jump
	if jumped_from_slide:
		jump_vel = movement_stats.jump_velocity * movement_stats.slide_jump_mod
		jumped_from_slide = false
	
	# Apply jump velocity
	velocity.y = jump_vel
	
	# Play jump sound (if available on player)
	# Note: Audio resources could be moved to a separate AudioStats resource in the future
	if player.has_method("get") and player.get("jump_sound") != null:
		var jump_sound = player.get("jump_sound")
		if jump_sound:
			# Use Audio system if available
			if Audio and Audio.has_method("play_sound"):
				Audio.play_sound(jump_sound)
	
	# Play jump animation directly via AnimationPlayer (like the working version)
	var animation_player: AnimationPlayer = nodes.get("animation_player")
	if animation_player:
		animation_player.play("jump")
	
	# Handle bunny hop speed accumulation
	if movement_stats.can_bunnyhop:
		# Bunny hop speed is tracked in sprint state, but we can access it here
		# For now, just apply normal jump velocity
		pass
	
	# Switch collision shapes if crouching
	if is_crouching:
		var standing_collision: CollisionShape3D = nodes.get("standing_collision_shape")
		if standing_collision:
			standing_collision.disabled = false
		if crouching_collision:
			crouching_collision.disabled = true
