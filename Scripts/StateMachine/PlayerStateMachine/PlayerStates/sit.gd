extends State

## Sit state: Player is sitting on a sittable object.
## Handles tweening to sit position, look marker constraints, and standing up.
## Can be entered from any Grounded state (Idle, Crouch, Stand, Sneak).
## Exits to Grounded parent (if on floor) or Airborne parent (if not on floor).


## Reference to player node (CogitoPlayer) - set in _ready
var player: Node

## Sittable state tracking
var is_sitting: bool = false
var original_position: Transform3D
var displacement_position: Vector3
var sittable_look_marker: Vector3
var sittable_look_angle: float
var moving_seat: bool = false
var original_neck_basis: Basis = Basis()
var original_body_basis: Basis = Basis()
var original_body_local_basis: Basis = Basis()
var is_ejected: bool = false
var currently_tweening: bool = false
var original_sittable_basis: Basis = Basis()  # Save sittable rotation for physics-based restoration
var active_tween: Tween = null  # Track active tween so we can kill it if needed
var is_exiting: bool = false  # Prevent re-entrance during exit process
var last_exit_time: int = 0  # Timestamp of last exit (ms) - prevents immediate re-sit
const EXIT_COOLDOWN_MS: int = 500  # Cooldown before player can sit again after standing

## Player node references
var body: Node3D
var neck: Node3D
var head: Node3D
var standing_collision_shape: CollisionShape3D
var crouching_collision_shape: CollisionShape3D
var navigation_agent: NavigationAgent3D

## Input settings for look sensitivity
var input_settings: InputSettings

## Called when entering Sit state
func _enter() -> void:
	# Check cooldown - prevent immediate re-sit after standing up
	# This stops the same input from triggering both stand up AND sit down
	var current_time = Time.get_ticks_msec()
	if last_exit_time > 0 and (current_time - last_exit_time) < EXIT_COOLDOWN_MS:
		# Still in cooldown, cancel this sit attempt and return to Grounded
		call_deferred("_cancel_sit_cooldown")
		return
	
	# Get player node - Sit state is under Grounded, which is under StateMachine
	# Hierarchy: Sit -> Grounded -> StateMachine -> CogitoPlayer
	# Walk up the tree to find the actual PlayerStateMachine node
	var current = get_parent()
	var state_machine_node = null
	
	# Walk up to find the StateMachine (PlayerStateMachine)
	while current:
		if current is StateMachine:
			state_machine_node = current
			break
		current = current.get_parent()
	
	# Try to get player from StateMachine's player property
	if state_machine_node and "player" in state_machine_node:
		player = state_machine_node.player
	
	# Fallback: walk up from StateMachine to get player
	if (not player or not player is CharacterBody3D) and state_machine_node:
		player = state_machine_node.get_parent()
	
	# Verify player is actually a CharacterBody3D (CogitoPlayer extends CharacterBody3D)
	if not player or not player is CharacterBody3D:
		push_error("Sit state: Could not find player node (CogitoPlayer)")
		return
	
	# Cache player nodes
	body = player.get_node_or_null("Body") as Node3D
	neck = player.get_node_or_null("Body/Neck") as Node3D
	head = player.get_node_or_null("Body/Neck/Head") as Node3D
	standing_collision_shape = player.get_node_or_null("StandingCollisionShape") as CollisionShape3D
	crouching_collision_shape = player.get_node_or_null("CrouchingCollisionShape") as CollisionShape3D
	navigation_agent = player.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	
	# Get input settings from PlayerStateMachine
	if state_machine_node and state_machine_node.has_method("get") and state_machine_node.get("player_resources") != null:
		var player_resources = state_machine_node.get("player_resources")
		if player_resources and player_resources.has_method("get") and player_resources.get("input_settings") != null:
			input_settings = player_resources.get("input_settings")
	
	# Lock body rotation while sitting to prevent external changes (pickup interactions, etc.)
	if state_machine_node and "body_rotation_locked" in state_machine_node:
		state_machine_node.body_rotation_locked = true
	
	# Reset state flags
	is_exiting = false
	is_sitting = false
	currently_tweening = false
	
	# Reset all motion variables when entering sit state
	# This prevents direction confusion and velocity carryover
	Motion.input_dir = Vector2.ZERO
	Motion.direction = Vector3.ZERO
	Motion.velocity = Vector3.ZERO
	Motion.last_velocity = Vector3.ZERO
	
	# Start sitting down (animation will be handled automatically by AnimationController)
	_sit_down()

## Called when exiting Sit state
func _exit() -> void:
	# Unlock body rotation after state transition is complete
	# This ensures mouse look can't interfere during the transition
	# The unlock function will also handle the final restore
	call_deferred("_unlock_body_rotation")

## Called when sit is cancelled due to cooldown (deferred to avoid signal issues)
func _cancel_sit_cooldown() -> void:
	# Immediately transition back to Grounded - we just stood up and shouldn't sit again
	var state_machine = get_parent()
	while state_machine and not state_machine is StateMachine:
		state_machine = state_machine.get_parent()
	
	if state_machine and state_machine.has_method("_change_state"):
		state_machine._change_state("Grounded")
	else:
		finished.emit("Grounded")

## Deferred function to restore Body rotation after state exit
## This is a safety net in case _stand_up_finished() hasn't run yet
## It does NOT lock the rotation since _stand_up_finished() handles that
func _restore_body_rotation() -> void:
	# Get the PlayerStateMachine to check if we should restore
	var state_machine = get_parent()
	while state_machine and not state_machine is StateMachine:
		state_machine = state_machine.get_parent()
	
	# Check if rotation is already unlocked (meaning _stand_up_finished() has run)
	if state_machine and "body_rotation_locked" in state_machine:
		if not state_machine.body_rotation_locked:
			return
	
	# Check if physics-based sittable
	var sittable = CogitoSceneManager._current_sittable_node
	var physics_sittable: bool = false
	if sittable and sittable.has_method("get") and sittable.get("physics_sittable") != null:
		physics_sittable = sittable.get("physics_sittable")
	
	# STEP 1 & 2: Restore Player and Body rotation (in correct order)
	if physics_sittable and sittable and original_sittable_basis != Basis():
		# Only use Y rotation (yaw) to keep player upright
		var current_sittable_euler = sittable.global_transform.basis.get_euler()
		var original_sittable_euler = original_sittable_basis.get_euler()
		var y_rotation_delta = current_sittable_euler.y - original_sittable_euler.y
		var y_rotation_delta_basis = Basis.from_euler(Vector3(0, y_rotation_delta, 0))
		
		if original_position != Transform3D():
			var adjusted_player_basis = y_rotation_delta_basis * original_position.basis
			player.global_transform.basis = adjusted_player_basis
		
		if body and original_body_basis != Basis():
			var adjusted_body_basis = y_rotation_delta_basis * original_body_basis
			body.global_transform.basis = adjusted_body_basis
		elif body and original_body_local_basis != Basis():
			var adjusted_player_basis = y_rotation_delta_basis * original_position.basis
			var calculated_global = adjusted_player_basis * original_body_local_basis
			body.global_transform.basis = calculated_global
	else:
		if original_position != Transform3D():
			player.global_transform.basis = original_position.basis
		if body and original_body_basis != Basis():
			body.global_transform.basis = original_body_basis
		elif body and original_body_local_basis != Basis():
			var calculated_global = player.global_transform.basis * original_body_local_basis
			body.global_transform.basis = calculated_global
	
	# STEP 3: Reset Neck rotation AFTER player and body
	if neck:
		neck.rotation = Vector3.ZERO
	
	# STEP 4: Reset Head rotation
	if head:
		head.rotation = Vector3.ZERO
	
	# Note: We don't lock or unlock here - _stand_up_finished() handles that

