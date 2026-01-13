extends Node3D

## Controls character animations, IK systems, and model rotation based on player movement and state.
## Uses a blend tree system similar to NPCs: Movement BlendSpace2D for lower body, UpperBodyState for upper body.
## Synchronizes character model rotation with camera and input direction.
## Note: Weapon spawning is handled by CogitoWieldable system in PlayerInteractionComponent, not here.
class_name AnimationController

## AnimationTree node that contains all animation states and blend trees
@export var animation_tree: AnimationTree

## AnimationPlayer node for direct animation control (used for Push pause/resume)
## Auto-found from animation_tree if not set
@export var animation_player: AnimationPlayer

## Node3D representing the character's armature (skeleton) used for rotation in non-combat mode
@export var armature: Node3D

## Interpolation rate for smoothly rotating the model toward input direction (0.0 to 1.0)
@export var turn_rate: float = 0.1

## SkeletonIK3D node for hip/upper body rotation toward camera
@export var hip_ik: SkeletonIK3D

## SkeletonIK3D node for right hand IK positioning during combat
@export var right_hand_ik: SkeletonIK3D

## SkeletonIK3D node for left hand IK positioning during combat (grip on weapon)
@export var left_hand_ik: SkeletonIK3D

## Node3D target position that the hip IK follows for upper body rotation
@export var hip_target: Node3D

## Skeleton3D node for bone manipulation (auto-found from hip_ik if not set)
@export var skeleton: Skeleton3D

## Character Mesh in case we want to access in other scripts
@export var character_mesh: MeshInstance3D

## Head bone name for scale manipulation
@export var head_bone_name: String = "Head"

## Head scale multiplier for testing (0.0 to hide head, 1.0 for normal scale)
@export var head_scale_multiplier: Vector3 = Vector3.ONE

## Cached head bone ID (set in _ready, -1 if not found)
var head_bone_id: int = -1

## Cached base head scale from bone metadata (defaults to Vector3.ONE)
var base_head_scale: Vector3 = Vector3.ONE

## Current camera rotation from mouse input (x: yaw, y: pitch)
var current_mouse_rotation: Vector2 = Vector2.ZERO

## Smoothed input direction for character movement
var input_dir: Vector2 = Vector2.UP

## Raw input direction (unsmoothed) - used for immediate response in Climb state
## This is updated every frame from the direction_updated signal, so it always reflects current input
var raw_input_dir: Vector2 = Vector2.ZERO

## Reference to the player node (CharacterBody3D) - cached for velocity access
var player: CharacterBody3D

## Reference to player's sprint speed for blend position calculation
var player_sprint_speed: float = 4.0

## Rotation offset in degrees applied to hip target (affects upper body angle)
var hip_rotation_offset: float = -55

## Track last head scale to avoid unnecessary updates
var last_head_scale: Vector3 = Vector3.ONE

## Tracks if Roll OneShot animation is currently active
var roll_oneshot_active: bool = false
## Tracks if Slide OneShot animation is currently active
var slide_oneshot_active: bool = false
## Tracks frames since entering Climb state (to allow Enter animation to complete)
var climb_enter_frames: int = 0
const CLIMB_ENTER_FRAME_DELAY: int = 10  # Wait ~10 frames (~0.16s at 60fps) before forcing to Idle
## Tracks if Interact OneShot animation is currently active
var interact_oneshot_active: bool = false
## Tracks last frame's interact input state to detect presses
var was_interact_pressed: bool = false

func _ready() -> void:
	if hip_ik:
		hip_ik.start()
	if right_hand_ik:
		right_hand_ik.start()
	if left_hand_ik:
		left_hand_ik.start()
	if hip_ik:
		hip_ik.influence = 0
	if right_hand_ik:
		right_hand_ik.influence = 0
	if left_hand_ik:
		left_hand_ik.influence = 0
	
	# Auto-find skeleton from hip_ik if not set
	if not skeleton and hip_ik:
		skeleton = hip_ik.get_parent() as Skeleton3D
		if not skeleton:
			push_warning("AnimationController: Could not find Skeleton3D from hip_ik")
	
	# Auto-find AnimationPlayer from animation_tree if not set
	if not animation_player and animation_tree:
		animation_player = animation_tree.get_parent() as AnimationPlayer
		if not animation_player:
			# Try to find it as a sibling or child
			var parent = animation_tree.get_parent()
			if parent:
				animation_player = parent.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if not animation_player:
			push_warning("AnimationController: Could not find AnimationPlayer for Push pause/resume")
	
	# Cache head bone ID and base scale
	_cache_head_bone_info()
	
	# Find and cache player node for velocity access
	_cache_player_node()
	
	# Connect to player's wieldable system for future animation support
	_connect_to_wieldable_system()
	
	# Connect to player's interaction component for interact animations
	_connect_to_interaction_system()

## Caches the player node reference for velocity access
func _cache_player_node() -> void:
	var search_node: Node = get_parent()
	var search_depth = 0
	const MAX_SEARCH_DEPTH = 10
	
	# Search up the tree for CharacterBody3D (CogitoPlayer)
	while search_node and search_depth < MAX_SEARCH_DEPTH:
		if search_node is CharacterBody3D:
			player = search_node
			# Try to get sprint speed from player resources if available
			if player.has_method("get") and player.get("player_resources") != null:
				var player_resources = player.get("player_resources")
				if player_resources and player_resources.has_method("get"):
					var movement_stats = player_resources.get("movement_stats")
					if movement_stats and movement_stats.has_method("get"):
						var sprint_speed = movement_stats.get("sprinting_speed")
						if sprint_speed != null:
							player_sprint_speed = sprint_speed
			break
		search_node = search_node.get_parent()
		search_depth += 1
	
	if not player:
		push_warning("AnimationController: Could not find CharacterBody3D player node")

## Helper function to safely get an AnimationTree parameter
## Returns the parameter value if it exists, or null if it doesn't
func _get_animation_parameter(param_path: String):
	if not animation_tree:
		return null
	# Access the parameter directly using bracket notation
	# If the parameter doesn't exist, this will return null
	return animation_tree.get(param_path)

## Helper function to safely set an AnimationTree parameter
## Returns true if successful, false if parameter doesn't exist
func _set_animation_parameter(param_path: String, value) -> bool:
	if not animation_tree:
		return false
	# Set the parameter directly - AnimationTree will handle it
	# If the parameter doesn't exist, it will silently fail but won't crash
	animation_tree[param_path] = value
	return true

## Updates animation blend position based on player velocity (called every frame from Motion states)
## Similar to NPC's update_animations() - calculates relative velocity and updates Movement BlendSpace2D
## Also updates Crouch BlendSpace2D if in crouch state
## This should be called from Motion states' _update() methods
## Helper: Calculates relative velocity in player's local space for BlendSpace2D
## Returns: Vector2 with x (left/right) and y (forward/back) for BlendSpace2D
func _calculate_relative_velocity() -> Vector2:
	if not player:
		return Vector2.ZERO
	
	# Get horizontal velocity (x/z only, ignore y/vertical)
	var horizontal_velocity = player.velocity * Vector3(1, 0, 1)
	# Normalize by sprint speed to get 0-1 range
	var relative_velocity = player.global_basis.inverse() * (horizontal_velocity / player_sprint_speed)
	# Convert to Vector2 for BlendSpace2D (x: left/right, y: forward/back)
	# Invert Z to match BlendSpace2D coordinate system (forward is negative Y)
	return Vector2(relative_velocity.x, -relative_velocity.z)

