extends Motion

## Ladder state: Player is climbing a ladder.
## Handles ladder movement, sprint on ladder, and jumping off ladder.
## Transitions to Grounded when on floor, or Airborne when jumping off.

## Static variable to track ladder state
static var on_ladder: bool = false
static var ladder_on_cooldown: bool = false

## Reference to ladder collision and direction (set by enter_ladder)
var current_ladder: CollisionShape3D
var ladder_direction: Vector3

## Grace period to prevent immediate exit when entering from ground
var entry_grace_frames: int = 0
const ENTRY_GRACE_FRAME_COUNT: int = 10  # ~0.16 seconds at 60fps

## Flag to track if we're exiting via jump (cooldown should persist) vs walking off (cooldown should clear)
var exiting_via_jump: bool = false

## Entry position - used to detect if player has moved before allowing floor-exit
var entry_position_y: float = 0.0
## Has the player moved significantly on the ladder?
var has_moved_on_ladder: bool = false
const MIN_LADDER_MOVEMENT: float = 0.5  # Must move at least 0.5m before floor-exit is allowed

## Called when entering ladder state
func _enter() -> void:
	on_ladder = true
	# Start grace period to prevent immediate exit when entering from ground
	entry_grace_frames = ENTRY_GRACE_FRAME_COUNT
	# Reset exit flag
	exiting_via_jump = false
	# Track entry position for floor-exit logic
	var player = get_player()
	if player:
		entry_position_y = player.global_position.y
	has_moved_on_ladder = false
	# Note: Don't start cooldown here - it's already started in _do_enter_ladder()
	# Starting it here would create duplicate timers
	super._enter()

## Called when exiting ladder state
func _exit() -> void:
	on_ladder = false
	entry_grace_frames = 0
	
	# Clear cooldown only if we're NOT exiting via jump
	# When jumping off, we want the cooldown to prevent instant re-grab
	# When exiting by walking to floor, we should allow immediate re-entry
	if not exiting_via_jump:
		ladder_on_cooldown = false
	
	# Reset the flag for next time
	exiting_via_jump = false
	super._exit()

## Handles input for jumping off ladder
func _state_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputConstants.INPUT_JUMP):
		_jump_off_ladder()
		return

## Updates ladder movement and checks for exit conditions
func _update(delta: float) -> void:
	if not ladder_handling_stats or not movement_stats:
		return
	
	var nodes: Dictionary = get_player_nodes()
	var body: Node3D = nodes.get("body")
	var camera: Camera3D = nodes.get("head").get_node_or_null("Eyes/Camera") if nodes.get("head") else null
	
	if not body or not camera:
		return
	
	# Decrement grace period counter
	if entry_grace_frames > 0:
		entry_grace_frames -= 1
	
	# Get input direction (use static variable from Motion base class)
	input_dir = Input.get_vector(InputConstants.INPUT_LEFT, InputConstants.INPUT_RIGHT, InputConstants.INPUT_FORWARD, InputConstants.INPUT_BACKWARD)
	
	# Determine ladder speed (normal or sprint)
	var ladder_speed: float = ladder_handling_stats.ladder_speed
	
	if ladder_handling_stats.can_sprint_on_ladder and Input.is_action_pressed(InputConstants.INPUT_SPRINT) and input_dir.length_squared() > 0.1:
		# Check stamina if available
		var player: Node = get_player()
		if player and player.has_method("get") and player.get("stamina_attribute") != null:
			var stamina_attribute = player.get("stamina_attribute")
			if stamina_attribute and stamina_attribute.has_method("get") and stamina_attribute.get("value_current") != null:
				var current_stamina = stamina_attribute.get("value_current")
				if current_stamina > 0:
					ladder_speed = ladder_handling_stats.ladder_sprint_speed
					# Consume stamina
					if player.has_method("decrease_attribute"):
						player.decrease_attribute("stamina", delta * 10.0)  # Adjust drain rate as needed
	
	# Get camera look direction to determine up/down intent
	var look_vector = camera.get_camera_transform().basis
	var looking_down = look_vector.z.dot(Vector3.UP) > 0.5
	
	# Apply ladder movement direction
	var y_dir: float = 1.0 if looking_down else -1.0
	direction = (body.global_transform.basis * Vector3(input_dir.x, input_dir.y * y_dir, 0)).normalized()
	
	# Set velocity for ladder movement
	velocity = direction * ladder_speed
	
	# Apply velocity
	var player_body: CharacterBody3D = owner as CharacterBody3D
	if player_body:
		player_body.velocity = velocity
		player_body.move_and_slide()
		velocity = player_body.velocity
		
		# Track if player has moved enough on the ladder
		if not has_moved_on_ladder:
			var movement_distance = abs(player_body.global_position.y - entry_position_y)
			if movement_distance > MIN_LADDER_MOVEMENT:
				has_moved_on_ladder = true
	
	# Check for exit conditions - but respect grace period, cooldown, and movement requirement
	# Grace period prevents immediate exit when entering from ground
	# Movement requirement ensures player has actually climbed before floor-exit triggers
	# This prevents exiting when entering from the TOP of a ladder (standing on platform)
	if player_body and player_body.is_on_floor() and not ladder_on_cooldown and entry_grace_frames <= 0 and has_moved_on_ladder:
		finished.emit("Grounded")
	
	# Emit direction for animation (if AnimationController exists)
	direction_updated.emit(input_dir)