## Unlocks body rotation after state exit is complete
## Called deferred from _exit() to ensure state transition is finished
## Also performs final restore to ensure rotation is correct before unlocking
func _unlock_body_rotation() -> void:
	var state_machine = get_parent()
	while state_machine and not state_machine is StateMachine:
		state_machine = state_machine.get_parent()
	
	if state_machine and "body_rotation_locked" in state_machine:
		# Final restore - check if physics-based sittable
		var sittable = CogitoSceneManager._current_sittable_node
		var physics_sittable: bool = false
		if sittable and sittable.has_method("get") and sittable.get("physics_sittable") != null:
			physics_sittable = sittable.get("physics_sittable")
		
		# STEP 1 & 2: Restore Player and Body rotation (in correct order)
		if physics_sittable and sittable and original_sittable_basis != Basis():
			# Only use Y rotation (yaw) to keep player upright
			var current_sittable_euler = sittable.global_transform.basis.get_euler()
			var original_sittable_euler = original_sittable_basis.get_euler()
			var y_rotation_delta = current_sittable_euler.y - original_sittable_euler.y
			var y_rotation_delta_basis = Basis.from_euler(Vector3(0, y_rotation_delta, 0))
			
			if original_position != Transform3D():
				var adjusted_player_basis = y_rotation_delta_basis * original_position.basis
				player.global_transform.basis = adjusted_player_basis
			
			if body and original_body_basis != Basis():
				var adjusted_body_basis = y_rotation_delta_basis * original_body_basis
				body.global_transform.basis = adjusted_body_basis
		else:
			if original_position != Transform3D():
				player.global_transform.basis = original_position.basis
			if body and original_body_basis != Basis():
				body.global_transform.basis = original_body_basis
		
		# STEP 3: Reset Neck rotation AFTER player and body
		if neck:
			neck.rotation = Vector3.ZERO
		
		# STEP 4: Reset Head rotation
		if head:
			head.rotation = Vector3.ZERO
		
		# Immediately unlock so mouse look works right away
		state_machine.body_rotation_locked = false

## Handles input for standing up and sitting look
func _state_input(event: InputEvent) -> void:
	# Handle interact input
	if event.is_action_pressed(InputConstants.INPUT_INTERACT):
		# Check if player is looking at an interactable that ISN'T the current sittable
		# If so, let the interaction component handle it (e.g., picking up coins while sitting)
		var has_other_interactable = false
		if player and player.has_node("PlayerInteractionComponent"):
			var interaction_component = player.get_node("PlayerInteractionComponent")
			if interaction_component.has_method("get") and interaction_component.get("interactable") != null:
				var current_interactable = interaction_component.get("interactable")
				var current_sittable = CogitoSceneManager._current_sittable_node
				# If looking at something other than the sittable, let interaction handle it
				if current_interactable and current_interactable != current_sittable:
					has_other_interactable = true
		
		# Only stand up if NOT looking at another interactable
		if not has_other_interactable:
			# Prevent re-entrance - don't call _stand_up() multiple times
			if not is_exiting:
				_stand_up()
		# If looking at another interactable, don't consume the input - let it propagate
		else:
			return
		return
	
	# Block jump input while sitting
	if event.is_action_pressed(InputConstants.INPUT_JUMP):
		return
	
	# Handle sitting look (mouse movement)
	if event is InputEventMouseMotion and is_sitting and not currently_tweening:
		_handle_sitting_look(event)

## Updates sit state - handles physics-based sittables, ejection, and gamepad look
func _update(delta: float) -> void:
	if not is_sitting or currently_tweening:
		return
	
	var sittable = CogitoSceneManager._current_sittable_node
	if not sittable:
		_stand_up()
		return
	
	# Handle physics-based sittables (vehicles, moving chairs, etc.)
	var physics_sittable: bool = false
	if sittable.has_method("get") and sittable.get("physics_sittable") != null:
		physics_sittable = sittable.get("physics_sittable")
	
	if physics_sittable:
		var sit_position_node = null
		if sittable.has_method("get") and sittable.get("sit_position_node") != null:
			sit_position_node = sittable.get("sit_position_node")
		
		if sit_position_node:
			# Keep player aligned with moving sittable
			# IMPORTANT: Only copy position and Y rotation (yaw), not full transform
			# This prevents the player from tipping over if the sittable tips
			var sit_marker_transform = sit_position_node.global_transform
			
			# Extract only the Y rotation (yaw) from the sit marker
			# Keep the player upright by only rotating around Y axis
			var sit_marker_euler = sit_marker_transform.basis.get_euler()
			var upright_basis = Basis.from_euler(Vector3(0, sit_marker_euler.y, 0))
			
			# Apply position and upright rotation to the PLAYER CharacterBody3D only
			# Do NOT touch the Body node - that's used for camera look and should be controlled by mouse input
			player.global_position = sit_marker_transform.origin
			player.global_transform.basis = upright_basis
		
		# Check for ejection (sittable has fallen over)
		if not is_ejected and sittable.has_method("get") and sittable.get("eject_on_fall") != null:
			var eject_on_fall: bool = sittable.get("eject_on_fall")
			if eject_on_fall:
				var chair_up_vector = sittable.global_transform.basis.y
				var global_up_vector = Vector3(0, 1, 0)
				var angle_to_up = rad_to_deg(chair_up_vector.angle_to(global_up_vector))
				
				var eject_angle: float = 45.0
				if sittable.has_method("get") and sittable.get("eject_angle") != null:
					eject_angle = sittable.get("eject_angle")
				
				if angle_to_up > eject_angle:
					is_ejected = true
					# Trigger ejection via interaction
					if player.has_method("get") and player.get("player_interaction_component") != null:
						var interaction_component = player.get("player_interaction_component")
						if sittable.has_method("interact"):
							sittable.interact(interaction_component)
	
	# Handle gamepad look while sitting (TODO: Add look marker constraint support)
	# For now, basic gamepad look - can be enhanced later
	if input_settings and neck and head:
		# Get gamepad events from PlayerStateMachine (stored there)
		var state_machine = get_parent()
		if state_machine and state_machine.has_method("get"):
			var joystick_h_event = state_machine.get("joystick_h_event") if state_machine.has_method("get") else null
			var joystick_v_event = state_machine.get("joystick_v_event") if state_machine.has_method("get") else null
			
			if joystick_h_event and abs(joystick_h_event.get_axis_value()) > input_settings.joy_deadzone:
				if input_settings.invert_y_axis:
					head.rotate_x(deg_to_rad(joystick_h_event.get_axis_value() * input_settings.joy_h_sens * delta))
				else:
					head.rotate_x(-deg_to_rad(joystick_h_event.get_axis_value() * input_settings.joy_h_sens * delta))
				
				var vertical_look_angle: float = 90.0
				if sittable.has_method("get") and sittable.get("vertical_look_angle") != null:
					vertical_look_angle = sittable.get("vertical_look_angle")
				head.rotation.x = clamp(head.rotation.x, deg_to_rad(-vertical_look_angle), deg_to_rad(vertical_look_angle))
			
			if joystick_v_event and abs(joystick_v_event.get_axis_value()) > input_settings.joy_deadzone:
				neck.rotate_y(deg_to_rad(-joystick_v_event.get_axis_value() * input_settings.joy_v_sens * delta))
				neck.rotation.y = clamp(neck.rotation.y, deg_to_rad(-180), deg_to_rad(180))
	
	# Check if we should exit (ejected or no longer sitting)
	if is_ejected:
		_stand_up()
		return
	
	# Check for exit transitions based on floor state
	if player.has_method("is_on_floor") and not player.is_on_floor():
		# Not on floor - exit to Airborne parent
		finished.emit("Airborne")

