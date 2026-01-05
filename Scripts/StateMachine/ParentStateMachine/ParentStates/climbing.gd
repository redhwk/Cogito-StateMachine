extends State

## Climbing parent state: Container for all climbing-based movement states.
## Automatically transitions to Ladder when entered (default climbing state).
## Climbing child states (Ladder, Ledge) are children of this node.

## Called when entering Climbing state
## Automatically transitions to Ladder (default climbing state)
func _enter() -> void:
	# Transition to default child state (Ladder)
	var ladder_state = get_node_or_null("Ladder")
	if ladder_state:
		finished.emit("Ladder")
	else:
		push_error("Climbing state: Ladder child state not found")

## Updates climbing state (parent states typically don't do much)
## Child states handle all the actual logic
func _update(_delta: float) -> void:
	# Parent states are containers - child states do the work
	# Child states (Ladder, Ledge) handle all transition logic
	pass
