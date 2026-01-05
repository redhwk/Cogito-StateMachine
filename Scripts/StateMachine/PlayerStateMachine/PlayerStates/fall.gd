extends Motion

## Fall state: Player is descending through the air.
## Handles landing detection, landing sounds, and transitions to appropriate grounded state.
## Uses floor raycast for early landing detection and checks for hard landings (roll).

## RayCast3D pointing downward from player for early landing detection
## Automatically retrieved from player's StaircheckRayCast3D node
var floor_ray_cast: RayCast3D

## Called when entering the Fall state
func _enter() -> void:
	super._enter()
	# Get the StaircheckRayCast3D from the player node
	var player = get_player()
	if player and player.has_method("get_node"):
		floor_ray_cast = player.get_node_or_null("StaircheckRayCast3D") as RayCast3D

## Updates gravity and movement while falling
## Uses floor raycast to prepare landing animation before actual ground contact
## Transitions to Roll for hard landings, or Run/Idle for normal landings
## Transitions to Float if gravity is overridden (gravity zone)
func _update(delta: float) -> void:
	# Check if we should transition to Float state (gravity zone active)
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
	
	# Early landing detection via raycast
	if floor_ray_cast and floor_ray_cast.is_colliding():
		if direction != Vector3.ZERO:
			animation_change_requested.emit("Run")
		else:
			animation_change_requested.emit("Idle")
	
	# Check for landing
	if is_on_floor():
		# Check if this was a hard landing (should trigger roll)
		if last_velocity.y <= -7.5:
			# Hard landing - transition to Roll state
			finished.emit("Roll")
		elif last_velocity.y <= -5.0:
			# Medium landing - play landing animation
			var nodes: Dictionary = get_player_nodes()
			var animation_player: AnimationPlayer = nodes.get("animation_player")
			if animation_player:
				animation_player.play("landing")
			
			# Play landing sound with dynamic volume/pitch
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
func _play_landing_sound() -> void:
	var player: Node = get_player()
	if not player or not player.has_method("get"):
		return
	
	var nodes: Dictionary = get_player_nodes()
	var footstep_player = nodes.get("footstep_player")
	if not footstep_player or not footstep_player.has_method("_play_interaction"):
		return
	
	# Get landing sound parameters from player
	var landing_threshold: float = -2.0
	var min_landing_velocity: float = -2.0
	var max_landing_velocity: float = -8.0
	var min_volume_db: float = -40.0
	var max_volume_db: float = 0.0
	var max_pitch: float = 0.8
	var min_pitch: float = 0.7
	
	if player.get("landing_threshold") != null:
		landing_threshold = player.get("landing_threshold")
	if player.get("min_landing_velocity") != null:
		min_landing_velocity = player.get("min_landing_velocity")
	if player.get("max_landing_velocity") != null:
		max_landing_velocity = player.get("max_landing_velocity")
	if player.get("min_volume_db") != null:
		min_volume_db = player.get("min_volume_db")
	if player.get("max_volume_db") != null:
		max_volume_db = player.get("max_volume_db")
	if player.get("max_pitch") != null:
		max_pitch = player.get("max_pitch")
	if player.get("min_pitch") != null:
		min_pitch = player.get("min_pitch")
	
	# Only play if velocity exceeds threshold
	if last_velocity.y < landing_threshold:
		var velocity_ratio: float = clamp((last_velocity.y - min_landing_velocity) / (max_landing_velocity - min_landing_velocity), 0.0, 1.0)
		var landing_volume: float = lerp(min_volume_db, max_volume_db, velocity_ratio)
		var landing_pitch: float = lerp(max_pitch, min_pitch, velocity_ratio)
		
		# Set LandingVolume and LandingPitch on player for FootstepSurfaceDetector
		if player.has_method("set"):
			player.set("LandingVolume", landing_volume)
			player.set("LandingPitch", landing_pitch)
		
		if footstep_player.has_method("set"):
			if footstep_player.get("volume_db") != null:
				footstep_player.set("volume_db", landing_volume)
			if footstep_player.get("pitch_scale") != null:
				footstep_player.set("pitch_scale", landing_pitch)
		
		footstep_player._play_interaction("landing")