## Initiates sitting down sequence
func _sit_down() -> void:
	if not standing_collision_shape or not crouching_collision_shape:
		return
	
	standing_collision_shape.disabled = true
	crouching_collision_shape.disabled = true
	is_ejected = false
	
	var sittable = CogitoSceneManager._current_sittable_node
	if not sittable:
		# No sittable, exit state
		finished.emit("Grounded")
		return
	
	# Don't set is_sitting to true yet - wait until tween completes
	# Don't disable physics_process yet - need it for the tween to work
	# is_sitting = true
	# if player.has_method("set_physics_process"):
	#	player.set_physics_process(false)
	
	if sittable.has_method("get") and sittable.get("look_marker_node") != null:
		var look_marker = sittable.get("look_marker_node")
		if look_marker:
			sittable_look_marker = look_marker.global_transform.origin
	
	if sittable.has_method("get") and sittable.get("horizontal_look_angle") != null:
		sittable_look_angle = sittable.get("horizontal_look_angle")
	
	if not moving_seat:
		original_position = player.global_transform
		if neck:
			original_neck_basis = neck.global_transform.basis
		# Note: We don't save head rotation - we always reset it to 0 when standing up
		# because the head can rotate while sitting (looking up/down)
		if body:
			# Save Body node's rotation - this is used for direction calculation
			# Save both global and local transforms
			original_body_basis = body.global_transform.basis
			original_body_local_basis = body.transform.basis
		if sittable.has_method("get") and sittable.get("global_transform") != null:
			displacement_position = sittable.global_transform.origin - player.global_transform.origin
			# Save sittable rotation for physics-based restoration
			original_sittable_basis = sittable.global_transform.basis
	
	# Check if sittable is physics-based
	var physics_sittable: bool = false
	if sittable.has_method("get") and sittable.get("physics_sittable") != null:
		physics_sittable = sittable.get("physics_sittable")
	
	var sit_position_node = null
	# Get sit_position_node from the sittable (it's a member variable set in _ready())
	# Try direct property access first
	if "sit_position_node" in sittable:
		sit_position_node = sittable.sit_position_node
	
	# If still null, try to get it from the node path directly
	if not sit_position_node:
		var sit_path = null
		if "sit_position_node_path" in sittable:
			sit_path = sittable.sit_position_node_path
		if sit_path and sit_path != NodePath() and sittable.has_method("get_node_or_null"):
			sit_position_node = sittable.get_node_or_null(sit_path) as Node3D
	
	if not sit_position_node:
		push_error("Sit state: Could not find sit_position_node in sittable. Make sure sit_position_node_path is set in the sittable.")
		finished.emit("Grounded")
		return
	
	var tween_duration: float = 1.0
	if sittable.has_method("get") and sittable.get("tween_duration") != null:
		tween_duration = sittable.get("tween_duration")
	
	currently_tweening = true
	
	# Create tween to move player to sit position
	# Store in active_tween so we can kill it if player presses stand-up early
	active_tween = get_tree().create_tween()
	active_tween.set_parallel(false)  # Sequential tweening
	active_tween.tween_property(player, "global_transform", sit_position_node.global_transform, tween_duration)
	active_tween.tween_callback(_sit_down_finished)
	
	
	
	# For physics-based sittables, keep physics_process enabled
	# For non-physics sittables, disable it after tween completes
	if not physics_sittable:
		# Will disable physics_process in _sit_down_finished()
		pass

## Called when sit down tween completes
func _sit_down_finished() -> void:
	active_tween = null  # Clear the tween reference
	currently_tweening = false
	is_sitting = true
	
	var sittable = CogitoSceneManager._current_sittable_node
	if not sittable:
		finished.emit("Grounded")
		return
	
	# Check if physics-based - if not, disable physics_process now
	var physics_sittable: bool = false
	if "physics_sittable" in sittable:
		physics_sittable = sittable.physics_sittable
	
	if not physics_sittable:
		if player.has_method("set_physics_process"):
			player.set_physics_process(false)
	
	# Call sittable's _sit_down() to play animation and update state
	# This should be called AFTER the player has moved to the sit position
	if sittable.has_method("_sit_down"):
		sittable._sit_down()
	
	# Also manually play the animation if _sit_down() didn't handle it
	# Get animation_player directly from the sittable
	var anim_player = null
	if "animation_player" in sittable:
		anim_player = sittable.animation_player
	
	# If animation_player is null, try to get it from the node path
	if not anim_player and "animation_player_node_path" in sittable:
		var anim_path = sittable.animation_player_node_path
		if anim_path != NodePath() and sittable.has_method("get_node_or_null"):
			anim_player = sittable.get_node_or_null(anim_path) as AnimationPlayer
	
	# Play animation if we have both player and animation name
	if anim_player:
		var anim_name = ""
		if "animation_on_enter" in sittable:
			anim_name = sittable.animation_on_enter
		
		if anim_name and anim_name != "":
			anim_player.play(anim_name)
	
	# Sync player properties for save/load
	if player.has_method("set"):
		player.set("is_sitting", true)
		player.set("sittable_look_marker", sittable_look_marker)
		player.set("sittable_look_angle", sittable_look_angle)
		player.set("moving_seat", moving_seat)
		player.set("displacement_position", displacement_position)
		player.set("original_position", original_position)
		player.set("original_neck_basis", original_neck_basis)
		player.set("is_ejected", is_ejected)
		player.set("currently_tweening", false)
	
	if standing_collision_shape:
		standing_collision_shape.disabled = true
	if crouching_collision_shape:
		crouching_collision_shape.disabled = true
	
	currently_tweening = false
	
	# Rotate neck to look at marker
	if sittable_look_marker != Vector3.ZERO and neck:
		var rotation_tween_duration: float = 1.0
		if sittable.has_method("get") and sittable.get("rotation_tween_duration") != null:
			rotation_tween_duration = sittable.get("rotation_tween_duration")
		
		var tween = player.create_tween()
		var target_transform = neck.global_transform.looking_at(sittable_look_marker, Vector3.UP)
		tween.tween_property(neck, "global_transform:basis", target_transform.basis, rotation_tween_duration)

## Initiates standing up sequence
func _stand_up() -> void:
	var sittable = CogitoSceneManager._current_sittable_node
	if not sittable:
		# Immediately restore collision and physics, then exit
		_restore_player_state(true)  # true = enable collision shapes
		finished.emit("Grounded")
		return
	
	# Mark that we're exiting to prevent re-entrance
	is_exiting = true
	
	# Kill any active tween (e.g., sit-down tween still running)
	if active_tween and active_tween.is_valid():
		active_tween.kill()
	active_tween = null
	
	# Stop any ongoing tween and mark as not sitting
	# Set player.is_sitting = false EARLY to prevent interaction system from also trying to stand up
	currently_tweening = false
	is_sitting = false
	if player.has_method("set"):
		player.set("is_sitting", false)
	
	# Get the PlayerStateMachine
	var state_machine = get_parent()
	while state_machine and not state_machine is StateMachine:
		state_machine = state_machine.get_parent()
	
	# Lock body rotation to prevent external changes during restoration
	if state_machine and "body_rotation_locked" in state_machine:
		state_machine.body_rotation_locked = true
	
	# Check if this is a physics sittable - these need special handling
	# Method 1: Check if sittable is a RigidBody3D (swing is a RigidBody3D)
	# Method 2: Try to access the physics_sittable property directly
	var physics_sittable: bool = false
	if sittable is RigidBody3D:
		physics_sittable = true
	else:
		# Try direct property access for non-RigidBody physics sittables
		if sittable.get("physics_sittable") == true:
			physics_sittable = true
	
	# For physics sittables (swing, vehicles, etc.):
	# The safest approach is to IMMEDIATELY teleport to original position
	# This avoids all physics conflicts, tween interference, etc.
	if physics_sittable:
		_instant_exit_physics_sittable(sittable)
		return
	
	# For regular sittables: Safe to enable collision and use normal tween flow
	_restore_player_state(true)
	
	# Handle player exit placement based on sittable's placement_on_leave behavior
	var placement_on_leave = 0  # Default to ORIGINAL
	if sittable.has_method("get") and sittable.get("placement_on_leave") != null:
		placement_on_leave = sittable.get("placement_on_leave")
	
	match placement_on_leave:
		0:  # ORIGINAL
			_move_to_original_position(sittable)
		1:  # AUTO
			_move_to_nearby_location(sittable)
		2:  # TRANSFORM
			_move_to_leave_node(sittable)
		3:  # DISPLACEMENT
			_move_to_displacement_position(sittable)
	
	moving_seat = false

