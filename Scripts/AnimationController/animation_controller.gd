extends Node3D

## Controls character animations, IK systems, and model rotation based on player input and combat state.
## Handles transitions between combat and non-combat animation states, weapon attachment/detachment,
## and synchronizes character model rotation with camera and input direction.
class_name AnimationController

## AnimationTree node that contains all animation states and blend trees
@export var animation_tree: AnimationTree

## Node3D representing the right hand attachment point for weapons
@export var right_hand: Node3D

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

## Current combat status: COMBAT or NONCOMBAT
enum CombatStatus {COMBAT, NONCOMBAT}

## Current camera rotation from mouse input (x: yaw, y: pitch)
var current_mouse_rotation: Vector2 = Vector2.ZERO

## Smoothed input direction for character movement
var input_dir: Vector2 = Vector2.UP

## Current combat status state
var current_combat_status: CombatStatus = CombatStatus.NONCOMBAT

## Weapon model that will be attached to the hand after animation completes
var next_weapon_to_load: Node = null

## Rotation offset in degrees applied to hip target (affects upper body angle)
var hip_rotation_offset: float = -55

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
	
	# Connect to player's wieldable system for future animation support
	_connect_to_wieldable_system()

## Called by PlayerStateMachine when motion state changes (Idle, Run, Jump, etc.)
## Updates the appropriate animation state machine based on current combat status
## Parameter state: The name of the state (e.g., "Idle", "Walk", "Sprint", "Jump")
func on_state_machine_state_change(state: String) -> void:
	if not animation_tree:
		return
	
	match current_combat_status:
		CombatStatus.NONCOMBAT:
			if animation_tree.has_parameter("parameters/unarmed_movement/transition_request"):
				animation_tree["parameters/unarmed_movement/transition_request"] = state
		CombatStatus.COMBAT:
			if animation_tree.has_parameter("parameters/armed_movement/transition_request"):
				animation_tree["parameters/armed_movement/transition_request"] = state

## Called when transitioning between combat and non-combat states
## Can be called directly or from wieldable system when weapon is equipped/unequipped
## Configures IK influences, model rotation, and animation tree transitions
## Parameter status: "combat" or "non_combat"
func on_combat_status_changed(status: String) -> void:
	if not animation_tree:
		return
	
	match status:
		"non_combat":
			input_dir = Vector2.UP
			current_combat_status = CombatStatus.NONCOMBAT
			_on_camera_camera_rotated(current_mouse_rotation)
			rotate_model(input_dir, current_mouse_rotation)
			set_ik_influence(hip_ik, 0, .1)
			set_ik_influence(left_hand_ik, 0, .1)
			set_ik_influence(right_hand_ik, 0, .1)
		"combat":
			current_combat_status = CombatStatus.COMBAT
			rotate_model(Vector2.UP, current_mouse_rotation)
			set_ik_influence(hip_ik, 1, .1)
	
	if animation_tree.has_parameter("parameters/combat_transition/transition_request"):
		animation_tree["parameters/combat_transition/transition_request"] = status

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

## Called by Motion states when player input direction changes
## Smoothly interpolates input direction and updates model rotation or animation blend positions
## based on combat status
## Parameter dir: The input direction vector from the Motion state
func on_character_input_direction_changed(dir: Vector2) -> void:
	input_dir = input_dir.lerp(dir, turn_rate)
	
	if not animation_tree:
		return
	
	match current_combat_status:
		CombatStatus.NONCOMBAT:
			rotate_model(input_dir, current_mouse_rotation)
		CombatStatus.COMBAT:
			if animation_tree.has_parameter("parameters/walk_blend/blend_position"):
				animation_tree["parameters/walk_blend/blend_position"] = input_dir
			if animation_tree.has_parameter("parameters/run_blend/blend_position"):
				animation_tree["parameters/run_blend/blend_position"] = input_dir

## Signal callback from Camera when camera rotation changes
## Updates hip rotation and handles character model rotation in non-combat mode
## Parameter _rotation: The camera rotation vector (x: yaw, y: pitch)
func _on_camera_camera_rotated(_rotation: Vector2) -> void:
	current_mouse_rotation = _rotation
	rotate_hip()
	match current_combat_status:
		CombatStatus.NONCOMBAT:
			transform.basis = Basis()
			rotate_object_local(Vector3(0, 1, 0), current_mouse_rotation.x)

