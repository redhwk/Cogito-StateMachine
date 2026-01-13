extends Motion

## Roll state: Player is performing a roll animation after landing from a high fall.
## Handles landing sounds, fall damage, and roll animation.
## Transitions to Stand when roll completes.

## Static variable to track if we should transition to roll
static var should_roll: bool = false

## Called when entering roll state
func _enter() -> void:
	var nodes: Dictionary = get_player_nodes()
	var head: Node3D = nodes.get("head")
	var standing_collision: CollisionShape3D = nodes.get("standing_collision_shape")
	var crouching_collision: CollisionShape3D = nodes.get("crouching_collision_shape")
	
	if not movement_stats:
		return
	
	# Play roll animation directly via AnimationPlayer (like the working version)
	# The AnimationTree OneShot will also trigger, but this ensures the animation plays
	var animation_player: AnimationPlayer = nodes.get("animation_player")
	if animation_player and not movement_stats.disable_roll_anim:
		animation_player.play("roll")
	
	# Apply crouch position for roll
	if head:
		head.position.y = movement_stats.crouching_depth
	
	# Switch to crouch collision (disable standing, enable crouching)
	if standing_collision:
		standing_collision.disabled = true
	if crouching_collision:
		crouching_collision.disabled = false
	
	# Play landing sound with dynamic volume/pitch
	# Use movement_stats resource instead of accessing player properties directly
	if not movement_stats:
		return
	
	var player: Node = get_player()
	if player:
		var footstep_player = nodes.get("footstep_player")
		if footstep_player and footstep_player.has_method("_play_interaction"):
			# Get landing sound parameters from movement_stats resource
			var landing_threshold: float = movement_stats.landing_threshold
			var min_landing_velocity: float = movement_stats.min_landing_velocity
			var max_landing_velocity: float = movement_stats.max_landing_velocity
			var min_volume_db: float = movement_stats.min_volume_db
			var max_volume_db: float = movement_stats.max_volume_db
			var max_pitch: float = movement_stats.max_pitch
			var min_pitch: float = movement_stats.min_pitch
			
			if last_velocity.y < landing_threshold:
				var velocity_ratio: float = clamp((last_velocity.y - min_landing_velocity) / (max_landing_velocity - min_landing_velocity), 0.0, 1.0)
				var landing_volume: float = lerp(min_volume_db, max_volume_db, velocity_ratio)
				var landing_pitch: float = lerp(max_pitch, min_pitch, velocity_ratio)
				
				# Set LandingVolume and LandingPitch on player for FootstepSurfaceDetector
				# (This is still needed for the footstep system to work)
				if player.has_method("set"):
					player.set("LandingVolume", landing_volume)
					player.set("LandingPitch", landing_pitch)
				
				if footstep_player.has_method("set") and footstep_player.get("volume_db") != null:
					footstep_player.set("volume_db", landing_volume)
				if footstep_player.has_method("set") and footstep_player.get("pitch_scale") != null:
					footstep_player.set("pitch_scale", landing_pitch)
				
				footstep_player._play_interaction("landing")
		
		# Apply fall damage
		var fall_damage: int = 0
		var fall_damage_threshold: float = -5.0
		if player.get("fall_damage") != null:
			fall_damage = player.get("fall_damage")
		if player.get("fall_damage_threshold") != null:
			fall_damage_threshold = player.get("fall_damage_threshold")
		
		if fall_damage > 0 and last_velocity.y <= fall_damage_threshold:
			if player.has_method("decrease_attribute"):
				player.decrease_attribute("health", fall_damage)
	
	should_roll = false
	super._enter()

## Updates roll state and checks for completion
func _update(delta: float) -> void:
	# Get player nodes for head and movement
	var nodes: Dictionary = get_player_nodes()
	
	# Check if roll animation is finished (check AnimationPlayer directly like the working version)
	var animation_player: AnimationPlayer = nodes.get("animation_player")
	if animation_player:
		# Check if roll animation is still playing
		if not animation_player.is_playing() or animation_player.current_animation != "roll":
			# Roll animation complete, transition to Stand
			finished.emit("Stand")
			return
	
	# Keep head at crouch depth during roll
	var head: Node3D = nodes.get("head")
	if head and movement_stats:
		head.position.y = lerp(head.position.y, movement_stats.crouching_depth, delta * movement_stats.lerp_speed)
	
	# Minimal movement during roll
	set_direction()
	if movement_stats:
		calculate_velocity(movement_stats.crouching_speed * 0.5, direction, movement_stats.acceleration, delta)
	
	# Apply velocity
	apply_velocity(delta)