## Handles exiting from physics sittables (swing, vehicles, etc.)
## Finds valid ground near the sittable first, only falls back to original_position if needed
func _instant_exit_physics_sittable(sittable: Node) -> void:
	var safe_position: Vector3 = player.global_position
	
	# PRIORITY 1: Try to use the leave node position (if defined on the sittable)
	var leave_node: Node3D = null
	if sittable.has_method("get") and sittable.get("leave_node_path") != null:
		var leave_path = sittable.get("leave_node_path") as NodePath
		if leave_path and not leave_path.is_empty():
			leave_node = sittable.get_node_or_null(leave_path) as Node3D
	
	if leave_node:
		# Leave node exists - find ground below it and validate
		var leave_pos = leave_node.global_position
		var ground_pos = _find_ground_at_position(leave_pos, sittable)
		if ground_pos != Vector3.INF:
			# Check if this position is blocked by a wall
			var validated = _validate_target_position_for_physics(ground_pos, sittable)
			if validated == ground_pos:
				safe_position = ground_pos
	
	# PRIORITY 2: If leave node failed/blocked, try different directions around the chair
	if safe_position == player.global_position:
		var nearby_pos = _find_safe_exit_position_for_physics(sittable)
		if nearby_pos != Vector3.INF:
			safe_position = nearby_pos
	
	# PRIORITY 3: Try ground directly below current position
	if safe_position == player.global_position:
		var ground_below = _find_ground_below_current_position(sittable)
		if ground_below != player.global_position:
			var validated = _validate_target_position_for_physics(ground_below, sittable)
			if validated == ground_below:
				safe_position = ground_below
	
	# PRIORITY 4: Fall back to original_position only as last resort
	if safe_position == player.global_position:
		if original_position != Transform3D():
			safe_position = original_position.origin

	# IMPORTANT: Reset ALL velocity sources to prevent launch effect
	# 1. Reset Motion's static velocity (shared across all movement states)
	Motion.velocity = Vector3.ZERO
	Motion.last_velocity = Vector3.ZERO
	Motion.direction = Vector3.ZERO
	Motion.input_dir = Vector2.ZERO
	
	# 2. Reset player's CharacterBody3D velocity
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
	
	# 3. Reset any vehicle velocity (cogito_vehicle has its own velocity)
	if sittable.has_method("get") and sittable.get("velocity") != null:
		sittable.set("velocity", Vector3.ZERO)
	if sittable.has_method("get") and sittable.get("rotation_momentum") != null:
		sittable.set("rotation_momentum", 0.0)
	
	# Temporarily disable sittable's collision to prevent physics push
	var original_layer: int = 0
	var original_mask: int = 0
	var sittable_collision_disabled = false
	if sittable is CollisionObject3D:
		var col_obj = sittable as CollisionObject3D
		# Store original collision layer/mask
		original_layer = col_obj.collision_layer
		original_mask = col_obj.collision_mask
		# Disable collision temporarily
		col_obj.collision_layer = 0
		col_obj.collision_mask = 0
		sittable_collision_disabled = true
	
	# Teleport player IMMEDIATELY to the safe position
	player.global_position = safe_position
	
	# Reset velocity AGAIN after teleport (belt and suspenders approach)
	Motion.velocity = Vector3.ZERO
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
	
	# Now it's safe to restore physics and collision - player is at valid position
	_restore_player_state(true)
	
	# Re-enable sittable collision after a short delay (let physics settle)
	if sittable_collision_disabled and sittable is CollisionObject3D:
		# Defer re-enabling collision to next physics frame
		_defer_reenable_sittable_collision(sittable, original_layer, original_mask)
	
	# Call sittable's _stand_up() to play animation and update state
	if sittable and sittable.has_method("_stand_up"):
		sittable._stand_up()
	
	# Sync player properties for save/load
	if player.has_method("set"):
		player.set("is_sitting", false)
		player.set("currently_tweening", false)
	
	moving_seat = false
	
	# Record exit time to prevent immediate re-sit from same input
	last_exit_time = Time.get_ticks_msec()
	
	# Exit to Grounded state - directly call state machine to ensure transition happens
	# Using direct method call instead of signal for reliability
	var state_machine = get_parent()
	while state_machine and not state_machine is StateMachine:
		state_machine = state_machine.get_parent()
	
	if state_machine and state_machine.has_method("_change_state"):
		state_machine._change_state("Grounded")
	else:
		# Fallback to signal
		finished.emit("Grounded")

## Finds a safe exit position around a physics sittable by checking multiple directions
## Returns a valid ground position that isn't blocked by walls, or Vector3.INF if none found
func _find_safe_exit_position_for_physics(sittable: Node) -> Vector3:
	if not player:
		return Vector3.INF
	
	var current_pos = player.global_position
	
	# Try 8 directions around the current position at increasing distances
	var directions = [
		Vector3(1, 0, 0),    # Right
		Vector3(-1, 0, 0),   # Left
		Vector3(0, 0, 1),    # Forward
		Vector3(0, 0, -1),   # Back
		Vector3(1, 0, 1).normalized(),   # Front-right
		Vector3(-1, 0, 1).normalized(),  # Front-left
		Vector3(1, 0, -1).normalized(),  # Back-right
		Vector3(-1, 0, -1).normalized(), # Back-left
	]
	
	var distances = [1.0, 1.5, 2.0]  # Try multiple distances
	
	for distance in distances:
		for dir in directions:
			var test_pos = current_pos + dir * distance
			
			# Find ground at this position
			var ground_pos = _find_ground_at_position(test_pos, sittable)
			if ground_pos == Vector3.INF:
				continue
			
			# Validate this position isn't blocked by a wall
			var validated = _validate_target_position_for_physics(ground_pos, sittable)
			if validated == ground_pos:
				# Found a valid position!
				return ground_pos
	
	return Vector3.INF

## Validates a target position for physics sittables - checks if path is blocked by wall
## Returns the target_pos if valid, or player's current position if blocked
func _validate_target_position_for_physics(target_pos: Vector3, sittable: Node) -> Vector3:
	if not player:
		return target_pos
	
	var space_state = player.get_world_3d().direct_space_state
	if not space_state:
		return target_pos
	
	var player_pos = player.global_position
	var distance_to_target = (target_pos - player_pos).length()
	
	# If target is very close, no need to validate
	if distance_to_target < 0.5:
		return target_pos
	
	# Build exclusion list - exclude player AND sittable
	var exclude_list: Array[RID] = [player.get_rid()]
	if sittable and sittable is CollisionObject3D:
		exclude_list.append((sittable as CollisionObject3D).get_rid())
	
	# Cast rays FROM TARGET TO PLAYER to detect walls
	var waist_blocked = false
	var head_blocked = false
	
	# Waist level check (0.8m)
	var waist_query = PhysicsRayQueryParameters3D.create(
		target_pos + Vector3(0, 0.8, 0),
		player_pos + Vector3(0, 0.8, 0)
	)
	waist_query.exclude = exclude_list
	waist_query.collision_mask = 1
	var waist_result = space_state.intersect_ray(waist_query)
	if waist_result:
		waist_blocked = true
	
	# Head level check (1.5m)
	var head_query = PhysicsRayQueryParameters3D.create(
		target_pos + Vector3(0, 1.5, 0),
		player_pos + Vector3(0, 1.5, 0)
	)
	head_query.exclude = exclude_list
	head_query.collision_mask = 1
	var head_result = space_state.intersect_ray(head_query)
	if head_result:
		head_blocked = true
	
	# Only consider it a wall if BOTH waist and head are blocked
	var is_blocked_by_wall = waist_blocked and head_blocked
	
	if not is_blocked_by_wall:
		return target_pos
	
	# Blocked by wall - return player's current position to signal failure
	return player_pos