## Rotates the hip target node to follow camera pitch and apply rotation offset
## Used by hip IK to rotate upper body toward camera direction
func rotate_hip() -> void:
	if not hip_target:
		return
	hip_target.transform.basis = Basis()
	hip_target.rotate_object_local(Vector3(1, 0, 0), current_mouse_rotation.y)
	hip_target.rotate_object_local(Vector3(0, 1, 0), deg_to_rad(hip_rotation_offset))

## Rotates the character armature to face the movement direction relative to camera rotation
## Calculates the angle between input direction and camera yaw, then rotates the model
## Parameter angle: The input direction vector
## Parameter _rotation: The camera rotation vector
func rotate_model(angle: Vector2 = Vector2.ZERO, _rotation: Vector2 = Vector2.ZERO) -> void:
	if not armature:
		return
	var new_angle: float = atan2(angle.x, angle.y) - _rotation.x
	armature.transform.basis = Basis()
	armature.rotate_object_local(Vector3(0, 1, 0), new_angle)

## Signal callback from WeaponManager when player switches weapons (TODO: future functionality)
## Disables hand IK and loads the new weapon configuration
## Currently using wieldable system instead - see _on_wieldable_data_updated()
## Parameter _weapon: The weapon resource
## Parameter _model: The weapon model node
func _on_weapon_manager_weapon_changed(_weapon: Node, _model: Node) -> void:
	set_ik_influence(left_hand_ik, 0, .1)
	set_ik_influence(right_hand_ik, 0, .1)
	load_new_weapon(_weapon, _model)

