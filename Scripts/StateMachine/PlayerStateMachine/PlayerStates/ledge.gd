extends Motion

## Ledge state: Player is climbing a ledge.
## Handles ledge climbing mechanics.
## Transitions to Grounded when climb completes, or Airborne if falling.

## Updates ledge climbing movement
## TODO: Implement ledge climbing mechanics
func _update(_delta: float) -> void:
	# Placeholder for ledge climbing implementation
	# This would handle:
	# - Detecting ledge grab
	# - Climbing animation
	# - Positioning player on top of ledge
	# - Transitioning to Grounded when complete
	
	if is_on_floor():
		finished.emit("Grounded")
	else:
		finished.emit("Airborne")
