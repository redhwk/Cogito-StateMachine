extends Motion

## Fall state: Player is descending through the air.
## Handles landing detection, landing sounds, and transitions to appropriate grounded state.
## Uses floor raycast for early landing detection and checks for hard landings (roll).

## RayCast3D pointing downward from player for early landing detection
## Automatically retrieved from player's StaircheckRayCast3D node
var floor_ray_cast: RayCast3D

## Tracks if we've already triggered the landing animation (prevents multiple triggers)
var landing_animation_triggered: bool = false

## Called when entering the Fall state
func _enter() -> void:
	super._enter()
	# Reset landing animation flag
	landing_animation_triggered = false
	# Get the StaircheckRayCast3D from the player node
	var player = get_player()
	if player and player.has_method("get_node"):
		floor_ray_cast = player.get_node_or_null("StaircheckRayCast3D") as RayCast3D

## Updates gravity and movement while falling
## Uses floor raycast to prepare landing animation before actual ground contact
## Transitions to Roll for hard landings, or Run/Idle for normal landings
## Transitions to Float if gravity is overridden (gravity zone)
## Note: Float transition happens as soon as override_gravity_force is set by gravity zone Area3D
func _update(delta: float) -> void:
	# Check if we should transition to Float state (gravity zone active)
	# Check this FIRST before any other processing to transition as early as possible
	# The gravity zone's Area3D body_entered signal sets override_gravity_force,
	# so this will trigger as soon as the player body enters the Area3D
	if override_gravity_force >= 0:
		finished.emit("Float")
		return
	
	set_direction()
	calculate_gravity(delta)
	if movement_stats:
		calculate_velocity(speed, direction, movement_stats.in_air_acceleration, delta)
	
	# Emit direction for animation (if AnimationController exists)
	direction_updated.emit(input_dir)
	
	# Apply velocity with stair handling
	apply_velocity(delta)
	
	# Early landing detection via raycast - trigger landing animation before hitting ground
	# Animation is handled by AnimationController via state machine transitions
	# No direct AnimationController calls needed - proper signal-based communication
	if floor_ray_cast and floor_ray_cast.is_colliding() and not landing_animation_triggered:
		# About to land - mark as triggered to prevent multiple calls
		landing_animation_triggered = true
	
	# Check for landing
	# IMPORTANT: Check is_on_floor() AFTER apply_velocity() so last_velocity is set correctly
	# last_velocity is set in motion.gd's apply_velocity() BEFORE move_and_slide()
	# This ensures we capture the velocity just before landing
	if is_on_floor():
		# Check if this was a hard landing (should trigger roll)
		# Use last_velocity which is updated in motion.gd's apply_velocity() BEFORE move_and_slide()
		# Threshold: -7.5 for hard landing (roll), -5.0 for medium landing (landing animation)
		# Note: last_velocity.y is negative when falling, so <= -7.5 means falling faster than 7.5 units/sec
		if last_velocity.y <= -7.5:
			# Hard landing - transition to Roll state
			finished.emit("Roll")
		elif last_velocity.y <= -5.0:
			# Medium landing - play landing sound and transition to grounded state
			# Animation is handled by AnimationController via state machine transitions
			_play_landing_sound()
			
			# Transition to grounded state
			if direction != Vector3.ZERO:
				finished.emit("Walk")
			else:
				finished.emit("Idle")
		else:
			# Soft landing - transition to Grounded parent (will auto-transition to Idle)
			finished.emit("Grounded")

## Plays landing sound with dynamic volume and pitch based on landing velocity
## Uses movement_stats resource instead of accessing player properties directly
func _play_landing_sound() -> void:
	if not movement_stats:
		return
	
	var nodes: Dictionary = get_player_nodes()
	var footstep_player = nodes.get("footstep_player")
	if not footstep_player or not footstep_player.has_method("_play_interaction"):
		return
	
	var player: Node = get_player()
	if not player:
		return
	
	# Get landing sound parameters from movement_stats resource
	var landing_threshold: float = movement_stats.landing_threshold
	var min_landing_velocity: float = movement_stats.min_landing_velocity
	var max_landing_velocity: float = movement_stats.max_landing_velocity
	var min_volume_db: float = movement_stats.min_volume_db
	var max_volume_db: float = movement_stats.max_volume_db
	var max_pitch: float = movement_stats.max_pitch
	var min_pitch: float = movement_stats.min_pitch
	
	# Only play if velocity exceeds threshold
	if last_velocity.y < landing_threshold:
		var velocity_ratio: float = clamp((last_velocity.y - min_landing_velocity) / (max_landing_velocity - min_landing_velocity), 0.0, 1.0)
		var landing_volume: float = lerp(min_volume_db, max_volume_db, velocity_ratio)
		var landing_pitch: float = lerp(max_pitch, min_pitch, velocity_ratio)
		
		# Set LandingVolume and LandingPitch on player for FootstepSurfaceDetector
		# (This is still needed for the footstep system to work)
		if player.has_method("set"):
			player.set("LandingVolume", landing_volume)
			player.set("LandingPitch", landing_pitch)
		
		if footstep_player.has_method("set"):
			if footstep_player.get("volume_db") != null:
				footstep_player.set("volume_db", landing_volume)
			if footstep_player.get("pitch_scale") != null:
				footstep_player.set("pitch_scale", landing_pitch)
		
		footstep_player._play_interaction("landing")