## Re-enables sittable collision after player has moved away
## Called deferred to let physics settle first
func _defer_reenable_sittable_collision(sittable: Node, orig_layer: int, orig_mask: int) -> void:
	# Use a timer to delay re-enabling collision
	# This gives the player time to move away from the sittable
	var timer = get_tree().create_timer(0.2)  # 200ms delay
	timer.timeout.connect(func():
		if is_instance_valid(sittable) and sittable is CollisionObject3D:
			var col_obj = sittable as CollisionObject3D
			# Restore original collision layer/mask
			col_obj.collision_layer = orig_layer
			col_obj.collision_mask = orig_mask
	)

## Finds valid ground position below the player's current position on a physics sittable
## Used to find a safe landing spot when exiting swings, vehicles, etc.
func _find_ground_below_current_position(sittable: Node) -> Vector3:
	var current_pos = player.global_position
	
	# Build exclusion list - exclude player AND sittable
	var exclude_list: Array[RID] = [player.get_rid()]
	if sittable and sittable is CollisionObject3D:
		exclude_list.append((sittable as CollisionObject3D).get_rid())
	
	var space_state = player.get_world_3d().direct_space_state
	if not space_state:
		# Fallback to original position if we can't raycast
		if original_position != Transform3D():
			return original_position.origin
		return current_pos
	
	# Cast a ray straight down from current position to find the floor
	var ray_origin = current_pos + Vector3(0, 1.0, 0)  # Start above current position
	var ray_end = current_pos + Vector3(0, -20.0, 0)   # Search far down
	
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.exclude = exclude_list
	query.collision_mask = 1
	
	var result = space_state.intersect_ray(query)
	
	if result:
		# Found ground - position player standing on it
		var ground_pos = result.position
		
		# Calculate proper standing height offset from the collision shape
		# The player's origin is at the center of their collision capsule, not at their feet
		var standing_height_offset = 1.0  # Default: assume origin is ~1m above feet
		
		if standing_collision_shape and standing_collision_shape.shape:
			var shape = standing_collision_shape.shape
			if shape is CapsuleShape3D:
				# Capsule: origin is at center, so offset is half the height
				standing_height_offset = (shape as CapsuleShape3D).height / 2.0
			elif shape is BoxShape3D:
				standing_height_offset = (shape as BoxShape3D).size.y / 2.0
			elif shape is CylinderShape3D:
				standing_height_offset = (shape as CylinderShape3D).height / 2.0
			# Add the collision shape's local Y position offset
			standing_height_offset += standing_collision_shape.position.y
		
		# Add small margin to ensure we're definitely above ground
		standing_height_offset += 0.05
		
		return Vector3(current_pos.x, ground_pos.y + standing_height_offset, current_pos.z)
	
	# No ground found directly below - return current position (caller will try other options)
	return current_pos

## Finds valid ground position below a specific position (for leave nodes, etc.)
## Returns Vector3.INF if no valid ground found
func _find_ground_at_position(check_pos: Vector3, sittable: Node) -> Vector3:
	# Build exclusion list - exclude player AND sittable
	var exclude_list: Array[RID] = [player.get_rid()]
	if sittable and sittable is CollisionObject3D:
		exclude_list.append((sittable as CollisionObject3D).get_rid())
	
	var space_state = player.get_world_3d().direct_space_state
	if not space_state:
		return Vector3.INF
	
	# Cast a ray straight down from check position to find the floor
	var ray_origin = check_pos + Vector3(0, 1.0, 0)  # Start above check position
	var ray_end = check_pos + Vector3(0, -20.0, 0)   # Search far down
	
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.exclude = exclude_list
	query.collision_mask = 1
	
	var result = space_state.intersect_ray(query)
	
	if result:
		var ground_pos = result.position
		
		# Calculate proper standing height offset from the collision shape
		var standing_height_offset = 1.0  # Default
		
		if standing_collision_shape and standing_collision_shape.shape:
			var shape = standing_collision_shape.shape
			if shape is CapsuleShape3D:
				standing_height_offset = (shape as CapsuleShape3D).height / 2.0
			elif shape is BoxShape3D:
				standing_height_offset = (shape as BoxShape3D).size.y / 2.0
			elif shape is CylinderShape3D:
				standing_height_offset = (shape as CylinderShape3D).height / 2.0
			standing_height_offset += standing_collision_shape.position.y
		
		# Add small margin to ensure we're definitely above ground
		standing_height_offset += 0.05
		
		# Return position at check_pos X/Z but at proper ground height
		return Vector3(check_pos.x, ground_pos.y + standing_height_offset, check_pos.z)
	
	return Vector3.INF

## Moves player to original position before sitting
func _move_to_original_position(sittable: Node) -> void:
	currently_tweening = true
	var tween_duration: float = 1.0
	if sittable.has_method("get") and sittable.get("tween_duration") != null:
		tween_duration = sittable.get("tween_duration")
	
	# Save target position NOW before the sittable can move/tip
	var target_position = original_position.origin
	
	# Validate target position - check for walls between player and target
	target_position = _validate_target_position(target_position)
	
	var tween = player.create_tween()
	# Only tween position, not rotation - rotation is already restored in _restore_player_state()
	tween.tween_property(player, "global_position", target_position, tween_duration)
	# Don't tween neck - we've already reset it to (0,0,0) in _restore_player_state()
	tween.tween_callback(_stand_up_finished)

## Moves player to leave node position
func _move_to_leave_node(sittable: Node) -> void:
	currently_tweening = true
	var leave_node_path = null
	if sittable.has_method("get") and sittable.get("leave_node_path") != null:
		leave_node_path = sittable.get("leave_node_path")
	
	if leave_node_path:
		var leave_node = sittable.get_node(leave_node_path)
		if leave_node:
			var tween_duration: float = 1.0
			if sittable.has_method("get") and sittable.get("tween_duration") != null:
				tween_duration = sittable.get("tween_duration")
			
			# IMPORTANT: Save the leave node's transform NOW before the sittable can move/tip
			# The leave node is a child of the sittable, so its transform changes if the sittable tips
			var target_position = leave_node.global_position
			
			# For elevated sittables (like swings), the leave marker may be high above the floor.
			# Instead of tweening to the elevated position and then trying to fix it,
			# we use the leave marker's X/Z but the original standing Y position.
			# This ensures the player goes directly to a valid floor-level position.
			if original_position != Transform3D():
				var height_above_original = target_position.y - original_position.origin.y
				if height_above_original > 0.5:
					# Leave marker is significantly above where player was standing
					# Use original Y to avoid placing player in mid-air
					target_position.y = original_position.origin.y
			
			# Validate target position - check for walls between player and target
			target_position = _validate_target_position(target_position)
			
			var tween = player.create_tween()
			# Only tween position, not rotation - rotation is already restored in _restore_player_state()
			tween.tween_property(player, "global_position", target_position, tween_duration)
			# Don't tween neck - we've already reset it to (0,0,0) in _restore_player_state()
			tween.tween_callback(_stand_up_finished)
			return
	
	# Fallback to original position
	_move_to_original_position(sittable)