## Jumps off the ladder
func _jump_off_ladder() -> void:
	if not ladder_handling_stats or not movement_stats:
		return
	
	var nodes: Dictionary = get_player_nodes()
	var camera: Camera3D = nodes.get("head").get_node_or_null("Eyes/Camera") if nodes.get("head") else null
	
	if not camera:
		return
	
	# Apply jump velocity in look direction
	var look_vector = camera.get_camera_transform().basis
	var jump_velocity_scaled: float = movement_stats.jump_velocity * ladder_handling_stats.ladder_jump_scale
	velocity = look_vector * Vector3(jump_velocity_scaled, jump_velocity_scaled, jump_velocity_scaled)
	
	# Mark that we're exiting via jump (cooldown should persist after exit)
	exiting_via_jump = true
	
	# Start cooldown timer
	_start_ladder_cooldown()
	
	# Exit to Airborne
	finished.emit("Airborne")

## Starts ladder cooldown timer to prevent immediate re-entry
func _start_ladder_cooldown() -> void:
	# Always set cooldown to true first (this is the critical part)
	ladder_on_cooldown = true
	
	# Get cooldown duration from stats or use default
	var cooldown_duration: float = 0.5  # Default 0.5 seconds
	if ladder_handling_stats:
		cooldown_duration = ladder_handling_stats.ladder_cooldown
	
	# Create timer if we're in the tree
	if is_inside_tree():
		var cooldown_timer = get_tree().create_timer(cooldown_duration)
		cooldown_timer.timeout.connect(_ladder_cooldown_finished)
	else:
		# Fallback: use call_deferred to reset cooldown after a brief delay
		call_deferred("_ladder_cooldown_finished_deferred")

## Called when ladder cooldown finishes
func _ladder_cooldown_finished() -> void:
	ladder_on_cooldown = false

## Deferred cooldown finish (fallback when timer can't be created)
func _ladder_cooldown_finished_deferred() -> void:
	# Wait a bit before clearing cooldown
	await get_tree().create_timer(0.5).timeout
	ladder_on_cooldown = false

## Called by ladder_area.gd to enter ladder state
## Parameter ladder: The ladder CollisionShape3D
## Parameter ladderDir: The direction vector of the ladder
func enter_ladder(ladder: CollisionShape3D, ladderDir: Vector3) -> void:
	if ladder_on_cooldown:
		return
	
	current_ladder = ladder
	ladder_direction = ladderDir
	
	# Simplified approach: Always allow ladder entry when the player is in the ladder area
	# The player has to physically walk into the ladder area, so they clearly want to climb
	# The cooldown prevents accidental re-entry after jumping off
	_do_enter_ladder(ladder, ladderDir)

## Actually performs the ladder entry (positioning, cooldown, transition)
func _do_enter_ladder(ladder: CollisionShape3D, ladderDir: Vector3) -> void:
	# Position player on ladder
	var offset = (owner.global_position - ladder.global_position)
	if offset.dot(ladderDir) < -0.1:
		owner.global_translate(ladderDir * offset.length() / 4.0)
	
	# Start cooldown BEFORE transition to ensure it's set
	_start_ladder_cooldown()
	
	# Transition to Ladder state
	finished.emit("Ladder")
