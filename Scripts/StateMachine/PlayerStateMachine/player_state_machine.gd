extends StateMachine

## State machine managing all player movement states (Idle, Run, Jump, Sprint, Aim, etc.).
## Connects Motion state signals to AnimationController for animation synchronization.
## Handles input for mouse/gamepad look, menu, and inventory.

## Container resource holding all player configuration resources (movement, headbob, input, etc.).
## Create different PlayerResources (.tres files) to define player profiles (e.g., "Fast Player", "Stealth Player").
## Can be swapped at runtime to change player characteristics based on environmental or gameplay factors.
@export var player_resources: PlayerResources

## AnimationController reference for sending animation requests and direction updates
@export var animation_controller: AnimationController

## Reference to the player node (CogitoPlayer) - set automatically in _ready
var player: CogitoPlayer

## Player body/head nodes for camera rotation (accessed via player node)
var body: Node3D
var neck: Node3D
var head: Node3D

## Input state tracking
var joystick_h_event: InputEventJoypadMotion
var joystick_v_event: InputEventJoypadMotion
var is_movement_paused: bool = false
var is_showing_ui: bool = false
var is_free_looking: bool = false
var body_rotation_locked: bool = false  # Prevents mouse look from rotating Body (used after standing up)
var saved_forward_direction: Vector3 = Vector3.ZERO  # Saved forward direction to use for first movement after standing up
var saved_forward_use_count: int = 0  # Number of times we've used the saved forward direction (cleared after 3 uses)
var body_rotation_unlock_next_frame: bool = false  # Set by motion.gd after 3 saved-direction uses to unlock in next frame

## Cached input settings reference (for performance)
var input_settings: InputSettings