## Finds nearby location using navmesh
func _move_to_nearby_location(sittable: Node) -> void:
	if not navigation_agent:
		_move_to_leave_node(sittable)
		return
	
	var seat_position = sittable.global_transform.origin
	var exit_distance: float = 1.0
	var max_distance: float = 10.0
	var step_increase: float = 0.5
	var max_attempts: int = 10
	var navmesh_offset_y: float = 0.25
	var attempts: int = 0
	
	while attempts < max_attempts:
		var random_direction = Vector3(
			randf_range(-0.1, 0.1),
			randf_range(-0.1, 0.1),
			randf_range(-0.1, 0.1)
		).normalized()
		
		var candidate_pos = seat_position + (random_direction * exit_distance)
		candidate_pos.y = navmesh_offset_y
		
		navigation_agent.target_position = candidate_pos
		
		if navigation_agent.is_navigation_finished():
			currently_tweening = true
			var tween_duration: float = 1.0
			if sittable.has_method("get") and sittable.get("tween_duration") != null:
				tween_duration = sittable.get("tween_duration")
			
			# Save target position NOW before the sittable can move/tip
			var target_position = navigation_agent.target_position
			target_position.y += 1
			
			# Validate target position - check for walls between player and target
			target_position = _validate_target_position(target_position)
			
			var tween = player.create_tween()
			# Only tween position, not rotation
			tween.tween_property(player, "global_position", target_position, tween_duration)
			# Don't tween neck - we've already reset it to (0,0,0) in _restore_player_state()
			tween.tween_callback(_stand_up_finished)
			return
		else:
			exit_distance += step_increase
			attempts += 1
		
		if exit_distance > max_distance:
			exit_distance = 1
	
	# Fallback to leave node
	_move_to_leave_node(sittable)

## Moves player to displacement position
func _move_to_displacement_position(sittable: Node) -> void:
	currently_tweening = true
	var tween_duration: float = 1.0
	if sittable.has_method("get") and sittable.get("tween_duration") != null:
		tween_duration = sittable.get("tween_duration")
	
	# Save target position NOW before the sittable can move/tip
	var target_position = sittable.global_transform.origin - displacement_position
	
	# For elevated sittables (like swings), ensure we use the original standing Y
	if original_position != Transform3D():
		var height_above_original = target_position.y - original_position.origin.y
		if height_above_original > 0.5:
			target_position.y = original_position.origin.y
	
	# Validate target position - check for walls between player and target
	target_position = _validate_target_position(target_position)
	
	var tween = player.create_tween()
	# Only tween position, not rotation - rotation is already restored in _restore_player_state()
	tween.tween_property(player, "global_position", target_position, tween_duration)
	# Don't tween neck - we've already reset it to (0,0,0) in _restore_player_state()
	tween.tween_callback(_stand_up_finished)

## Called when stand up tween completes
func _stand_up_finished() -> void:
	is_sitting = false
	currently_tweening = false
	
	# Ensure player state is fully restored
	_restore_player_state()
	
	# Get the PlayerStateMachine to unlock body rotation
	var state_machine = get_parent()
	while state_machine and not state_machine is StateMachine:
		state_machine = state_machine.get_parent()
	
	# Re-apply rotations one more time to ensure they're correct
	# We'll unlock in _exit() after the state transition is complete
	var sittable_check = CogitoSceneManager._current_sittable_node
	var physics_sittable_check: bool = false
	if sittable_check and sittable_check.has_method("get") and sittable_check.get("physics_sittable") != null:
		physics_sittable_check = sittable_check.get("physics_sittable")
	
	# STEP 1 & 2: Restore Player and Body rotation
	if physics_sittable_check and sittable_check and original_sittable_basis != Basis():
		# Only use Y rotation (yaw) to keep player upright
		var current_sittable_euler = sittable_check.global_transform.basis.get_euler()
		var original_sittable_euler = original_sittable_basis.get_euler()
		var y_rotation_delta = current_sittable_euler.y - original_sittable_euler.y
		var y_rotation_delta_basis = Basis.from_euler(Vector3(0, y_rotation_delta, 0))
		if original_position != Transform3D():
			player.global_transform.basis = y_rotation_delta_basis * original_position.basis
		if body and original_body_basis != Basis():
			body.global_transform.basis = y_rotation_delta_basis * original_body_basis
	else:
		if original_position != Transform3D():
			player.global_transform.basis = original_position.basis
		if body and original_body_basis != Basis():
			body.global_transform.basis = original_body_basis
	
	# STEP 3: Reset Neck rotation AFTER player and body
	if neck:
		neck.rotation = Vector3.ZERO
	
	# STEP 4: Reset Head rotation
	if head:
		head.rotation = Vector3.ZERO
	
	# Call sittable's _stand_up() to play animation and update state
	var sittable = CogitoSceneManager._current_sittable_node
	if sittable and sittable.has_method("_stand_up"):
		sittable._stand_up()
	
	# Safety check: Ensure player is on valid ground (prevents falling through world)
	# Use a raycast to find the ground below the player
	_ensure_valid_ground_position()
	
	# Sync player properties for save/load
	if player.has_method("set"):
		player.set("is_sitting", false)
		player.set("currently_tweening", false)
	
	# Exit to appropriate parent state
	if player.has_method("is_on_floor") and player.is_on_floor():
		finished.emit("Grounded")
	else:
		finished.emit("Airborne")

## Restores player state after standing up (collision shapes, physics, velocity, etc.)
## enable_collision: If true, re-enables collision shapes AND physics_process. 
## Set to false for physics sittables where the player overlaps with the sittable 
## and needs to move away first (via tween) before physics can safely run.
func _restore_player_state(enable_collision: bool = true) -> void:
	# Only re-enable physics_process when we're also enabling collision
	# Otherwise physics will run without collision shapes → player falls through floor
	if enable_collision:
		if player.has_method("set_physics_process"):
			player.set_physics_process(true)
	
	# IMPORTANT: Rotation restoration order matters!
	# Hierarchy: Player -> Body -> Neck -> Head
	# We must restore from parent to child: Player first, then Body, then Neck, then Head
	
	# Check if this is a physics-based sittable (vehicle, etc.)
	var sittable = CogitoSceneManager._current_sittable_node
	var physics_sittable: bool = false
	if sittable and sittable.has_method("get") and sittable.get("physics_sittable") != null:
		physics_sittable = sittable.get("physics_sittable")
	
	# STEP 1: Restore Player rotation first (affects all children)
	# STEP 2: Restore Body rotation (affects Neck and Head)
	if physics_sittable and sittable and original_sittable_basis != Basis():
		# For physics-based sittables, account for the vehicle's Y rotation change ONLY
		# We only use the Y rotation (yaw) to keep the player upright even if the sittable tipped
		var current_sittable_euler = sittable.global_transform.basis.get_euler()
		var original_sittable_euler = original_sittable_basis.get_euler()
		
		# Calculate only the Y rotation difference (yaw)
		var y_rotation_delta = current_sittable_euler.y - original_sittable_euler.y
		var y_rotation_delta_basis = Basis.from_euler(Vector3(0, y_rotation_delta, 0))
		
		# Apply the Y rotation delta to the original player rotation
		if original_position != Transform3D():
			var adjusted_player_basis = y_rotation_delta_basis * original_position.basis
			player.global_transform.basis = adjusted_player_basis
		
		# Apply the same Y rotation delta to the body
		if body and original_body_basis != Basis():
			var adjusted_body_basis = y_rotation_delta_basis * original_body_basis
			body.global_transform.basis = adjusted_body_basis
		elif body and original_body_local_basis != Basis():
			var adjusted_player_basis = y_rotation_delta_basis * original_position.basis
			var calculated_global = adjusted_player_basis * original_body_local_basis
			body.global_transform.basis = calculated_global
	else:
		# For non-physics sittables, restore the original rotation directly
		# Restore player's global transform basis (rotation) FIRST
		if original_position != Transform3D():
			player.global_transform.basis = original_position.basis
		
		# Then restore Body rotation
		if body:
			if original_body_basis != Basis():
				body.global_transform.basis = original_body_basis
			elif original_body_local_basis != Basis():
				var calculated_global = player.global_transform.basis * original_body_local_basis
				body.global_transform.basis = calculated_global
	
	# STEP 3: Reset Neck rotation AFTER player and body are restored
	# Reset to local (0,0,0) instead of restoring global - we want to face forward
	# The neck is used for looking around while sitting, so its rotation changed
	if neck:
		neck.rotation = Vector3.ZERO
	
	# STEP 4: Reset Head rotation to neutral (looking straight ahead)
	if head:
		head.position.y = 0.0
		head.rotation = Vector3.ZERO
	
	# Reset ALL velocity sources to prevent sliding/stuck/launched movement
	# 1. Reset Motion's static velocity (shared across all movement states)
	Motion.velocity = Vector3.ZERO
	Motion.last_velocity = Vector3.ZERO
	
	# 2. Reset player's CharacterBody3D velocity
	if player is CharacterBody3D:
		var player_body = player as CharacterBody3D
		player_body.velocity = Vector3.ZERO
	
	# Reset static direction variables to prevent direction issues after standing
	Motion.input_dir = Vector2.ZERO
	Motion.direction = Vector3.ZERO
	
	# Re-enable collision shapes if requested
	# For physics sittables, we delay this until after the player has moved away
	# to prevent physics conflicts (player overlapping sittable → pushed through floor)
	if enable_collision:
		_reenable_collision_shapes()