## Helper: Gets the current player state name
func _get_current_player_state() -> String:
	if not player:
		return ""
	var state_machine = player.get_node_or_null("StateMachine")
	if state_machine and state_machine.current_state:
		return state_machine.current_state.name
	return ""

## Helper: Updates Movement BlendSpace2D blend position
## Parameter rel_velocity_xz: Relative velocity Vector2 for blend position
## Parameter skip_states: Array of state names to skip Movement updates for
func _update_movement_blendspace(rel_velocity_xz: Vector2, skip_states: Array = []) -> void:
	var current_state = _get_current_player_state()
	if current_state in skip_states:
		return
	
	# Calculate blend position based on state
	var blend_pos: Vector2 = Vector2.ZERO
	
	if rel_velocity_xz.length_squared() > 0:
		# Normalize to get direction (preserves sign for forward/backward and left/right)
		var direction = rel_velocity_xz.normalized()
		
		# Set blend position based on state
		# BlendSpace2D expects: Idle at (0,0), Walk at (0,0.5), Sprint at (0,1.0)
		# For diagonal movement, scale both X and Y components
		match current_state:
			"Walk":
				# Walk state: scale direction to 0.5 range
				# This allows blending between walk animations at different directions
				blend_pos.x = direction.x * 0.5
				blend_pos.y = direction.y * 0.5
			"Sprint":
				# Sprint state: scale direction to 1.0 range
				# This allows blending between sprint animations at different directions
				blend_pos.x = direction.x * 1.0
				blend_pos.y = direction.y * 1.0
			"Idle":
				# Idle state: set to (0, 0)
				blend_pos = Vector2.ZERO
			_:
				# For other states, use normalized direction (falls back to 0-1 range)
				blend_pos = direction
	else:
		# No movement: set to Idle position (0, 0)
		blend_pos = Vector2.ZERO
	
	_set_animation_parameter("parameters/Movement/blend_position", blend_pos)

## Helper: Forces a StateMachine to stay in Idle state
## Parameter state_machine_path: Path to the StateMachine playback (e.g., "parameters/Crouch/playback")
## Parameter force_unconditionally: If true, always call travel("Idle") even if already in Idle
## Parameter allow_enter_to_complete: If true, don't force to Idle if currently in Enter state (let Enter complete first)
func _maintain_state_machine_idle(state_machine_path: String, force_unconditionally: bool = false, allow_enter_to_complete: bool = false) -> void:
	var state_machine = _get_animation_parameter(state_machine_path)
	if not state_machine:
		return
	
	if force_unconditionally:
		# Always force to Idle (for Sit state)
		state_machine.travel("Idle")
	else:
		# Only force if not already in Idle
		var current_sub_state = _get_animation_parameter(state_machine_path.replace("/playback", "/current_state"))
		if allow_enter_to_complete and current_sub_state == "Enter":
			# Let Enter animation complete first - don't force to Idle yet
			return
		elif current_sub_state != "Idle":
			state_machine.travel("Idle")

## Helper: Updates a BlendSpace2D inside a StateMachine state
## Parameter blendspace_path: Path to the BlendSpace2D blend_position (e.g., "parameters/Crouch/Idle/blend_position")
## Parameter rel_velocity_xz: Relative velocity Vector2 for blend position (can be Vector2.ZERO for Idle)
func _update_blendspace_in_state(blendspace_path: String, rel_velocity_xz: Vector2) -> void:
	# Always set the blend position, even if it's Vector2.ZERO (for Idle states)
	# This ensures we properly reset to Idle when input stops
	_set_animation_parameter(blendspace_path, rel_velocity_xz)

## Helper: Calculates climb BlendSpace2D position from input direction
## Maps input direction (WASD) to BlendSpace2D coordinates:
## - Forward (W, y=-1) → Up (0, 1) [Y axis is inverted]
## - Backward (S, y=1) → Down (0, -1) [Y axis is inverted]
## - Left (A, x=-1) → Left (-1, 0)
## - Right (D, x=1) → Right (1, 0)
## - No input → Idle (0, 0)
## Note: Input.get_vector() returns negative Y for forward (W), but BlendSpace2D expects positive Y for Up
## Parameter input_direction: Input direction Vector2 from ladder/ledge state (x: left/right, y: forward/backward)
## Returns: Vector2 for BlendSpace2D blend_position
func _calculate_climb_blend_position(input_direction: Vector2) -> Vector2:
	# Use a more robust threshold to detect no input
	# Input.get_vector() can return very small values near zero, so we use 0.1 threshold
	# Check individual components to handle cases where one axis is zero
	var abs_x = abs(input_direction.x)
	var abs_y = abs(input_direction.y)
	
	if abs_x < 0.1 and abs_y < 0.1:
		# No input on either axis - return Idle position (0, 0)
		return Vector2.ZERO
	
	# For ladder climbing, we want to handle each axis independently
	# If input is diagonal, we allow it to blend (e.g., Up-Left would be between Up and Left)
	var blend_pos = Vector2.ZERO
	
	# Map x-axis (left/right) directly - Input.get_vector() already gives -1 to 1
	# A (left) → -1, D (right) → 1
	if abs_x >= 0.1:
		blend_pos.x = clamp(input_direction.x, -1.0, 1.0)
	
	# Map y-axis (forward/backward) - CRITICAL: Invert Y axis!
	# Input.get_vector() returns: W (forward) → -1, S (backward) → 1
	# BlendSpace2D expects: Up → 1, Down → -1
	# So we need to INVERT: forward (W, y=-1) → Up (y=1), backward (S, y=1) → Down (y=-1)
	if abs_y >= 0.1:
		blend_pos.y = clamp(-input_direction.y, -1.0, 1.0)  # Invert Y axis
	
	return blend_pos

## Helper: Maintains blend amount and StateMachine Idle for states without BlendSpace2D
## Parameter blend_param: Path to the blend parameter (e.g., "parameters/PushBlend/blend_amount")
## Parameter state_machine_path: Path to the StateMachine playback
func _maintain_blend_with_state_machine(blend_param: String, state_machine_path: String) -> void:
	_set_animation_parameter(blend_param, 1.0)
	_maintain_state_machine_idle(state_machine_path, false)

## Helper: Maintains blend amount, StateMachine Idle, and BlendSpace2D for states with movement
## Parameter blend_param: Path to the blend parameter (e.g., "parameters/CrouchBlend/blend_amount")
## Parameter state_machine_path: Path to the StateMachine playback
## Parameter blendspace_path: Path to the BlendSpace2D blend_position
## Parameter rel_velocity_xz: Relative velocity Vector2 for blend position
func _maintain_blend_with_blendspace(
	blend_param: String,
	state_machine_path: String,
	blendspace_path: String,
	rel_velocity_xz: Vector2
) -> void:
	_set_animation_parameter(blend_param, 1.0)
	_maintain_state_machine_idle(state_machine_path, false)
	_update_blendspace_in_state(blendspace_path, rel_velocity_xz)

## Helper: Special case for Sit state - maintains blend and StateMachine
## Only forces to Idle if not in Enter state (allows Enter animation to complete)
## Tracks previous Sit sub-state to detect Enter → Idle transition
var previous_sit_sub_state: String = ""