## Connects Motion state signals to AnimationController
## Creates state map and initializes state machine
## Extracts resources from PlayerResources container and passes them to all Motion states
## Sets up player node references for input handling
func _ready() -> void:
	
	# Get player node reference (StateMachine is child of player)
	player = get_parent() as CogitoPlayer
	if not player:
		push_error("PlayerStateMachine: Parent must be CogitoPlayer")
		return
	
	
	# Cache player body/head nodes for camera rotation
	body = player.get_node_or_null("Body") as Node3D
	neck = player.get_node_or_null("Body/Neck") as Node3D
	head = player.get_node_or_null("Body/Neck/Head") as Node3D
	
	if not body or not neck or not head:
		push_error("PlayerStateMachine: Could not find Body/Neck/Head nodes in player")
	
	# Validate that player_resources is assigned
	if not player_resources:
		push_error("PlayerStateMachine: player_resources is not assigned. Please assign a PlayerResources resource in the inspector.")
		return
	
	
	# Validate that all required resources are present in the container
	if not player_resources.movement_stats:
		push_error("PlayerStateMachine: player_resources.movement_stats is missing. Please assign all resources in the PlayerResources container.")
		return
	if not player_resources.headbob_stats:
		push_error("PlayerStateMachine: player_resources.headbob_stats is missing.")
	if not player_resources.stair_handling_stats:
		push_error("PlayerStateMachine: player_resources.stair_handling_stats is missing.")
	if not player_resources.ladder_handling_stats:
		push_error("PlayerStateMachine: player_resources.ladder_handling_stats is missing.")
	if not player_resources.input_settings:
		push_error("PlayerStateMachine: player_resources.input_settings is missing.")
	if not player_resources.free_look_settings:
		push_error("PlayerStateMachine: player_resources.free_look_settings is missing.")
	
	# Extract resources from container
	var movement_stats: MovementStats = player_resources.movement_stats
	var headbob_stats: HeadbobStats = player_resources.headbob_stats
	var stair_handling_stats: StairHandlingStats = player_resources.stair_handling_stats
	var ladder_handling_stats: LadderHandlingStats = player_resources.ladder_handling_stats
	input_settings = player_resources.input_settings
	var free_look_settings: FreeLookSettings = player_resources.free_look_settings
	
	# Load options from config file and update InputSettings
	_load_options_from_config()
	
	# Connect to options menu signal to reload settings when options change
	if player.pause_menu:
		var pause_menu_node = player.get_node_or_null(player.pause_menu)
		if pause_menu_node:
			# Try different possible paths to OptionsTabMenu (based on PauseMenu.tscn structure)
			var options_tab = pause_menu_node.get_node_or_null("Content/TabContainer/OptionsTabMenu")
			if not options_tab:
				options_tab = pause_menu_node.get_node_or_null("Content/OptionsTabMenu")
			if not options_tab:
				options_tab = pause_menu_node.get_node_or_null("TabContainer/OptionsTabMenu")
			if not options_tab:
				options_tab = pause_menu_node.get_node_or_null("OptionsTabMenu")
			# Also try searching recursively
			if not options_tab:
				options_tab = pause_menu_node.find_child("OptionsTabMenu", true, false)
			
			if options_tab and options_tab.has_signal("options_updated"):
				if not options_tab.options_updated.is_connected(_on_options_updated):
					options_tab.options_updated.connect(_on_options_updated)
			else:
				pass
	
	# Pass resources to all Motion states (recursively find all states)
	_pass_resources_to_states_recursive(self, movement_stats, headbob_stats, stair_handling_stats, 
		ladder_handling_stats, input_settings, free_look_settings)
	
	# Connect animation signals to all states (recursively)
	_connect_animation_signals_recursive(self)
	
	# Create state map for state lookups
	_create_state_map()
	
	# Initialize directly (PlayerStateMachine is a direct child of the player)
	var parent_state_machine = get_parent().get_node_or_null("ParentStateMachine")
	if not parent_state_machine or parent_state_machine == self:
		# Initialize directly
		# Try to resolve start_state (can be NodePath from inspector or State object)
		var initial_state: State = null
		
		# First, try to use start_state directly if it's already a State
		if start_state and start_state is State:
			initial_state = start_state
		else:
			# start_state might be a NodePath - try to resolve it
			# Get the raw property value to check its actual type
			var start_state_raw = get("start_state")
			if start_state_raw:
				if start_state_raw is NodePath:
					initial_state = get_node_or_null(start_state_raw) as State
				elif start_state_raw is String:
					initial_state = get_node_or_null(NodePath(start_state_raw)) as State
				elif start_state_raw is State:
					initial_state = start_state_raw
		
		# Fallback: if we still don't have a state, try to find Grounded
		if not initial_state:
			initial_state = get_node_or_null("Grounded") as State
		
		if initial_state:
			_initialize(initial_state)
			var _state_name: String
			if current_state:
				_state_name = current_state.name
			else:
				_state_name = "NULL"
			# Capture mouse on startup
			if InputHelper.device_index == -1:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		else:
			push_error("PlayerStateMachine: Could not find initial state. Please assign start_state in the inspector or ensure Grounded state exists.")
			_set_active(false)
	else:
		# If ParentStateMachine exists (future use), wait for it to activate us
		_set_active(false)

## Recursively passes resources to all Motion states in the hierarchy
func _pass_resources_to_states_recursive(node: Node, movement_stats: MovementStats, headbob_stats: HeadbobStats,
	stair_handling_stats: StairHandlingStats, ladder_handling_stats: LadderHandlingStats,
	input_config: InputSettings, free_look_settings: FreeLookSettings) -> void:
	for child in node.get_children():
		if child is Motion:
			child.set_resources(movement_stats, headbob_stats, stair_handling_stats, 
				ladder_handling_stats, input_config, free_look_settings)
		# Recursively process children (for nested parent states)
		_pass_resources_to_states_recursive(child, movement_stats, headbob_stats, stair_handling_stats,
			ladder_handling_stats, input_config, free_look_settings)

