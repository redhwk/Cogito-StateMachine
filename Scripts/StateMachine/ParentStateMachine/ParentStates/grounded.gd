extends State

## Grounded parent state: Container for all ground-based movement states.
## Automatically transitions to Idle when entered (default grounded state).
## All grounded child states (Idle, Walk, Sprint, Crouch, etc.) are children of this node.

## Called when entering Grounded state
## Automatically transitions to Idle (default grounded state)
func _enter() -> void:
	# Transition to default child state (Idle)
	var idle_state = get_node_or_null("Idle")
	if idle_state:
		finished.emit("Idle")
	else:
		push_error("Grounded state: Idle child state not found")

## Updates grounded state (parent states typically don't do much)
## Child states handle all the actual logic
func _update(_delta: float) -> void:
	# Parent states are containers - child states do the work
	pass
