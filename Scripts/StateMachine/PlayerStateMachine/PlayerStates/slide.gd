extends Motion

## Slide state: Player is sliding (sprint + crouch) on the ground.
## Uses slide timer to control slide duration and speed decay.
## Transitions to Sprint when slide ends (if sprinting), Walk when slide ends (if walking), or Jump when jumping.

## Reference to Crouch state script for accessing static try_crouch variable
const CrouchState = preload("res://Scripts/StateMachine/PlayerStateMachine/PlayerStates/crouch.gd")

## Track the state we came from (Sprint or Walk) so we can return to it
var previous_state: String = "Sprint"

## Called when entering slide state
func _enter() -> void:
	super._enter()  # Call parent _enter() for animation request
	
	var nodes: Dictionary = get_player_nodes()
	var sliding_timer: Timer = nodes.get("sliding_timer")
	var head: Node3D = nodes.get("head")
	var standing_collision: CollisionShape3D = nodes.get("standing_collision_shape")
	var crouching_collision: CollisionShape3D = nodes.get("crouching_collision_shape")
	
	# Determine previous state by checking if sprint is still pressed
	# If sprint is pressed, we came from Sprint, otherwise from Walk
	if Input.is_action_pressed(InputConstants.INPUT_SPRINT):
		previous_state = "Sprint"
	else:
		previous_state = "Walk"
	
	# Store slide direction from current input
	slide_vector = input_dir
	
	# Start slide timer if available
	if sliding_timer:
		sliding_timer.start()
	
	# Tween head to crouch position for smooth slide transition
	if head and movement_stats:
		var tween = get_tree().create_tween()
		tween.tween_property(head, "position:y", movement_stats.crouching_depth, 0.2)
	
	# Switch collision shapes immediately
	if standing_collision:
		standing_collision.disabled = true
	if crouching_collision:
		crouching_collision.disabled = false
	
	# Play slide audio
	var player: Node = get_player()
	if player and player.has_method("get") and player.get("slide_audio_player") != null:
		var slide_audio_player = player.get("slide_audio_player")
		if slide_audio_player and slide_audio_player.has_method("play"):
			slide_audio_player.play()

## Called when exiting slide state
func _exit() -> void:
	var nodes: Dictionary = get_player_nodes()
	var sliding_timer: Timer = nodes.get("sliding_timer")
	var head: Node3D = nodes.get("head")
	var standing_collision: CollisionShape3D = nodes.get("standing_collision_shape")
	var crouching_collision: CollisionShape3D = nodes.get("crouching_collision_shape")
	
	# Stop slide timer
	if sliding_timer:
		sliding_timer.stop()
	
	# Restore head position and collision shapes when exiting slide
	# If transitioning to Sprint, smoothly tween head back to standing position
	# Otherwise, reset immediately
	if head and movement_stats:
		# Check if we're transitioning to Sprint (smooth transition)
		# We'll use a tween to smoothly raise the head
		var tween = get_tree().create_tween()
		tween.tween_property(head, "position:y", 0.0, 0.15)
		# For other transitions, we can still tween but faster
		# The tween will complete even if we transition states
	
	# Restore collision shapes to standing
	if standing_collision:
		standing_collision.disabled = false
	if crouching_collision:
		crouching_collision.disabled = true
	
	# Reset eyes tilt
	var eyes: Node3D = nodes.get("eyes")
	if eyes:
		eyes.rotation.z = 0.0
	
	# Ensure try_crouch is false (player should not stay crouched after slide)
	CrouchState.try_crouch = false
	
	# Stop slide audio
	var player: Node = get_player()
	if player and player.has_method("get") and player.get("slide_audio_player") != null:
		var slide_audio_player = player.get("slide_audio_player")
		if slide_audio_player and slide_audio_player.has_method("stop"):
			slide_audio_player.stop()

## Handles input for jumping from slide or releasing crouch
func _state_input(event: InputEvent) -> void:
	var jump_timer: Timer = get_jump_timer()
	if event.is_action_pressed(InputConstants.INPUT_JUMP) and (not jump_timer or jump_timer.is_stopped()):
		if jump_timer:
			jump_timer.start()
		# Mark that we jumped from slide
		jumped_from_slide = true
		finished.emit("Jump")
	
	# Release crouch to exit slide (ignore toggle mode - just check button release)
	# Exit to previous state (Sprint if sprinting, Walk if walking)
	if event.is_action_released(InputConstants.INPUT_CROUCH):
		# Set try_crouch to false since user released crouch
		CrouchState.try_crouch = false
		finished.emit(previous_state)
	
	# Release sprint to exit slide (go to Walk)
	if event.is_action_released(InputConstants.INPUT_SPRINT):
		previous_state = "Walk"  # Update previous state since sprint was released
		finished.emit("Walk")

## Updates slide movement, applies slide speed decay, and checks for state transitions
func _update(delta: float) -> void:
	var nodes: Dictionary = get_player_nodes()
	var sliding_timer: Timer = nodes.get("sliding_timer")
	var body: Node3D = nodes.get("body")
	
	if not movement_stats or not body:
		return
	
	# Calculate slide speed based on timer (decays over time)
	var slide_speed_current: float = movement_stats.sliding_speed
	if sliding_timer and not sliding_timer.is_stopped():
		# Speed decays as timer runs out: starts at 1.5x, ends at 0.5x
		var timer_ratio: float = sliding_timer.time_left / sliding_timer.wait_time
		slide_speed_current = (timer_ratio + 0.5) * movement_stats.sliding_speed
	else:
		# Timer finished, exit slide to previous state (Sprint if sprinting, Walk if walking)
		# Set try_crouch to false since slide ended (player should not stay crouched)
		CrouchState.try_crouch = false
		finished.emit(previous_state)
		return
	
	# Use slide direction (locked when slide started)
	var slide_direction: Vector3 = (body.global_transform.basis * Vector3(slide_vector.x, 0.0, slide_vector.y)).normalized()
	
	# Calculate velocity using slide speed
	calculate_velocity(slide_speed_current, slide_direction, movement_stats.acceleration, delta)
	direction_updated.emit(slide_vector)
	
	# Apply free look tilt during slide (eyes rotation)
	var eyes: Node3D = nodes.get("eyes")
	if eyes and free_look_settings:
		var target_tilt: float = deg_to_rad(4.0)
		if movement_stats:
			eyes.rotation.z = lerp(eyes.rotation.z, target_tilt, delta * movement_stats.lerp_speed)
	
	# Apply velocity with stair handling
	apply_velocity(delta)
	
	# Check for transitions
	if not is_on_floor():
		finished.emit("Airborne")