## Configures hand position/rotation and animation tree for a new weapon
## Sets up weapon-specific animations and stores the weapon model for later attachment
## Parameter _weapon: The weapon resource
## Parameter model: The weapon model node
func load_new_weapon(_weapon: Node, model: Node) -> void:
	if not right_hand or not animation_tree:
		return
	
	# TODO: Implement weapon-specific configuration when WeaponManager is integrated
	# For now, just store the model
	next_weapon_to_load = model
	
	# Example of how to set animations (uncomment when WeaponManager is ready):
	# if _weapon.has_method("get") and _weapon.get("hand_position"):
	# 	right_hand.position = _weapon.get("hand_position")
	# if _weapon.has_method("get") and _weapon.get("hand_rotation"):
	# 	right_hand.rotation = _weapon.get("hand_rotation")
	#
	# if animation_tree.tree_root.has_method("get_node"):
	# 	var weapon_idle = animation_tree.tree_root.get_node_or_null("weapon_idle_animation")
	# 	if weapon_idle and _weapon.has_method("get") and _weapon.get("weapon_idle_animation"):
	# 		weapon_idle.set_animation(_weapon.get("weapon_idle_animation").resource_name)
	
	if animation_tree.has_parameter("parameters/change_weapon/request"):
		animation_tree["parameters/change_weapon/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE

## Attaches the stored weapon model to the right hand node
## Called by animation event after weapon change animation completes
func attach_weapon_to_hand() -> void:
	if next_weapon_to_load and right_hand:
		right_hand.add_child(next_weapon_to_load)
		next_weapon_to_load = null

## Removes the currently attached weapon model from the right hand
## Used when switching weapons or entering non-combat state
func remove_weapon_attachment() -> void:
	if right_hand and right_hand.get_child_count() > 0:
		var current_weapon_attachment: Node3D = right_hand.get_child(0) as Node3D
		if current_weapon_attachment:
			current_weapon_attachment.queue_free()

## Activates hand IK when weapon is ready to be gripped
## Called by animation event after weapon attachment
func activate_hand_ik() -> void:
	if current_combat_status == CombatStatus.COMBAT:
		set_ik_influence(right_hand_ik, .5, .1)
		set_ik_influence(left_hand_ik, 1, .1)

## Signal callback from WeaponManager when weapon system finishes (TODO: future functionality)
## Handles weapon removal and animation state transitions
## Currently using wieldable system instead - see _on_wieldable_data_updated()
## Parameter status: The combat status string
## Parameter weapons_is_empty: Whether the weapon inventory is empty
func _on_weapon_manager_weapon_manager_finished(status: String, weapons_is_empty: bool) -> void:
	if not animation_tree:
		return
	
	if animation_tree.has_parameter("parameters/combat_transition/current_state"):
		if animation_tree["parameters/combat_transition/current_state"] == status:
			return
	
	on_combat_status_changed(status)
	next_weapon_to_load = null
	
	if not weapons_is_empty:
		if animation_tree.has_parameter("parameters/change_weapon/active") and animation_tree["parameters/change_weapon/active"]:
			remove_weapon_attachment()
			if animation_tree.has_parameter("parameters/change_weapon/request"):
				animation_tree["parameters/change_weapon/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT
		else:
			if animation_tree.has_parameter("parameters/change_weapon/request"):
				animation_tree["parameters/change_weapon/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE

## Signal callback from WeaponManager when weapon system starts (TODO: future functionality)
## Initializes combat state and loads the first weapon
## Currently using wieldable system instead - see _on_wieldable_data_updated()
## Parameter status: The combat status string
## Parameter _weapon: The weapon resource
## Parameter _model: The weapon model node
func _on_weapon_manager_weapon_manager_started(status: String, _weapon: Node, _model: Node) -> void:
	on_combat_status_changed(status)
	load_new_weapon(_weapon, _model)

## Signal callback from WeaponManager when weapon fires (TODO: future functionality)
## Triggers the shoot animation in the animation tree
func _on_weapon_manager_weapon_fired() -> void:
	if animation_tree and animation_tree.has_parameter("parameters/shoot/request"):
		animation_tree["parameters/shoot/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE

## Signal callback from WeaponManager when weapon reloads (TODO: future functionality)
## Disables hand IK and triggers the reload animation
func _on_weapon_manager_weapon_reloaded() -> void:
	set_ik_influence(right_hand_ik, 0, .1)
	set_ik_influence(left_hand_ik, 0, .1)
	if animation_tree and animation_tree.has_parameter("parameters/reload/request"):
		animation_tree["parameters/reload/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE

## Connects to the player's PlayerInteractionComponent to receive wieldable change notifications
## This allows the animation controller to respond to weapon equip/unequip events
func _connect_to_wieldable_system() -> void:
	# Find the player node (search up the tree for CharacterBody3D which CogitoPlayer extends)
	var player: Node = get_parent()
	var search_depth = 0
	const MAX_SEARCH_DEPTH = 10  # Prevent infinite loops
	
	# Search up the tree for CharacterBody3D (CogitoPlayer)
	while player and search_depth < MAX_SEARCH_DEPTH:
		if player is CharacterBody3D:
			break
		player = player.get_parent()
		search_depth += 1
	
	if not player or not player is CharacterBody3D:
		push_warning("AnimationController: Could not find player node to connect wieldable system")
		return
	
	# Get PlayerInteractionComponent
	var pic = player.get_node_or_null("PlayerInteractionComponent")
	if not pic:
		push_warning("AnimationController: Could not find PlayerInteractionComponent")
		return
	
	if pic.has_signal("updated_wieldable_data"):
		if not pic.updated_wieldable_data.is_connected(_on_wieldable_data_updated):
			pic.updated_wieldable_data.connect(_on_wieldable_data_updated)

## Signal callback from PlayerInteractionComponent when wieldable item changes
## Called when a weapon is equipped, unequipped, or its data is updated
## Parameter _wielded_item: The WieldableItemPD resource (null if unequipped)
## Parameter _ammo_in_inventory: Amount of ammo in inventory (0 if none)
## Parameter _ammo_item: The AmmoItemPD resource (null if no ammo type)
func _on_wieldable_data_updated(_wielded_item, _ammo_in_inventory: int, _ammo_item) -> void:
	# TODO: Add animation logic here when needed
	# This can trigger animations like:
	# - Equip animation when wielded_item is not null (was null before)
	# - Unequip animation when wielded_item is null (was not null before)
	# - Reload animation when ammo changes
	# - Weapon-specific animations based on wielded_item type
	
	# Example future implementation:
	# if _wielded_item:
	#     if not was_wielding_before:
	#         # Play equip animation
	#         pass
	# else:
	#     if was_wielding_before:
	#         # Play unequip animation
	#         pass
	pass