## Resets head rotation to neutral (called deferred after rotation restoration)
func _reset_head_rotation() -> void:
	if head:
		head.rotation = Vector3.ZERO

## Re-enables collision shapes after a frame delay to avoid physics conflicts
func _reenable_collision_shapes() -> void:
	# Re-enable standing collision shape
	if standing_collision_shape:
		standing_collision_shape.disabled = false
	# Disable crouching collision shape
	if crouching_collision_shape:
		crouching_collision_shape.disabled = true

## Validates a target position before tweening to it
## Checks if there's a WALL between the player and the target
## Uses REVERSE raycasting (from target to player) to detect walls even when player is against them
## A wall blocks BOTH waist and head level rays; a platform edge is too short to block these
## If blocked by a wall, finds a safe alternative position nearby
## Returns the validated (or alternative) target position
func _validate_target_position(target_pos: Vector3) -> Vector3:
	if not player:
		return target_pos
	
	var space_state = player.get_world_3d().direct_space_state
	if not space_state:
		return target_pos
	
	var player_pos = player.global_position
	var distance_to_target = (target_pos - player_pos).length()
	
	# If target is very close, no need to validate
	if distance_to_target < 0.5:
		return target_pos
	
	# Build exclusion list - always exclude player, and also exclude the sittable if it's a physics object
	# This prevents raycasts from hitting the sittable's collision shapes (e.g., swing seat)
	var exclude_list: Array[RID] = [player.get_rid()]
	var sittable = CogitoSceneManager._current_sittable_node
	if sittable and sittable is CollisionObject3D:
		exclude_list.append((sittable as CollisionObject3D).get_rid())
	
	# Cast rays FROM TARGET TO PLAYER (reverse direction)
	# This ensures we detect walls even if the player is right against them
	# The ray starts in clear space (at the target) and travels toward the player
	
	var waist_blocked = false
	var head_blocked = false
	
	# Waist level check (0.8m) - from target to player
	var waist_query = PhysicsRayQueryParameters3D.create(
		target_pos + Vector3(0, 0.8, 0),
		player_pos + Vector3(0, 0.8, 0)
	)
	waist_query.exclude = exclude_list
	waist_query.collision_mask = 1
	var waist_result = space_state.intersect_ray(waist_query)
	
	if waist_result:
		# If we hit something, there's an obstacle between target and player
		waist_blocked = true
	
	# Head level check (1.5m) - from target to player
	var head_query = PhysicsRayQueryParameters3D.create(
		target_pos + Vector3(0, 1.5, 0),
		player_pos + Vector3(0, 1.5, 0)
	)
	head_query.exclude = exclude_list
	head_query.collision_mask = 1
	var head_result = space_state.intersect_ray(head_query)
	
	if head_result:
		# If we hit something, there's an obstacle between target and player
		head_blocked = true
	
	# Only consider it a wall if BOTH waist and head are blocked
	# A wall is tall and blocks both; a platform edge (0.25m) won't block rays at 0.8m or 1.5m height
	var is_blocked_by_wall = waist_blocked and head_blocked
	
	if not is_blocked_by_wall:
		# Path is clear (or only blocked by something short like a platform edge)
		return target_pos
	
	# Path is blocked by a wall - find a safe alternative position nearby
	var safe_pos = _find_safe_position()
	if safe_pos != Vector3.ZERO:
		return safe_pos
	
	# No safe position found - stay at current position (don't move through wall)
	return player_pos

## Ensures the player is in a valid position after standing up
## Checks for collisions with world geometry and teleports to safety if needed
## Falls back to original_position if no valid position is found
func _ensure_valid_ground_position() -> void:
	if not player or not player is CharacterBody3D:
		return
	
	var player_body = player as CharacterBody3D
	
	# Build exclusion list - always exclude player, and also exclude the sittable if it's a physics object
	# This prevents raycasts from hitting the sittable's collision shapes (e.g., swing seat)
	var exclude_list: Array[RID] = [player.get_rid()]
	var sittable = CogitoSceneManager._current_sittable_node
	if sittable and sittable is CollisionObject3D:
		exclude_list.append((sittable as CollisionObject3D).get_rid())
	
	# First, check if the player is currently inside geometry using test_move
	# We test a tiny movement to see if we're already colliding
	var test_collision = KinematicCollision3D.new()
	var is_stuck = player_body.test_move(player_body.global_transform, Vector3(0, 0.01, 0), test_collision)
	
	# Also test in multiple directions to detect being inside walls
	if not is_stuck:
		is_stuck = player_body.test_move(player_body.global_transform, Vector3(0.01, 0, 0), test_collision)
	if not is_stuck:
		is_stuck = player_body.test_move(player_body.global_transform, Vector3(0, 0, 0.01), test_collision)
	if not is_stuck:
		is_stuck = player_body.test_move(player_body.global_transform, Vector3(0, -0.01, 0), test_collision)
	
	if is_stuck:
		# Player is inside geometry - try to find a safe position
		var safe_position = _find_safe_position()
		if safe_position != Vector3.ZERO:
			player.global_position = safe_position
		elif original_position != Transform3D():
			# Fallback to original position before sitting
			player.global_position = original_position.origin
		return
	
	# Player is not stuck - but verify they're on solid ground
	var space_state = player.get_world_3d().direct_space_state
	if not space_state:
		return
	
	# Cast a ray downward from the player's feet to find ground
	# Use a short distance first to check for immediate ground
	var ray_origin = player.global_position + Vector3(0, 0.5, 0)
	var ray_end = player.global_position + Vector3(0, -0.5, 0)
	
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.exclude = exclude_list
	query.collision_mask = 1
	
	var result = space_state.intersect_ray(query)
	
	if result:
		var ground_y = result.position.y
		var player_y = player.global_position.y
		
		# Snap to ground if player is BELOW ground (clipping through)
		# Don't snap if player is above ground - that's expected for elevated exits
		if player_y < ground_y:
			# Player is below ground - snap up to valid position
			if original_position != Transform3D():
				player.global_position.y = original_position.origin.y
			else:
				player.global_position.y = ground_y + 0.1
	else:
		# No immediate ground found - try a longer raycast
		ray_end = player.global_position + Vector3(0, -10.0, 0)
		query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
		query.exclude = exclude_list
		query.collision_mask = 1
		result = space_state.intersect_ray(query)
		
		if result:
			# Found ground further down - but this might be below a platform edge
			# Only use this if the drop is reasonable (< 2 meters)
			var drop_distance = player.global_position.y - result.position.y
			if drop_distance < 2.0 and drop_distance > -0.5:
				# For elevated sittables (like swings), the leave position may be high above the floor.
				# Simple ground snapping with a small offset (0.1m) will place the player's ORIGIN
				# just above ground, but their collision shape extends below that, causing clipping.
				# Solution: Use original_position.y if it's valid (player was standing there before sitting)
				if drop_distance > 0.5 and original_position != Transform3D():
					# Elevated exit - use the Y from where the player was standing before sitting
					# This is guaranteed to be a valid standing height
					player.global_position.y = original_position.origin.y
				else:
					# Small drop - safe to snap with small offset
					player.global_position.y = result.position.y + 0.1
			else:
				# Too far to drop - find a safe position NEARBY first
				var safe_pos = _find_safe_position()
				if safe_pos != Vector3.ZERO:
					player.global_position = safe_pos
				else:
					# No safe nearby position - use original position Y as fallback
					if original_position != Transform3D():
						player.global_position.y = original_position.origin.y
					else:
						# Last resort - snap to ground with collision-safe offset
						player.global_position.y = result.position.y + 0.1
		else:
			# No ground found at all - find safe position nearby or use original position
			var safe_pos = _find_safe_position()
			if safe_pos != Vector3.ZERO:
				player.global_position = safe_pos
			elif original_position != Transform3D():
				# Use original position as fallback - guaranteed to be valid
				player.global_position.y = original_position.origin.y
			# If still no safe position, the player will fall - but at least they stay in the area

