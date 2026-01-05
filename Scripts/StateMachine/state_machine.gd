extends Node

## Generic finite state machine implementation.
## Manages state transitions, delegates input and physics updates to current state,
## and maintains a map of all available states as child nodes.
class_name StateMachine

## Initial state to enter when the state machine starts
@export var start_state: State
# Dictionary mapping state names (node names) to State instances
var state_map: Dictionary
# Currently active state instance
var current_state: State = null
# Whether the state machine is currently active and processing updates
var _active: bool = false :
	set = _set_active


## Initializes the state machine by creating state map and entering start state
func _ready() -> void:
	_create_state_map()
	if start_state:
		_initialize(start_state)
	else:
		push_warning("StateMachine._ready: start_state is not assigned. State machine will not be active until _initialize() is called with a valid state.")

## Delegates input events to the current state's _state_input method
func _input(event: InputEvent) -> void:
	if not current_state:
		return
	current_state._state_input(event)
	
## Delegates physics frame updates to the current state's _update method
func _physics_process(delta: float) -> void:
	if not current_state:
		return
	if not _active:
		return
	
	current_state._update(delta)

## Builds a dictionary mapping child node names to State instances
## Recursively finds all states including nested parent states and their children
## Connects each state's finished signal to _change_state for transitions
func _create_state_map()->void:
	_create_state_map_recursive(self)

## Recursively builds state map including nested states
## Parameter node: The node to search for states in
func _create_state_map_recursive(node: Node) -> void:
	for child in node.get_children():
		if child is State:
			child.finished.connect(_change_state)
			# Store both full path and just the name for flexible transitions
			var full_path = _get_state_path(child)
			state_map[full_path] = child
			state_map[child.name] = child  # Allow transitions by just name too
		# Recursively search children (for nested parent states)
		_create_state_map_recursive(child)

## Gets the full path to a state node (e.g., "Grounded/Idle")
## Parameter state: The state node to get path for
## Returns: Full path string or just name if at root level
func _get_state_path(state: Node) -> String:
	var path_parts: Array[String] = []
	var current = state
	var root = self
	
	# Walk up the tree to build path
	while current != root and current != null:
		path_parts.insert(0, current.name)
		current = current.get_parent()
	
	return "/".join(path_parts)

## Activates the state machine and enters the specified state
## Parameter state: The state to initialize and enter
func _initialize(state: State) -> void:
	if not state:
		push_error("StateMachine._initialize: Cannot initialize with null state. Ensure start_state is assigned in the inspector.")
		return
	_set_active(true)
	current_state = state
	current_state._enter()

## Sets the active state of the state machine
## When inactive, physics_process and input processing are disabled
## Parameter value: True to activate, false to deactivate
func _set_active(value: bool) -> void:
	_active = value
	set_physics_process(value)
	set_process_input(value)
	#if not _active:
		#current_state = null

## Transitions from current state to a new state by name
## Calls _exit on current state, then _enter on new state
## Supports both direct state names and full paths (e.g., "Idle" or "Grounded/Idle")
## Parent states (Grounded, Airborne, Climbing) automatically transition to their default child states
## Parameter state_name: Name of the state node to transition to (must exist in state_map)
func _change_state(state_name: String) -> void:
	if not _active:
		return
	
	# Try to find state by name or full path
	var target_state: State = null
	if state_map.has(state_name):
		target_state = state_map[state_name]
	else:
		# Try to find by searching for partial match (e.g., "Idle" when looking for "Grounded/Idle")
		# Prefer exact matches first, then partial matches
		var exact_match: State = null
		var partial_match: State = null
		for key in state_map.keys():
			if key == state_name:
				exact_match = state_map[key]
				break
			elif key.ends_with("/" + state_name):
				partial_match = state_map[key]
		
		target_state = exact_match if exact_match else partial_match
	
	if not target_state:
		push_error("StateMachine: State '" + state_name + "' not found in state_map. Available states: " + str(state_map.keys()))
		return

	var _from_state_name: String = "null"
	if current_state:
		_from_state_name = current_state.name
	if current_state:
		current_state._exit()
	current_state = target_state
	current_state._enter()
	
	# Note: If the target state is a parent state (like Grounded), its _enter() will
	# automatically emit finished with a child state name (like "Idle"), causing
	# another transition. This is the intended behavior for parent container states.