## Recursively connects animation signals to all states
## Note: animation_change_requested signals are no longer used - state changes are handled
## automatically via _change_state() calling AnimationController.on_state_machine_state_change()
func _connect_animation_signals_recursive(node: Node) -> void:
	if not animation_controller:
		return
	
	for child in node.get_children():
		if child.has_signal("direction_updated"):
			child.direction_updated.connect(animation_controller.on_character_input_direction_changed)
		# Recursively process children
		_connect_animation_signals_recursive(child)

## Changes the player resources at runtime (useful for environmental effects, power-ups, etc.)
## Parameter new_resources: The PlayerResources resource to switch to
func change_player_resources(new_resources: PlayerResources) -> void:
	if not new_resources:
		push_error("PlayerStateMachine.change_player_resources: new_resources is null.")
		return
	
	player_resources = new_resources
	
	# Extract and update resources
	var movement_stats: MovementStats = player_resources.movement_stats
	var headbob_stats: HeadbobStats = player_resources.headbob_stats
	var stair_handling_stats: StairHandlingStats = player_resources.stair_handling_stats
	var ladder_handling_stats: LadderHandlingStats = player_resources.ladder_handling_stats
	input_settings = player_resources.input_settings
	var free_look_settings: FreeLookSettings = player_resources.free_look_settings
	
	# Update all Motion states with new resources (recursively)
	_pass_resources_to_states_recursive(self, movement_stats, headbob_stats, stair_handling_stats, 
		ladder_handling_stats, input_settings, free_look_settings)

## Signal callback from Camera when model view mode changes
## Disables state machine when in model view, enables when in game view
## Parameter view: True if model view is active, false if game view
func _on_camera_model_view_changed(view: bool) -> void:
	_set_active(!view)

## Overrides base StateMachine._input to handle mouse/gamepad look and menu/inventory
## Delegates other input to current state's _state_input method
func _input(event: InputEvent) -> void:
	# Handle mouse look
	if event is InputEventMouseMotion and not is_movement_paused:
		_handle_mouse_look(event)
	
	# Handle gamepad look (store events for processing in _physics_process)
	if event is InputEventJoypadMotion and not is_movement_paused:
		if event.get_axis() == 2:
			joystick_v_event = event
		if event.get_axis() == 3:
			joystick_h_event = event
	
	# Handle menu input
	if event.is_action_pressed(InputConstants.INPUT_MENU):
		_handle_menu_input()
	
	# Handle inventory input
	if event.is_action_pressed(InputConstants.INPUT_INVENTORY):
		_handle_inventory_input()
	
	# Delegate other input to current state (only if movement is not paused)
	if current_state and not is_movement_paused:
		current_state._state_input(event)

## Handles mouse look rotation for camera/head
## Uses InputSettings for sensitivity and inversion
## Parameter event: InputEventMouseMotion event
func _handle_mouse_look(event: InputEventMouseMotion) -> void:
	if not input_settings or not body or not neck or not head:
		return
	
	# Don't rotate Body if player is sitting - Sit state handles its own look constraints
	var is_sitting = false
	if current_state and current_state.name == "Sit":
		is_sitting = true
	
	var look_movement: Vector2 = Vector2(0.0, 0.0)
	
	# TODO: Handle sittable look (needs access to sittable state)
	# For now, handle normal look
	if is_free_looking:
		neck.rotate_y(deg_to_rad(-event.relative.x * input_settings.mouse_sens))
		neck.rotation.y = clamp(neck.rotation.y, deg_to_rad(-120), deg_to_rad(120))
	elif not is_sitting and not body_rotation_locked:
		# Only rotate Body if not sitting and not locked
		# body_rotation_locked is set temporarily after standing up to prevent rotation
		# This ensures mouse input can't interfere with rotation restoration
		body.rotate_y(deg_to_rad(-event.relative.x * input_settings.mouse_sens))
		look_movement.x = -event.relative.x
	
	# Vertical look
	if input_settings.invert_y_axis:
		# Inverted: mouse down = look up, mouse up = look down
		head.rotate_x(-deg_to_rad(event.relative.y * input_settings.mouse_sens))
		look_movement.y = -event.relative.y
	else:
		# Normal: mouse down = look down, mouse up = look up
		head.rotate_x(deg_to_rad(event.relative.y * input_settings.mouse_sens))
		look_movement.y = event.relative.y
	
	head.rotation.x = clamp(head.rotation.x, deg_to_rad(-90), deg_to_rad(90))
	
	# Emit mouse movement signal to player
	if player:
		player.mouse_movement.emit(look_movement)