## Attempts to find a safe position near the player's CURRENT location
## Searches in a circle around the current position at increasing distances
## Does NOT use original_position to avoid teleporting players far away
## Includes line-of-sight check to prevent going through walls
func _find_safe_position() -> Vector3:
	if not player or not player is CharacterBody3D:
		return Vector3.ZERO
	
	var player_body = player as CharacterBody3D
	var test_collision = KinematicCollision3D.new()
	var space_state = player.get_world_3d().direct_space_state
	if not space_state:
		return Vector3.ZERO
	
	# Build exclusion list - always exclude player, and also exclude the sittable if it's a physics object
	# This prevents raycasts from hitting the sittable's collision shapes (e.g., swing seat)
	var exclude_list: Array[RID] = [player.get_rid()]
	var sittable = CogitoSceneManager._current_sittable_node
	if sittable and sittable is CollisionObject3D:
		exclude_list.append((sittable as CollisionObject3D).get_rid())
	
	var player_pos = player.global_position
	
	# Try positions in a circle around the current position
	var directions = [
		Vector3(1, 0, 0),
		Vector3(-1, 0, 0),
		Vector3(0, 0, 1),
		Vector3(0, 0, -1),
		Vector3(0.707, 0, 0.707),
		Vector3(-0.707, 0, 0.707),
		Vector3(0.707, 0, -0.707),
		Vector3(-0.707, 0, -0.707),
	]
	
	# Try at increasing distances (up to 3 meters from current position)
	for distance in [0.5, 1.0, 1.5, 2.0, 2.5, 3.0]:
		for dir in directions:
			var test_pos = player_pos + dir * distance
			
			# IMPORTANT: Check line-of-sight first - make sure there's no wall between player and target
			# Cast a horizontal ray from player to the candidate position
			var los_query = PhysicsRayQueryParameters3D.create(
				player_pos + Vector3(0, 0.5, 0),  # From player's waist height
				test_pos + Vector3(0, 0.5, 0)     # To candidate's waist height
			)
			los_query.exclude = exclude_list
			los_query.collision_mask = 1
			var los_result = space_state.intersect_ray(los_query)
			
			if los_result:
				# There's a wall between player and this position - skip it
				continue
			
			# Line of sight is clear - now check if there's ground at this position
			var ray_query = PhysicsRayQueryParameters3D.create(
				test_pos + Vector3(0, 1.0, 0),
				test_pos + Vector3(0, -1.0, 0)
			)
			ray_query.exclude = exclude_list
			ray_query.collision_mask = 1
			var ground_result = space_state.intersect_ray(ray_query)
			
			if ground_result:
				# Found ground - now check if the position is clear (not inside walls)
				var ground_pos = Vector3(test_pos.x, ground_result.position.y + 0.1, test_pos.z)
				var test_transform = Transform3D(player_body.global_transform.basis, ground_pos)
				
				# Test if this position is free of collisions
				if not player_body.test_move(test_transform, Vector3(0, 0.01, 0), test_collision):
					if not player_body.test_move(test_transform, Vector3(0.01, 0, 0), test_collision):
						if not player_body.test_move(test_transform, Vector3(0, 0, 0.01), test_collision):
							# Valid position with ground, no collisions, and clear line of sight
							return ground_pos
	
	# No safe position found nearby
	return Vector3.ZERO

## Handles mouse look while sitting (constrained by look marker if set)
func _handle_sitting_look(event: InputEventMouseMotion) -> void:
	if not neck or not head or not input_settings:
		return
	
	# Apply mouse input to rotate neck (horizontal look)
	neck.rotate_y(deg_to_rad(-event.relative.x * input_settings.mouse_sens))
	
	# Only apply look marker constraints if a look marker is set and look angle is > 0
	if sittable_look_marker != Vector3.ZERO and sittable_look_angle > 0:
		var neck_position = neck.global_transform.origin
		var look_marker_position = sittable_look_marker
		var target_direction = Vector2(look_marker_position.x - neck_position.x, look_marker_position.z - neck_position.z).normalized()
		
		var neck_forward = neck.global_transform.basis.z
		var neck_direction = Vector2(neck_forward.x, neck_forward.z).normalized()
		var new_angle_to_marker = rad_to_deg(neck_direction.angle_to(target_direction))
		new_angle_to_marker = wrapf(new_angle_to_marker, 0, 360)
		
		# If outside the allowed look angle, undo the rotation
		if not (new_angle_to_marker > 180 - sittable_look_angle and new_angle_to_marker < (180 + sittable_look_angle)):
			neck.rotation.y -= deg_to_rad(-event.relative.x * input_settings.mouse_sens)
	else:
		# No look marker set - allow free horizontal look but clamp to reasonable range
		neck.rotation.y = clamp(neck.rotation.y, deg_to_rad(-120), deg_to_rad(120))
	
	# Vertical look
	if input_settings.invert_y_axis:
		# Inverted: mouse down = look up, mouse up = look down
		head.rotate_x(-deg_to_rad(event.relative.y * input_settings.mouse_sens))
	else:
		# Normal: mouse down = look down, mouse up = look up
		head.rotate_x(deg_to_rad(event.relative.y * input_settings.mouse_sens))
	
	# Clamp vertical look
	var sittable = CogitoSceneManager._current_sittable_node
	var vertical_look_angle: float = 90.0  # Default to 90 degrees
	if sittable and sittable.has_method("get") and sittable.get("vertical_look_angle") != null:
		vertical_look_angle = sittable.get("vertical_look_angle")
	head.rotation.x = clamp(head.rotation.x, deg_to_rad(-vertical_look_angle), deg_to_rad(vertical_look_angle))