func _maintain_sit_state() -> void:
	# Force SitBlend to 1.0 multiple times to ensure it sticks
	_set_animation_parameter("parameters/SitBlend/blend_amount", 1.0)
	
	# Set all other blends to 0.0 to ensure Sit shows through
	_set_animation_parameter("parameters/ClimbBlend/blend_amount", 0.0)
	_set_animation_parameter("parameters/PushBlend/blend_amount", 0.0)
	_set_animation_parameter("parameters/CrouchBlend/blend_amount", 0.0)
	_set_animation_parameter("parameters/FloatBlend/blend_amount", 0.0)
	_set_animation_parameter("parameters/JumpBlend/blend_amount", 0.0)
	
	# Set SitBlend again after other blends
	_set_animation_parameter("parameters/SitBlend/blend_amount", 1.0)
	
	# Check current Sit StateMachine state
	var sit_state_machine = _get_animation_parameter("parameters/Sit/playback")
	if sit_state_machine:
		var current_sit_state = _get_animation_parameter("parameters/Sit/current_state")
		
		# If we're in Enter state, the AnimationTree should auto-transition to Idle when Enter completes
		# We don't need to manually check OneShot completion - the transition handles it
		# The transition from Enter to Idle is configured in the AnimationTree
		
		# Detect transition from Enter to Idle - select random idle animation
		if previous_sit_sub_state == "Enter" and current_sit_state == "Idle":
			# Just transitioned from Enter to Idle - select random idle animation
			_select_random_sit_idle()
		
		# Only force to Idle if we're not in Enter (let Enter animation complete)
		if current_sit_state != "Enter" and current_sit_state != "Idle":
			# Force to Idle if in Exit or other states
			sit_state_machine.travel("Idle")
		# If already in Idle, don't call travel() - let AnimationTree handle it naturally
		
		# Update previous state for next frame
		previous_sit_sub_state = current_sit_state
	
	# Triple-check SitBlend is still 1.0
	_set_animation_parameter("parameters/SitBlend/blend_amount", 1.0)