## Handles gamepad look rotation (called from _physics_process)
## Uses InputSettings for sensitivity and deadzone
func _handle_gamepad_look(delta: float) -> void:
	if not input_settings or not body or not neck or not head or is_movement_paused:
		return
	
	# Process horizontal look
	if joystick_h_event:
		if abs(joystick_h_event.get_axis_value()) > input_settings.joy_deadzone:
			if input_settings.invert_y_axis:
				head.rotate_x(deg_to_rad(joystick_h_event.get_axis_value() * input_settings.joy_h_sens * delta))
			else:
				head.rotate_x(-deg_to_rad(joystick_h_event.get_axis_value() * input_settings.joy_h_sens * delta))
			head.rotation.x = clamp(head.rotation.x, deg_to_rad(-90), deg_to_rad(90))
	
	# Process vertical look
	if joystick_v_event:
		if abs(joystick_v_event.get_axis_value()) > input_settings.joy_deadzone:
			neck.rotate_y(deg_to_rad(-joystick_v_event.get_axis_value() * input_settings.joy_v_sens * delta))
			neck.rotation.y = clamp(neck.rotation.y, deg_to_rad(-120), deg_to_rad(120))

## Handles menu/pause input
func _handle_menu_input() -> void:
	if not player:
		return
	
	if CogitoSceneManager.is_currently_loading:
		return
	
	if is_showing_ui:
		# Behavior when pressing ESC/menu while external UI is open
		player.menu_pressed.emit(player.player_interaction_component)
		# Check if inventory is open and toggle it
		var player_hud = player.get_node_or_null(player.player_hud)
		if player_hud and player_hud.has_method("get") and player_hud.get("inventory_interface"):
			var inventory_interface = player_hud.get("inventory_interface")
			if inventory_interface.has_method("get") and inventory_interface.get("is_inventory_open"):
				player.toggle_inventory_interface.emit()
	else:
		if not is_movement_paused and not player.is_dead:
			# Check if currently_tweening (sittable) - this will be moved to Sit state
			# For now, just pause movement
			_on_pause_movement()
			# Open pause menu
			if player.pause_menu:
				var pause_menu_node = player.get_node(player.pause_menu)
				if pause_menu_node and pause_menu_node.has_method("open_pause_menu"):
					pause_menu_node.open_pause_menu()

## Handles inventory toggle input
func _handle_inventory_input() -> void:
	if not player or player.is_dead:
		return
	
	if not is_showing_ui:
		player.toggle_inventory_interface.emit()
	else:
		# Close inventory if it's open
		var player_hud = player.get_node_or_null(player.player_hud)
		if player_hud and player_hud.has_method("get") and player_hud.get("inventory_interface"):
			var inventory_interface = player_hud.get("inventory_interface")
			if inventory_interface.has_method("get") and inventory_interface.get("is_inventory_open"):
				player.toggle_inventory_interface.emit()

## Pauses movement and shows mouse cursor
func _on_pause_movement() -> void:
	if not is_movement_paused:
		is_movement_paused = true
		# Only show mouse cursor if input device is KBM
		if InputHelper.device_index == -1:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

## Resumes movement and captures mouse
func _on_resume_movement() -> void:
	if is_movement_paused:
		is_movement_paused = false
		# Reload options from config in case they were changed
		_update_input_settings_from_config()
		# Release mouse capture
		if InputHelper.device_index == -1:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

