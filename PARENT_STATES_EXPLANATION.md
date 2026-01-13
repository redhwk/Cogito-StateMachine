# Parent States System Explanation

## Overview

The state machine uses a **multi-tier hierarchy** with parent states acting as containers that automatically transition to their default child states.

## State Hierarchy Structure

```
PlayerStateMachine
├── Grounded (Parent State)
│   ├── Idle (default child)
│   ├── Walk
│   ├── Sprint
│   ├── Crouch
│   ├── Slide
│   ├── Stand
│   ├── Roll
│   ├── Sit
│   ├── Sneak
│   └── Push
├── Airborne (Parent State)
│   ├── Jump
│   ├── Fall (default child)
│   ├── AirControl
│   └── Float
└── Climbing (Parent State)
	├── Ladder (default child)
	└── Ledge
```

## How Parent States Work

### Grounded Parent State
- **Default Child:** Idle
- **Behavior:** When entered, automatically transitions to Idle
- **Use Case:** When any state emits `finished.emit("Grounded")`, the player enters Grounded, which immediately transitions to Idle

### Airborne Parent State
- **Default Child:** Fall (or Jump if ascending)
- **Behavior:** When entered, checks player velocity:
  - If `velocity.y > 0`: Transitions to Jump
  - If `velocity.y <= 0`: Transitions to Fall
- **Use Case:** When any state emits `finished.emit("Airborne")`, the player enters Airborne, which automatically selects the appropriate child state
- **Float State:** Used for zero-gravity, underwater, space environments (entered when gravity is overridden)

### Climbing Parent State
- **Default Child:** Ladder
- **Behavior:** When entered, automatically transitions to Ladder
- **Use Case:** When entering a ladder, transition to Climbing, which immediately goes to Ladder

## State Machine Recursive Mapping

The state machine now **recursively finds all states** in the hierarchy:

1. **Direct children** of StateMachine (Grounded, Airborne, Climbing)
2. **Nested children** of parent states (Idle, Walk, Jump, etc.)
3. **Full paths** are stored (e.g., "Grounded/Idle", "Airborne/Jump")
4. **Short names** are also stored (e.g., "Idle", "Jump") for flexible transitions

### Transition Examples

**From any Grounded child to Grounded:**
```gdscript
finished.emit("Grounded")  # Goes to Grounded parent, which auto-transitions to Idle
```

**From any state to specific child:**
```gdscript
finished.emit("Idle")      # Directly goes to Idle (works because of recursive mapping)
finished.emit("Walk")      # Directly goes to Walk
finished.emit("Jump")      # Directly goes to Jump
```

**From Airborne to Grounded:**
```gdscript
finished.emit("Grounded")  # Goes to Grounded parent, which auto-transitions to Idle
```

## State Transitions Flow

### Example: Landing from Fall

1. **Fall state** detects landing: `finished.emit("Grounded")`
2. **StateMachine** transitions to **Grounded** parent state
3. **Grounded._enter()** is called, which immediately emits `finished.emit("Idle")`
4. **StateMachine** transitions to **Idle** state
5. Player is now in Idle state

### Example: Jumping from Walk

1. **Walk state** detects jump input: `finished.emit("Jump")`
2. **StateMachine** transitions directly to **Jump** state (bypasses Airborne parent)
3. **Jump state** handles jump mechanics
4. When `velocity.y <= 0`, Jump emits: `finished.emit("Fall")`
5. **StateMachine** transitions to **Fall** state

### Example: Entering Ladder

1. **LadderArea** calls `player.enter_ladder(ladder, direction)`
2. **CogitoPlayer** forwards to **Ladder state**: `ladder_state.enter_ladder(ladder, direction)`
3. **Ladder state** emits: `finished.emit("Ladder")`
4. **StateMachine** transitions to **Ladder** state (or could go through Climbing parent)

## Parent State Implementation Details

### Grounded.gd
```gdscript
func _enter() -> void:
	var idle_state = get_node_or_null("Idle")
	if idle_state:
		finished.emit("Idle")  # Auto-transition to default child
```

### Airborne.gd
```gdscript
func _enter() -> void:
	# Check player velocity to determine child state
	if player_velocity.y > 0:
		finished.emit("Jump")
	else:
		finished.emit("Fall")
```

### Climbing.gd
```gdscript
func _enter() -> void:
	var ladder_state = get_node_or_null("Ladder")
	if ladder_state:
		finished.emit("Ladder")  # Auto-transition to default child
```

## Resource Passing

The `PlayerStateMachine` now **recursively passes resources** to all states:

- **Motion states** (Idle, Walk, Jump, etc.) receive all 6 resources via `set_resources()`
- **Parent states** (Grounded, Airborne, Climbing) don't need resources (they're just containers)
- **Sit state** (extends State, not Motion) doesn't need resources either

## Benefits of This Architecture

1. **Clean Transitions:** States can emit "Grounded" or "Airborne" without knowing specific child states
2. **Automatic Defaults:** Parent states handle default child selection
3. **Flexible:** Can still transition directly to specific states ("Idle", "Jump", etc.)
4. **Maintainable:** Adding new child states doesn't require updating all transition logic
5. **Hierarchical:** Clear organization of related states

## State Implementations

### Push State
- **Purpose:** Player is pushing a RigidBody3D object
- **Speed:** 70% of walking speed
- **Transitions:** To Idle when stopped, Airborne when leaving ground
- **Note:** RigidBody pushing is handled in `Motion.apply_velocity()`

### Sneak State
- **Purpose:** Player is sneaking (slower, quieter movement)
- **Speed:** 60% of walking speed
- **Footsteps:** 12dB quieter than walking
- **Headbob:** 50% intensity of walking headbob
- **Transitions:** To Idle when stopped, Sprint when sprint pressed, Airborne when leaving ground

### Float State
- **Purpose:** Player is in zero-gravity, underwater, or space environments
- **Control:** Full 3D movement with WASD, Jump (Space) to ascend, Crouch to descend
- **Speed:** Configurable via `MovementStats.float_speed_multiplier` (default: 0.6)
- **Vertical Speed:** Configurable via `MovementStats.float_vertical_speed` (default: 4.0)
- **Drag:** Configurable via `MovementStats.float_drag` (default: 0.02)
- **Entry:** Automatically entered when gravity is overridden (gravity zones, swim zones, etc.)
- **Transitions:** To Walk/Idle when landing on ground, Fall when gravity returns to normal and in air

## Testing Checklist

- [ ] Grounded parent auto-transitions to Idle
- [ ] Airborne parent auto-transitions to Jump (when ascending) or Fall (when descending)
- [ ] Climbing parent auto-transitions to Ladder
- [ ] States can transition to parent states ("Grounded", "Airborne", "Climbing")
- [ ] States can transition directly to child states ("Idle", "Walk", "Jump", etc.)
- [ ] All states receive resources correctly (Motion states only)
- [ ] Push state works when pushing RigidBody3D objects
- [ ] Sneak state works with reduced speed and quieter footsteps
- [ ] Float state works in gravity zones (Space to ascend, Crouch to descend)
- [ ] Float state transitions correctly when exiting gravity zones