func update_animations(_delta: float) -> void:
	if not animation_tree or not player:
		return
	
	# Calculate relative velocity once for all states
	var rel_velocity_xz = _calculate_relative_velocity()
	var current_state = _get_current_player_state()
	
	# Update Movement BlendSpace2D (skip Sit state)
	_update_movement_blendspace(rel_velocity_xz, ["Sit"])
	
	# Handle state-specific animation updates
	match current_state:
		"Crouch":
			_maintain_blend_with_blendspace(
				"parameters/CrouchBlend/blend_amount",
				"parameters/Crouch/playback",
				"parameters/Crouch/Idle/blend_position",
				rel_velocity_xz
			)
		
		"Push":
			_maintain_blend_with_state_machine(
				"parameters/PushBlend/blend_amount",
				"parameters/Push/playback"
			)
		
		"Ladder", "Ledge":
			_set_animation_parameter("parameters/ClimbBlend/blend_amount", 1.0)
			# Get the Climb StateMachine playback
			var climb_sm = _get_animation_parameter("parameters/Climb/playback")
			if not climb_sm:
				return
			
			# Increment frame counter (used to delay forcing to Idle to allow Enter animation)
			climb_enter_frames += 1
			
			# CRITICAL: Since current_climb_state parameter is always null (not accessible),
			# we can't check the actual state. Instead, wait a few frames for Enter to play,
			# then force to Idle so we can access the BlendSpace2D
			if climb_enter_frames >= CLIMB_ENTER_FRAME_DELAY:
				# Enter animation should have started - force to Idle to access BlendSpace2D
				# The BlendSpace2D is the "Idle" state node, so we must be in Idle to update it
				climb_sm.travel("Idle")
			
			# Always try to update BlendSpace2D based on raw_input_dir from the ladder state signal
			# raw_input_dir is updated every frame by on_character_input_direction_changed()
			# from the direction_updated signal emitted by ladder.gd line 132
			# This will be (0, 0) when no input, and will have values when WASD is pressed
			# Note: This might fail silently if StateMachine isn't in Idle yet, which is fine
			var climb_blend_pos = _calculate_climb_blend_position(raw_input_dir)
			_update_blendspace_in_state("parameters/Climb/Idle/blend_position", climb_blend_pos)
		
		"Sit":
			_maintain_sit_state()
		
		"Roll":
			# CRITICAL: Ensure Roll OneShot is active when in Roll state
			# The OneShot should already be triggered in on_state_machine_state_change(),
			# but we check here as a backup to ensure it's set if we somehow missed it
			if not roll_oneshot_active:
				# This should not happen if on_state_machine_state_change() is called correctly,
				# but handle it as a safety net
				roll_oneshot_active = true
				slide_oneshot_active = false
				if animation_tree:
					_set_animation_parameter("parameters/RollSlideBlend/blend_amount", 0.0)  # Show RollOneShot
					var param_path = "parameters/RollOneShot/OneShot/request"
					var test_value = animation_tree.get(param_path)
					if test_value != null:
						# Reset and fire OneShot immediately (no delays)
						animation_tree.set(param_path, AnimationNodeOneShot.ONE_SHOT_REQUEST_NONE)
						animation_tree.set(param_path, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
						animation_tree.advance(0.0)  # Force immediate processing
		
		"Slide":
			# CRITICAL: Ensure Slide OneShot is active when in Slide state
			# The OneShot should already be triggered in on_state_machine_state_change(),
			# but we check here as a backup to ensure it's set if we somehow missed it
			if not slide_oneshot_active:
				# This should not happen if on_state_machine_state_change() is called correctly,
				# but handle it as a safety net
				slide_oneshot_active = true
				roll_oneshot_active = false
				if animation_tree:
					_set_animation_parameter("parameters/RollSlideBlend/blend_amount", 1.0)  # Show SlideOneShot
					var param_path = "parameters/SlideOneShot/OneShot/request"
					var test_value = animation_tree.get(param_path)
					if test_value != null:
						# Reset and fire OneShot immediately (no delays)
						animation_tree.set(param_path, AnimationNodeOneShot.ONE_SHOT_REQUEST_NONE)
						animation_tree.set(param_path, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
						animation_tree.advance(0.0)  # Force immediate processing
		
		"AirControl":
			_set_animation_parameter("parameters/FloatBlend/blend_amount", 1.0)

## Updates Float animation blend based on movement direction
## Called from Float state to blend between Swim_Idle and Swim_Fwd
## Parameter movement_direction: Normalized Vector2 direction (forward = positive Y, backward = negative Y)
func update_float_animations(movement_direction: Vector2) -> void:
	if not animation_tree:
		return
	
	# Calculate blend amount: 0.0 = Swim_Idle (not moving), 1.0 = Swim_Fwd (moving)
	var movement_magnitude = movement_direction.length()
	var blend_amount = clamp(movement_magnitude, 0.0, 1.0)
	
	# Set Float blend amount (0.0 = Swim_Idle, 1.0 = Swim_Fwd)
	_set_animation_parameter("parameters/Float/Blend/blend_amount", blend_amount)
	
	# Note: For backward movement, we could reverse the Swim_Fwd animation by setting time_scale
	# However, AnimationTree doesn't directly support time_scale on individual animation nodes
	# To support backward movement, you could:
	# 1. Create a separate Swim_Bwd animation and blend between Swim_Fwd and Swim_Bwd
	# 2. Use AnimationPlayer's time_scale property (requires direct access to the animation)
	# 3. Use a BlendSpace1D with forward/backward positions
	# For now, Swim_Fwd will play normally for all movement directions

## Sets the upper body animation state (Neutral, PistolReady, RaisedFists, etc.)
## Similar to NPC's set_upper_body_state() - uses travel() on the UpperBodyState state machine
## Also sets UpperBodyBlend to 1.0 to show the UpperBodyState instead of SitBlend
## Parameter state_name: The name of the upper body state to transition to
func set_upper_body_state(state_name: String) -> void:
	if not animation_tree:
		return
	
	var upper_body_state_machine = _get_animation_parameter("parameters/UpperBodyState/playback")
	if upper_body_state_machine:
		# CRITICAL: Set UpperBodyBlend to 1.0 FIRST to show Transition/UpperBodyState (input 1) instead of SitBlend (input 0)
		# UpperBodyBlend blends between SitBlend (0) and Transition (1), where Transition shows UpperBodyState (input 0) by default
		_set_animation_parameter("parameters/UpperBodyBlend/blend_amount", 1.0)
		# Transition to the requested upper body state (e.g., "PistolReady" or "Neutral")
		upper_body_state_machine.travel(state_name)

## Tracks the previous state to detect transitions (e.g., Crouch → Stand should trigger Crouch Exit)
var previous_state: String = ""

## Helper: Gets the actual current state from the player's state machine
## Used to verify state when timing issues might cause incorrect state parameter
func _get_actual_current_state() -> String:
	if player:
		var state_machine = player.get_node_or_null("StateMachine")
		if state_machine and state_machine.current_state:
			return state_machine.current_state.name
	return ""

## Helper: Triggers a OneShot animation in the AnimationTree
## Parameter param_path: Full path to the OneShot request parameter (e.g., "parameters/Sit/Enter/OneShot/request")
func _trigger_oneshot(param_path: String) -> void:
	if not animation_tree:
		return
	var test_value = animation_tree.get(param_path)
	if test_value != null:
		animation_tree.set(param_path, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

## Helper: Handles Climb state specifically (allows Enter animation to complete, uses input direction)
## Parameter is_entering: Whether we're entering Climb state
## Parameter is_exiting: Whether we're exiting Climb state
func _handle_climb_state(is_entering: bool, is_exiting: bool) -> void:
	var climb_state_machine = _get_animation_parameter("parameters/Climb/playback")
	if not climb_state_machine:
		return
	
	if is_entering:
		# Reset raw_input_dir when entering Climb state to ensure clean state
		# It will be updated by the direction_updated signal from ladder state every frame
		raw_input_dir = Vector2.ZERO
		# Reset frame counter to allow Enter animation to play
		climb_enter_frames = 0
		
		# Entering Climb: transition to Enter first (let it play)
		climb_state_machine.travel("Enter")
		_trigger_oneshot("parameters/Climb/Enter/OneShot/request")
		
		# Set blend to 1.0 (show Climb animations)
		_set_animation_parameter("parameters/ClimbBlend/blend_amount", 1.0)
	
	elif is_exiting:
		# Exiting Climb: transition to Exit
		climb_state_machine.travel("Exit")
		_trigger_oneshot("parameters/Climb/Exit/OneShot/request")
		
		# Set blend to 0.0 (show Movement instead)
		_set_animation_parameter("parameters/ClimbBlend/blend_amount", 0.0)
		# Reset frame counter
		climb_enter_frames = 0
	
	else:
		# Not entering or exiting - check if we're actually in Climb
		var actual_state = _get_actual_current_state()
		if actual_state != "Ladder" and actual_state != "Ledge":
			# Not in Climb - ensure blend is 0
			_set_animation_parameter("parameters/ClimbBlend/blend_amount", 0.0)

## Helper: Handles Sit state specifically (allows Enter animation to complete)
## Parameter is_entering: Whether we're entering Sit state
## Parameter is_exiting: Whether we're exiting Sit state
## Parameter target_state: The state we're transitioning to (for exit detection)
func _handle_sit_state(is_entering: bool, is_exiting: bool, target_state: String) -> void:
	var sit_state_machine = _get_animation_parameter("parameters/Sit/playback")
	if not sit_state_machine:
		return
	
	var current_sit_state = _get_animation_parameter("parameters/Sit/current_state")
	
	if is_entering:
		# Entering Sit: transition to Enter if not already in Enter or Idle
		if current_sit_state != "Enter" and current_sit_state != "Idle":
			sit_state_machine.travel("Enter")
			_trigger_oneshot("parameters/Sit/Enter/OneShot/request")
		# If already in Enter, let it complete (don't force to Idle)
		# If already in Idle, select random idle animation
		elif current_sit_state == "Idle":
			# Already in Idle - select random idle animation if not already set
			_select_random_sit_idle()
		
		# Set blend to 1.0 (show Sit animations)
		_set_animation_parameter("parameters/SitBlend/blend_amount", 1.0)
		_set_animation_parameter("parameters/SitBlend/blend_amount", 1.0)  # Set twice for Sit
	
	elif is_exiting:
		# Only trigger Exit if transitioning to Stand state
		if target_state == "Stand":
			if current_sit_state == "Idle" or current_sit_state == "Enter":
				sit_state_machine.travel("Exit")
				_trigger_oneshot("parameters/Sit/Exit/OneShot/request")
		
		# Set blend to 0.0 (show Movement instead)
		_set_animation_parameter("parameters/SitBlend/blend_amount", 0.0)
	
	else:
		# Not entering or exiting - check if we're actually in Sit
		var actual_state = _get_actual_current_state()
		if actual_state != "Sit":
			# Not in Sit - ensure blend is 0
			_set_animation_parameter("parameters/SitBlend/blend_amount", 0.0)

## Helper: Handles StateMachine-based animation states (Enter → Idle → Exit pattern)
## Parameter state_machine_path: Path to the StateMachine playback (e.g., "parameters/Crouch/playback")
## Parameter blend_param: Path to the blend parameter (e.g., "parameters/CrouchBlend/blend_amount")
## Parameter is_entering: Whether we're entering this state
## Parameter is_exiting: Whether we're exiting this state
func _handle_state_machine_blend(
	state_machine_path: String,
	blend_param: String,
	is_entering: bool,
	is_exiting: bool
) -> void:
	var state_machine = _get_animation_parameter(state_machine_path)
	if not state_machine:
		return
	
	var current_sub_state = _get_animation_parameter(state_machine_path.replace("/playback", "/current_state"))
	
	if is_entering:
		# Entering state: transition to Enter if needed, then ensure Idle
		if current_sub_state != "Enter" and current_sub_state != "Idle":
			state_machine.travel("Enter")
			_trigger_oneshot(state_machine_path.replace("/playback", "/Enter/OneShot/request"))
		elif current_sub_state == "Enter":
			# Force to Idle if still in Enter
			state_machine.travel("Idle")
		else:
			# Already in Idle or other state - force to Idle
			state_machine.travel("Idle")
		
		# Set blend to 1.0 (show this state's animations)
		_set_animation_parameter(blend_param, 1.0)
	
	elif is_exiting:
		# Exiting state: transition to Exit if in Idle or Enter
		if current_sub_state == "Idle" or current_sub_state == "Enter":
			state_machine.travel("Exit")
			_trigger_oneshot(state_machine_path.replace("/playback", "/Exit/OneShot/request"))
		
		# Set blend to 0.0 (show Movement instead)
		_set_animation_parameter(blend_param, 0.0)
	
	else:
		# Not entering or exiting - ensure blend is 0
		_set_animation_parameter(blend_param, 0.0)

## Called by PlayerStateMachine when motion state changes (Idle, Walk, Sprint, Jump, etc.)
## With the blend tree system, we don't need to manually trigger transitions for movement states
## as the Movement BlendSpace2D automatically blends based on velocity via update_animations()
## This function handles special states like Sit, Jump, Float, etc. that need manual animation control
## Parameter state: The name of the state (e.g., "Idle", "Walk", "Sprint", "Jump", "Crouch", "Sit", "Float", "Fall")
func on_state_machine_state_change(state: String) -> void:
	if not animation_tree:
		return
	
	# CRITICAL: Handle Roll state FIRST, immediately when entering (before any other state logic)
	# This must happen as soon as possible to match the AnimationPlayer timing in roll.gd _enter()
	if state == "Roll":
		roll_oneshot_active = true
		slide_oneshot_active = false
		# CRITICAL: Set blend amounts FIRST to show RollOneShot through the blend chain
		_set_animation_parameter("parameters/JumpBlend/blend_amount", 0.0)  # Show MovementRollSlideBlend (input 0), not Jump (input 1)
		_set_animation_parameter("parameters/FloatBlend/blend_amount", 0.0)  # Show JumpBlend (input 0), not Float (input 1)
		_set_animation_parameter("parameters/CrouchBlend/blend_amount", 0.0)  # Show FloatBlend (input 0), not Crouch (input 1)
		_set_animation_parameter("parameters/PushBlend/blend_amount", 0.0)  # Show CrouchBlend (input 0), not Push (input 1)
		_set_animation_parameter("parameters/ClimbBlend/blend_amount", 0.0)  # Show PushBlend (input 0), not Climb (input 1)
		_set_animation_parameter("parameters/SitBlend/blend_amount", 0.0)  # Show ClimbBlend (input 0), not Sit (input 1)
		
		# CRITICAL: Set RollSlideBlend to 0.0 to show RollOneShot (input 0), not SlideOneShot (input 1)
		_set_animation_parameter("parameters/RollSlideBlend/blend_amount", 0.0)
		# CRITICAL: Set MovementRollSlideBlend to 1.0 to show RollSlideBlend (input 1), not Movement (input 0)
		_set_animation_parameter("parameters/MovementRollSlideBlend/blend_amount", 1.0)
		
		# Trigger RollOneShot IMMEDIATELY - no delays, no deferred calls
		var param_path = "parameters/RollOneShot/OneShot/request"
		var test_value = animation_tree.get(param_path)
		if test_value != null:
			# Reset OneShot first to ensure it can fire (critical for repeat triggers)
			animation_tree.set(param_path, AnimationNodeOneShot.ONE_SHOT_REQUEST_NONE)
			# Fire OneShot immediately - no deferred, no waiting
			animation_tree.set(param_path, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		else:
			# Parameter doesn't exist - this shouldn't happen but handle gracefully
			push_warning("AnimationController: RollOneShot/OneShot/request parameter not found for Roll animation")
	elif state == "Slide":
		slide_oneshot_active = true
		roll_oneshot_active = false
		# CRITICAL: Set blend amounts FIRST to show SlideOneShot through the blend chain
		_set_animation_parameter("parameters/JumpBlend/blend_amount", 0.0)  # Show MovementRollSlideBlend (input 0), not Jump (input 1)
		_set_animation_parameter("parameters/FloatBlend/blend_amount", 0.0)  # Show JumpBlend (input 0), not Float (input 1)
		_set_animation_parameter("parameters/CrouchBlend/blend_amount", 0.0)  # Show FloatBlend (input 0), not Crouch (input 1)
		_set_animation_parameter("parameters/PushBlend/blend_amount", 0.0)  # Show CrouchBlend (input 0), not Push (input 1)
		_set_animation_parameter("parameters/ClimbBlend/blend_amount", 0.0)  # Show PushBlend (input 0), not Climb (input 1)
		_set_animation_parameter("parameters/SitBlend/blend_amount", 0.0)  # Show ClimbBlend (input 0), not Sit (input 1)
		
		# CRITICAL: Set RollSlideBlend to 1.0 to show SlideOneShot (input 1), not RollOneShot (input 0)
		_set_animation_parameter("parameters/RollSlideBlend/blend_amount", 1.0)
		# CRITICAL: Set MovementRollSlideBlend to 1.0 to show RollSlideBlend (input 1), not Movement (input 0)
		_set_animation_parameter("parameters/MovementRollSlideBlend/blend_amount", 1.0)
		
		# Trigger SlideOneShot IMMEDIATELY - no delays, no deferred calls
		var param_path = "parameters/SlideOneShot/OneShot/request"
		var test_value = animation_tree.get(param_path)
		if test_value != null:
			# Reset OneShot first to ensure it can fire (critical for repeat triggers)
			animation_tree.set(param_path, AnimationNodeOneShot.ONE_SHOT_REQUEST_NONE)
			# Fire OneShot immediately - no deferred, no waiting
			animation_tree.set(param_path, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		else:
			# Parameter doesn't exist - this shouldn't happen but handle gracefully
			push_warning("AnimationController: SlideOneShot/OneShot/request parameter not found for Slide animation")
	elif previous_state == "Roll" and state != "Roll":
		roll_oneshot_active = false
		# Reset blend amounts when exiting Roll state - return to Movement
		_set_animation_parameter("parameters/RollSlideBlend/blend_amount", 0.0)
		_set_animation_parameter("parameters/MovementRollSlideBlend/blend_amount", 0.0)
	elif previous_state == "Slide" and state != "Slide":
		slide_oneshot_active = false
		# CRITICAL: Reset blend amounts when exiting Slide state so it returns to Movement, not Slide
		_set_animation_parameter("parameters/RollSlideBlend/blend_amount", 0.0)
		_set_animation_parameter("parameters/MovementRollSlideBlend/blend_amount", 0.0)
	
	# Determine if we're entering or exiting each state
	var is_entering_crouch = state == "Crouch" and previous_state != "Crouch"
	var is_exiting_crouch = previous_state == "Crouch" and state != "Crouch"
	
	# Sit state: Check both state parameter and actual state (special case for timing issues)
	var actual_state = _get_actual_current_state()
	var is_in_sit = state == "Sit" or actual_state == "Sit"
	var is_entering_sit = is_in_sit and previous_state != "Sit"
	var is_exiting_sit = previous_state == "Sit" and not is_in_sit
	
	var is_entering_push = state == "Push" and previous_state != "Push"
	var is_exiting_push = previous_state == "Push" and state != "Push"
	
	var is_entering_climb = (state == "Ladder" or state == "Ledge") and previous_state != "Ladder" and previous_state != "Ledge"
	var is_exiting_climb = (previous_state == "Ladder" or previous_state == "Ledge") and state != "Ladder" and state != "Ledge"
	
	# Handle Jump/Fall/Landing (special case - uses Jump StateMachine)
	_handle_jump_fall_landing(state)
	
	# Handle Float/AirControl (simple blend)
	if state == "Float" or state == "AirControl":
		_set_animation_parameter("parameters/FloatBlend/blend_amount", 1.0)
	elif state != "Float" and state != "AirControl":
		_set_animation_parameter("parameters/FloatBlend/blend_amount", 0.0)
	
	# Handle Sit state separately (allows Enter animation to complete, only exits to Stand)
	_handle_sit_state(is_entering_sit, is_exiting_sit, state)
	
	# Handle Climb state separately (allows Enter animation to complete, uses input direction for BlendSpace2D)
	_handle_climb_state(is_entering_climb, is_exiting_climb)
	
	# Handle other StateMachine-based states using helper function
	_handle_state_machine_blend("parameters/Crouch/playback", "parameters/CrouchBlend/blend_amount", 
		is_entering_crouch, is_exiting_crouch)
	
	_handle_state_machine_blend("parameters/Push/playback", "parameters/PushBlend/blend_amount", 
		is_entering_push, is_exiting_push)
	
	# Update previous_state AFTER all state handling
	previous_state = state

## Helper: Handles Jump/Fall/Landing animation logic (special case)
func _handle_jump_fall_landing(state: String) -> void:
	var jump_state_machine = _get_animation_parameter("parameters/Jump/playback")
	if not jump_state_machine:
		return
	
	if state == "Jump":
		# CRITICAL: Travel directly to "Jump" state, not "Start"
		# The "Start" state has no animation node defined (only position), so it defaults to T-pose
		# By skipping Start and going directly to Jump, we avoid the T-pose flash
		# Set JumpBlend to 1.0 FIRST to make the StateMachine visible
		_set_animation_parameter("parameters/JumpBlend/blend_amount", 1.0)
		# Then travel directly to Jump state (skipping Start which has no animation)
		jump_state_machine.travel("Jump")
	
	elif state == "Fall":
		# Fall state also uses Jump animation (falling animation)
		jump_state_machine.travel("Jump")
		_set_animation_parameter("parameters/JumpBlend/blend_amount", 1.0)
	
	elif state == "Idle" or state == "Walk" or state == "Sprint":
		var current_jump_state = _get_animation_parameter("parameters/Jump/current_state")
		if current_jump_state == "Jump":
			jump_state_machine.travel("Land")
			_trigger_oneshot("parameters/Jump/Land/OneShot/request")
		_set_animation_parameter("parameters/JumpBlend/blend_amount", 0.0)

## Selects a sit idle animation (currently simplified to single animation)
## Note: The AnimationTree now uses a single Sitting_Idle animation instead of a blend tree
## This function is kept for future use if multiple idle animations are added back
func _select_random_sit_idle() -> void:
	if not animation_tree:
		return
	
	# Currently, the Sit Idle state uses a single AnimationNodeAnimation (Sitting_Idle)
	# No blend parameters need to be set - the animation plays directly
	# If multiple idle animations are added back in the future, this function can be updated
	# to randomly select between them using blend parameters
	pass

## Called by Motion states when player input direction changes
## Updates model rotation in non-combat mode (when not using BlendSpace2D)
## In combat mode, the BlendSpace2D handles direction blending automatically
## Parameter dir: The input direction vector from the Motion state
func on_character_input_direction_changed(dir: Vector2) -> void:
	# Store raw input direction for immediate use in Climb state (no smoothing)
	# Always update raw_input_dir so it's always current (it's only used in Climb state anyway)
	raw_input_dir = dir
	
	# Smooth input direction for character rotation
	input_dir = input_dir.lerp(dir, turn_rate)
	
	if not animation_tree:
		return
	
	# Update camera rotation from player's body node
	var body_rotation = _get_camera_yaw()
	current_mouse_rotation.x = body_rotation
	
	# In non-combat mode, rotate the model to face movement direction
	# In combat mode, the BlendSpace2D handles direction blending
	rotate_model(input_dir, current_mouse_rotation)

## Signal callback from Camera when camera rotation changes
## Updates hip rotation and handles character model rotation in non-combat mode
## Parameter _rotation: The camera rotation vector (x: yaw, y: pitch)
func _on_camera_camera_rotated(_rotation: Vector2) -> void:
	current_mouse_rotation = _rotation
	rotate_hip()
	# Update model rotation when camera rotates
	rotate_model(input_dir, current_mouse_rotation)

## Gets the current camera yaw rotation from the player's body node
## Returns the yaw angle in radians, or 0.0 if body node not found
func _get_camera_yaw() -> float:
	if not player:
		return 0.0
	
	var body_node = player.get_node_or_null("Body") as Node3D
	if not body_node:
		return 0.0
	
	# Get yaw rotation from body's transform
	var forward = -body_node.global_transform.basis.z
	return atan2(forward.x, forward.z)

## Rotates the hip target node to follow camera pitch and apply rotation offset
## Used by hip IK to rotate upper body toward camera direction
func rotate_hip() -> void:
	if not hip_target:
		return
	hip_target.transform.basis = Basis()
	hip_target.rotate_object_local(Vector3(1, 0, 0), current_mouse_rotation.y)
	hip_target.rotate_object_local(Vector3(0, 1, 0), deg_to_rad(hip_rotation_offset))

## Rotates the character armature to face the camera direction (mouse look direction)
## In non-combat mode, character faces where the camera is looking, not movement direction
## 
## SETUP INSTRUCTIONS:
## For the player_model.tscn to always face the camera direction:
## 1. The player_model.tscn instance should be a direct child of the Body node in cogito_player.tscn
## 2. The Body node rotates with the camera (handled by third_person_camera.gd)
## 3. Since Body rotates with camera, the armature (player_model) will automatically rotate with Body
## 4. This function ensures the armature faces forward relative to Body's rotation
## 
## If armature is a child of Body: Only applies forward-facing offset (PI if model faces backwards)
## If armature is NOT a child of Body: Uses absolute rotation based on camera yaw (legacy behavior)
## 
## Parameter _angle: The input direction vector (unused - kept for compatibility)
## Parameter _rotation: The camera rotation vector (x: yaw, y: pitch)
func rotate_model(_angle: Vector2 = Vector2.ZERO, _rotation: Vector2 = Vector2.ZERO) -> void:
	if not armature:
		return
	
	# Get the Body node to check if armature is a child of it
	var body_node: Node3D = null
	if player:
		body_node = player.get_node_or_null("Body") as Node3D
	
	# Check if armature is a child of Body (or any ancestor of Body)
	var is_child_of_body: bool = false
	if body_node:
		var current_parent = armature.get_parent()
		while current_parent:
			if current_parent == body_node:
				is_child_of_body = true
				break
			current_parent = current_parent.get_parent()
	
	if is_child_of_body:
		# Armature is a child of Body (or descendant of Body)
		# Body already rotates with camera, so armature will automatically rotate with Body
		# We just need to ensure armature faces forward relative to Body's local space
		# Reset to identity and apply only the offset rotation (PI if model faces backwards by default)
		armature.transform.basis = Basis()
		armature.rotate_object_local(Vector3(0, 1, 0), PI)  # PI offset if model faces backwards by default
	else:
		# Armature is NOT a child of Body - use absolute rotation (legacy behavior)
		# This maintains backward compatibility if armature is placed elsewhere in the hierarchy
		# Rotate armature to face camera yaw direction (where mouse is pointing)
		armature.transform.basis = Basis()
		armature.rotate_object_local(Vector3(0, 1, 0), _rotation.x + PI)

## Checks if Roll OneShot animation is currently active
## Returns: True if Roll OneShot is active, false otherwise
func is_roll_oneshot_active() -> bool:
	if not animation_tree:
		return false
	
	# Check if we're in Roll state (if not, OneShot can't be active)
	# BUT: If roll_oneshot_active is true, assume it's active even if we can't detect it yet
	# This handles the case where call_deferred() hasn't executed yet
	if not roll_oneshot_active:
		return false
	
	# If roll_oneshot_active is true, assume it's active until proven otherwise
	# This prevents premature exit from Roll state when OneShot hasn't started yet
	
	# Try to get the OneShot active state
	# AnimationNodeOneShot exposes "active" as a parameter when it's part of the tree
	var oneshot_active = _get_animation_parameter("parameters/OneShot/active")
	if oneshot_active != null:
		var active = oneshot_active as bool
		# If OneShot is no longer active, update our tracking
		if not active:
			roll_oneshot_active = false
		return active
	
	# Alternative: Check the request parameter - if it's back to NONE (0), OneShot has finished
	var oneshot_request = _get_animation_parameter("parameters/OneShot/request")
	if oneshot_request != null:
		# AnimationNodeOneShot.ONE_SHOT_REQUEST_NONE = 0 (finished)
		# AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE = 1 (active)
		if oneshot_request == 0:
			# OneShot has finished
			roll_oneshot_active = false
			return false
		# If request is still FIRE or ABORT, animation is active
		return oneshot_request != 0
	
	# Alternative: Check if the Roll animation is actually playing via AnimationPlayer
	# This is a more reliable fallback - check if the Roll animation is in the AnimationPlayer
	# BUT: Only check if we've had time for call_deferred() to execute
	# We use a frame counter to ensure we've given the OneShot time to start
	if animation_player:
		# Check if Roll animation is currently assigned and playing
		# The OneShot node should be playing the Roll animation when active
		if animation_player.is_playing():
			# Try to get current animation name - if it's Roll, OneShot is active
			var current_anim = animation_player.current_animation
			if current_anim == "Roll":
				return true
			# If a different animation is playing, check if OneShot has started yet
			# If roll_oneshot_active is true but Roll isn't playing yet, assume it's starting
			elif roll_oneshot_active:
				# OneShot might not have started yet - give it time
				return true
			else:
				# Roll animation is not playing and roll_oneshot_active is false
				roll_oneshot_active = false
				return false
		else:
			# No animation playing - but if roll_oneshot_active is true, OneShot might not have started yet
			if roll_oneshot_active:
				# Give OneShot time to start (call_deferred might not have executed yet)
				return true
			# Roll animation has finished
			roll_oneshot_active = false
			return false
	
	# Fallback: Assume it's active if roll_oneshot_active is true
	# This will keep the state active until we can detect completion
	# This handles the case where call_deferred() hasn't executed yet
	return roll_oneshot_active

## Smoothly transitions an IK node's influence value over time using a Tween
## Used to blend IK on/off smoothly during state transitions
## Parameter ik: The SkeletonIK3D node to modify
## Parameter _influence: Target influence value (0.0 to 1.0)
## Parameter _time: Duration of the transition in seconds
func set_ik_influence(ik: SkeletonIK3D, _influence: float, _time: float) -> void:
	if not ik:
		return
	var tween: Tween = get_tree().create_tween()
	tween.tween_property(ik, "influence", _influence, _time)


## Connects to the player's PlayerInteractionComponent to receive wieldable change notifications
## This allows the animation controller to respond to weapon equip/unequip events
func _connect_to_wieldable_system() -> void:
	if not player:
		return
	
	# Get PlayerInteractionComponent
	var pic = player.get_node_or_null("PlayerInteractionComponent")
	if not pic:
		push_warning("AnimationController: Could not find PlayerInteractionComponent")
		return
	
	if pic.has_signal("updated_wieldable_data"):
		if not pic.updated_wieldable_data.is_connected(_on_wieldable_data_updated):
			pic.updated_wieldable_data.connect(_on_wieldable_data_updated)

## Connects to the player's PlayerInteractionComponent to trigger interact animations
## Monitors interact input directly in _input() instead of connecting to PlayerInteractionComponent
func _connect_to_interaction_system() -> void:
	# No connection needed - we monitor interact input directly in _input()
	pass

## Signal callback from PlayerInteractionComponent when wieldable item changes
## Called when a weapon is equipped, unequipped, or its data is updated
## Parameter _wielded_item: The WieldableItemPD resource (null if unequipped)
## Parameter _ammo_in_inventory: Amount of ammo in inventory (0 if none)
## Parameter _ammo_item: The AmmoItemPD resource (null if no ammo type)
func _on_wieldable_data_updated(_wielded_item, _ammo_in_inventory: int, _ammo_item) -> void:
	# Update upper body state based on wielded item
	if _wielded_item:
		# Weapon equipped - switch to appropriate upper body state
		# TODO: Determine weapon type and set appropriate state (PistolReady, RaisedFists, etc.)
		# For now, default to PistolReady if it's a weapon
		set_upper_body_state("PistolReady")
		# CRITICAL: Ensure UpperBodyBlend is set to 1.0 to show UpperBodyState
		# This is already done in set_upper_body_state(), but ensure it's set here too
		_set_animation_parameter("parameters/UpperBodyBlend/blend_amount", 1.0)
		# Enable IK for weapon holding
		set_ik_influence(hip_ik, 1, .1)
		set_ik_influence(right_hand_ik, .5, .1)
		set_ik_influence(left_hand_ik, 1, .1)
	else:
		# No weapon - return to neutral
		# CRITICAL: Set UpperBodyBlend to 0.0 FIRST before transitioning state
		# This prevents UpperBodyBlend from being set to 1.0 by set_upper_body_state()
		_set_animation_parameter("parameters/UpperBodyBlend/blend_amount", 0.0)
		# Transition to Neutral state without showing it (UpperBodyBlend is 0.0, so it won't be visible)
		# We still transition to Neutral to reset the state machine for next time a weapon is equipped
		var upper_body_state_machine = _get_animation_parameter("parameters/UpperBodyState/playback")
		if upper_body_state_machine:
			upper_body_state_machine.travel("Neutral")
		# Disable IK
		set_ik_influence(hip_ik, 0, .1)
		set_ik_influence(right_hand_ik, 0, .1)
		set_ik_influence(left_hand_ik, 0, .1)

## Triggers a hit animation via the Transition node
## Parameter hit_state: The hit animation state name (e.g., "hit")
func trigger_hit_animation(hit_state: String = "hit") -> void:
	if not animation_tree:
		return
	_set_animation_parameter("parameters/Transition/transition_request", hit_state)

## Triggers the Interact animation as a OneShot in the UpperBodyState StateMachine
## The animation will play as an upperbody-only overlay, then auto-return to Neutral after completion
## CRITICAL: Set blend amounts FIRST, then transition, then trigger OneShot immediately (no delays)
func trigger_interact_animation() -> void:
	if not animation_tree:
		return
	
	# CRITICAL: Set UpperBodyBlend to 1.0 FIRST to make UpperBodyState visible immediately
	_set_animation_parameter("parameters/UpperBodyBlend/blend_amount", 1.0)
	
	var upper_body_state_machine = _get_animation_parameter("parameters/UpperBodyState/playback")
	if not upper_body_state_machine:
		push_warning("AnimationController: UpperBodyState playback not found")
		return
	
	# Transition to Interact state
	upper_body_state_machine.travel("Interact")
	
	# Trigger the OneShot for Interact animation IMMEDIATELY - no delays, no deferred calls
	var param_path = "parameters/UpperBodyState/Interact/OneShot/request"
	var test_value = animation_tree.get(param_path)
	if test_value != null:
		# Reset OneShot first to ensure it can fire (critical for repeat triggers)
		animation_tree.set(param_path, AnimationNodeOneShot.ONE_SHOT_REQUEST_NONE)
		# Fire OneShot immediately - no deferred, no waiting
		animation_tree.set(param_path, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		# Force immediate processing of AnimationTree (critical for instant response)
		animation_tree.advance(0.0)
		interact_oneshot_active = true
	else:
		push_warning("AnimationController: Interact OneShot request parameter not found")

## Deferred function to trigger Roll OneShot after state transition completes
## Also called as backup even if immediate trigger was attempted
func _trigger_roll_oneshot() -> void:
	if not animation_tree:
		return
	
	var param_path = "parameters/OneShot/request"
	var test_value = animation_tree.get(param_path)
	if test_value != null:
		# Reset OneShot first to ensure it can fire (if it was already fired)
		# OneShot nodes need to be reset before they can fire again
		animation_tree.set(param_path, AnimationNodeOneShot.ONE_SHOT_REQUEST_NONE)
		# Then fire it
		animation_tree.set(param_path, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		# Verify it was set correctly
		var current_value = animation_tree.get(param_path)
		if current_value != AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE:
			# Try setting again if it didn't stick (sometimes needs multiple attempts)
			animation_tree.set(param_path, AnimationNodeOneShot.ONE_SHOT_REQUEST_NONE)
			animation_tree.set(param_path, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	else:
		# Parameter doesn't exist - fallback warning
		push_warning("AnimationController: Could not find OneShot/request parameter for Roll animation")
		roll_oneshot_active = false

## Triggers Jump_Start OneShot animation (called deferred after state transition)
func _trigger_jump_start_oneshot() -> void:
	if not animation_tree:
		return
	# Try to set the OneShot request - use set() method which handles nested parameters
	# Note: OneShot nodes inside BlendTrees may not expose request as a direct parameter
	# If this fails, the OneShot will still work via auto-advance from the BlendTree
	var param_path = "parameters/Jump/Start/OneShot/request"
	# Try to get the parameter to check if it exists
	var test_value = animation_tree.get(param_path)
	if test_value != null:
		animation_tree.set(param_path, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	# If parameter doesn't exist, OneShot will use auto-advance instead
	# This is fine, the Jump_Start animation will still play when entering Start state

## Triggers Jump_Land animation when player is about to hit the ground
## Called from Fall state when floor raycast detects ground
func trigger_jump_land() -> void:
	if not animation_tree:
		return
	
	var jump_state_machine = _get_animation_parameter("parameters/Jump/playback")
	if jump_state_machine:
		var current_jump_state = _get_animation_parameter("parameters/Jump/current_state")
		# Only trigger if we're in Jump state (falling), not already landing
		if current_jump_state == "Jump":
			jump_state_machine.travel("Land")
			# Trigger the Land OneShot animation using set() method
			var param_path = "parameters/Jump/Land/OneShot/request"
			# Try to get the parameter to check if it exists
			var test_value = animation_tree.get(param_path)
			if test_value != null:
				animation_tree.set(param_path, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

func _unhandled_input(event: InputEvent) -> void:
	# Monitor interact input to trigger interact animation EARLIER in the input chain
	# We check both "interact" and "interact2" actions to match PlayerInteractionComponent behavior
	# We don't consume the event so PlayerInteractionComponent can still handle it
	# Using _unhandled_input instead of _input ensures we process before other input handlers
	if event.is_action_pressed("interact") or event.is_action_pressed("interact2"):
		# Always trigger (will reset if already active) - this ensures immediate response
		trigger_interact_animation()

func _process(_delta: float) -> void:
	# Only update head scale if the multiplier has changed
	var current_scale = base_head_scale * head_scale_multiplier
	if current_scale != last_head_scale:
		_update_head_scale()
	
	# Continuously update model rotation to ensure it stays correct
	# This is important because rotate_model is only called when direction_updated signal is emitted
	# But we need to maintain rotation even when not moving
	if armature:
		# Update camera rotation from player's body node
		var body_rotation = _get_camera_yaw()
		current_mouse_rotation.x = body_rotation
		# Rotate model to face camera direction
		rotate_model(input_dir, current_mouse_rotation)
	
	# Monitor Interact OneShot completion and auto-return to Neutral
	if interact_oneshot_active and animation_tree:
		var oneshot_active = _get_animation_parameter("parameters/UpperBodyState/Interact/OneShot/active")
		if oneshot_active != null:
			var active = oneshot_active as bool
			if not active:
				# OneShot has completed - transition back to Neutral
				interact_oneshot_active = false
				var upper_body_state_machine = _get_animation_parameter("parameters/UpperBodyState/playback")
				if upper_body_state_machine:
					var current_state = _get_animation_parameter("parameters/UpperBodyState/current_state")
					if current_state == "Interact":
						upper_body_state_machine.travel("Neutral")
				
				# Check if there's a weapon equipped - if not, reset UpperBodyBlend to 0.0
				# If there is a weapon, UpperBodyBlend should stay at 1.0
				# This check runs regardless of state to ensure UpperBodyBlend is reset when Interact completes
				var has_weapon = false
				if player:
					var pic = player.get_node_or_null("PlayerInteractionComponent")
					if pic:
						# Directly access the property (it's a public var, not accessed via get())
						has_weapon = pic.equipped_wieldable_item != null
				
				if not has_weapon:
					# No weapon equipped - set UpperBodyBlend back to 0.0
					_set_animation_parameter("parameters/UpperBodyBlend/blend_amount", 0.0)

## Caches the head bone ID and base scale from bone metadata (called once in _ready)
func _cache_head_bone_info() -> void:
	if not skeleton or not is_instance_valid(skeleton):
		head_bone_id = -1
		return
	
	# Wait for skeleton to be ready
	if skeleton.get_bone_count() == 0:
		head_bone_id = -1
		return
	
	head_bone_id = skeleton.find_bone(head_bone_name)
	if head_bone_id == -1:
		push_warning("AnimationController: Could not find bone named '%s' in skeleton" % head_bone_name)
		return
	
	# Get HeadScale from bone metadata (only once, cache it)
	base_head_scale = Vector3.ONE
	if skeleton.has_bone_meta(head_bone_id, "HeadScale"):
		var meta_value = skeleton.get_bone_meta(head_bone_id, "HeadScale")
		if meta_value is Vector3:
			base_head_scale = meta_value

## Updates the head bone scale based on HeadScale bone metadata and head_scale_multiplier
## Reads the HeadScale Vector3 from the Head bone's BoneMetadata and applies it to the bone's scale
func _update_head_scale() -> void:
	# Early returns to prevent errors
	if not skeleton:
		return
	
	if not is_instance_valid(skeleton):
		return
	
	if not skeleton.is_inside_tree():
		return
	
	# Use cached bone ID
	if head_bone_id == -1:
		return
	
	# Check if skeleton is still ready
	if not skeleton.get_bone_count() > 0:
		return
	
	# Validate bone ID is still valid
	if head_bone_id < 0 or head_bone_id >= skeleton.get_bone_count():
		return
	
	# Apply the multiplier to cached base scale and set the bone scale
	var final_scale = base_head_scale * head_scale_multiplier
	
	# Validate scale is not NaN or infinite
	if is_nan(final_scale.x) or is_inf(final_scale.x) or \
	   is_nan(final_scale.y) or is_inf(final_scale.y) or \
	   is_nan(final_scale.z) or is_inf(final_scale.z):
		return
	
	# Only update if scale actually changed to reduce unnecessary operations
	if final_scale != last_head_scale:
		skeleton.set_bone_pose_scale(head_bone_id, final_scale)
		last_head_scale = final_scale