## Loads options from config file and updates InputSettings resource
func _load_options_from_config() -> void:
	if not input_settings:
		return
	
	var config = ConfigFile.new()
	var err = config.load(OptionsConstants.config_file_name)
	if err != OK:
		# Config file doesn't exist yet, use defaults
		return
	
	# Load invert Y axis setting
	var invert_y = config.get_value(OptionsConstants.section_name, OptionsConstants.invert_vertical_axis_key, input_settings.invert_y_axis)
	input_settings.invert_y_axis = invert_y
	
	# Load mouse sensitivity
	var mouse_sens = config.get_value(OptionsConstants.section_name, OptionsConstants.mouse_sens_key, input_settings.mouse_sens)
	input_settings.mouse_sens = mouse_sens
	
	# Load toggle crouch setting
	var toggle_crouch = config.get_value(OptionsConstants.section_name, OptionsConstants.toggle_crouching_key, input_settings.toggle_crouch)
	input_settings.toggle_crouch = toggle_crouch
	
	# Load gamepad settings
	var joy_deadzone = config.get_value(OptionsConstants.section_name, "joy_deadzone", input_settings.joy_deadzone)
	input_settings.joy_deadzone = joy_deadzone
	var joy_v_sens = config.get_value(OptionsConstants.section_name, OptionsConstants.gp_looksens_key, input_settings.joy_v_sens)
	input_settings.joy_v_sens = joy_v_sens
	var joy_h_sens = config.get_value(OptionsConstants.section_name, "joy_h_sens", input_settings.joy_h_sens)
	input_settings.joy_h_sens = joy_h_sens

## Signal callback when options are updated
func _on_options_updated() -> void:
	_update_input_settings_from_config()

## Updates InputSettings from options config (called when options change)
func _update_input_settings_from_config() -> void:
	_load_options_from_config()
	# Re-pass resources to update all states with new settings
	if player_resources:
		var movement_stats: MovementStats = player_resources.movement_stats
		var headbob_stats: HeadbobStats = player_resources.headbob_stats
		var stair_handling_stats: StairHandlingStats = player_resources.stair_handling_stats
		var ladder_handling_stats: LadderHandlingStats = player_resources.ladder_handling_stats
		var free_look_settings: FreeLookSettings = player_resources.free_look_settings
		_pass_resources_to_states_recursive(self, movement_stats, headbob_stats, stair_handling_stats,
			ladder_handling_stats, input_settings, free_look_settings)

## Unlocks rotation after restoration is complete
## Called deferred after Motion.set_direction has used the restored rotation
func _unlock_rotation_after_restore() -> void:
	if body_rotation_locked:
		body_rotation_locked = false

## Override _change_state to notify animation controller of state changes
func _change_state(state_name: String) -> void:
	# Call parent to handle the actual state transition
	super._change_state(state_name)
	
	# Notify animation controller of state change (for Jump, Fall, Float, Sit, etc.)
	if animation_controller and current_state:
		animation_controller.on_state_machine_state_change(current_state.name)

## Override _physics_process to handle gamepad look and update animations
func _physics_process(delta: float) -> void:
	# Unlock rotation one frame after motion.gd finishes using the saved forward direction
	# motion.gd sets body_rotation_unlock_next_frame when it has consumed the saved direction 3 times
	if body_rotation_unlock_next_frame:
		body_rotation_unlock_next_frame = false
		if body_rotation_locked:
			body_rotation_locked = false
	
	# Safety: if we're not sitting and rotation is still locked, unlock it
	if body_rotation_locked and (not current_state or current_state.name != "Sit"):
		body_rotation_locked = false
	
	# Handle gamepad look
	_handle_gamepad_look(delta)
	
	# Call parent _physics_process to delegate to current state
	# This will call Motion.set_direction() which will use saved forward direction if available
	super._physics_process(delta)
	
	# Update animations based on player velocity (blend tree system)
	if animation_controller and current_state is Motion:
		animation_controller.update_animations(delta)
