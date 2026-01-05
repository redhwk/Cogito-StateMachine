extends Node

## Base class for all state machine states.
## Provides virtual methods that child states override to implement state-specific behavior.
## States emit the finished signal with the next state name to trigger state transitions.
class_name State

## Emitted when state wants to transition to another state
## Parameter next_state: Name of the state node to transition to (must match child node name)
@warning_ignore("unused_signal")
signal finished(next_state: String)

## Called when entering this state
## Override in child states to perform initialization logic
func _enter() -> void:
	return
	
## Called when exiting this state
## Override in child states to perform cleanup logic
func _exit() -> void:
	return
	
## Called every frame when input events occur
## Override in child states to handle input-based state transitions
## Parameter _event: The InputEvent that occurred
func _state_input(_event: InputEvent) -> void:
	return
	
## Called every physics frame while this state is active
## Override in child states to perform per-frame updates (movement, physics, etc.)
## Parameter _delta: Time elapsed since last physics frame
func _update(_delta: float) -> void:
	return
