# Cogito Player Setup Guide

This guide explains how to set up the `cogito_player.tscn` scene with the new Finite State Machine architecture.

## Overview

The Cogito Player uses a modular, data-driven architecture with:
- **Finite State Machine (FSM)** for player behavior
- **Resource-based configuration** for easy profile swapping (i.e. default_player_profile, "Injured Player")
- **Centralized input handling** via `InputConstants`
- **Optional AnimationController** for visible player models

## Scene Structure

```
CogitoPlayer (CharacterBody3D)
├── Body/Neck/Head/Eyes
│   ├── Camera3D
│   └── AnimationPlayer (optional)
├── StandingCollisionShape
├── CrouchingCollisionShape
├── CrouchRayCast
├── SlidingTimer
├── FootstepPlayer (AudioStreamPlayer3D)
├── JumpCooldownTimer
├── NavigationAgent3D
├── PlayerInteractionComponent
├── StateMachine (PlayerStateMachine)
│   ├── Grounded (ParentState)
│   │   ├── Idle
│   │   ├── Walk
│   │   ├── Sprint
│   │   ├── Slide
│   │   ├── Sneak
│   │   ├── Roll
│   │   ├── Crouch
│   │   ├── Stand
│   │   ├── Sit
│   │   └── Push
│   ├── Airborne (ParentState)
│   │   ├── AirControl
│   │   ├── Jump
│   │   ├── Fall
│   │   └── Float
│   └── Climbing (ParentState)
│       ├── Ladder
│       └── Ledge
└── [Other Cogito components...]
```

## Required Setup Steps

### 1. Assign PlayerResources

The `StateMachine` node requires a `PlayerResources` resource that contains all player configuration:

1. Select the `StateMachine` node in the scene tree
2. In the Inspector, find the `Player Resources` property
3. Assign a `PlayerResources` resource (`.tres` file)

**Default Resource Location:**
- `res://Scripts/Resources/PlayerProfiles/default_player_profile.tres`

**Creating a New Player Profile:**
1. Right-click in FileSystem → New Resource
2. Select `PlayerResources`
3. Configure all sub-resources:
   - `MovementStats` - speeds, jump, crouch, acceleration
   - `HeadbobStats` - camera wiggle parameters
   - `StairHandlingStats` - stair stepping behavior
   - `LadderHandlingStats` - ladder climbing parameters
   - `InputSettings` - mouse/gamepad sensitivity
   - `FreeLookSettings` - free look camera tilt

### 2. Assign AnimationController (Optional)

The `AnimationController` is **optional** - the system works without it for headless/invisible players:

1. Select the `StateMachine` node
2. In the Inspector, find the `Animation Controller` property
3. **Option A:** Assign your `AnimationController` node (if you have a visible player model)
4. **Option B:** Leave it empty (for headless/invisible players)

**Note:** If `AnimationController` is not assigned, all animation-related calls are safely ignored.

### 3. Set Start State

The state machine needs a starting state:

1. Select the `StateMachine` node
2. In the Inspector, find the `Start State` property
3. Assign the initial state (typically `Grounded/Idle`)

**Path:** `StateMachine/Grounded/Idle`

### 4. Configure Node Paths

Ensure these node paths exist in the scene:

#### Required Nodes:
- `Body/Neck/Head/Eyes` - Camera and headbob target
- `StandingCollisionShape` - Standing collision shape
- `CrouchingCollisionShape` - Crouching collision shape
- `CrouchRayCast` - Raycast to detect ceiling when standing
- `SlidingTimer` - Timer for slide duration
- `FootstepPlayer` - AudioStreamPlayer3D for footsteps
- `JumpCooldownTimer` - Timer to prevent jump spam
- `NavigationAgent3D` - For sittable exit positioning

#### Optional Nodes:
- `Body/Neck/Head/Eyes/AnimationPlayer` - For animations (if using AnimationController)
- `Body/Neck/Head/Eyes/Camera` - Camera node (should already exist)

### 5. Configure Input Actions

Ensure all input actions referenced in `InputConstants` are defined in Project Settings:


### 6. Configure Player Signals

The `CogitoPlayer` class emits signals that other systems can connect to:

**Essential Signals:**
- `menu_pressed(player_interaction_component)` - ESC/Menu pressed
- `toggle_inventory_interface()` - Inventory toggle
- `mouse_movement(relative_mouse_movement)` - Mouse look delta
- `player_state_loaded()` - Player state loaded

**Connecting Signals:**
Connect these in your game's UI or scene manager scripts.

## Resource Configuration Guide

### MovementStats

Controls all movement parameters:

**Jump Properties:**
- `jump_velocity` - Normal jump height (default: 4.5)
- `crouch_jump_velocity` - Crouch jump height (default: 3.0)
- `can_crouch_jump` - Allow jumping while crouched (default: true)

**Movement Speeds:**
- `walking_speed` - Normal walk speed (default: 5.0)
- `sprinting_speed` - Sprint speed (default: 8.0)
- `crouching_speed` - Crouch speed (default: 3.0)
- `sliding_speed` - Slide speed (default: 5.0)

**Acceleration:**
- `acceleration` - Ground acceleration (default: 100.0)
- `in_air_acceleration` - Air acceleration (default: 5.0)

**Sprint System:**
- `sprint_duration` - Max sprint time (default: 3.0)
- `minimum_sprint_threshold` - Min time to enter sprint (default: 0.5)

**Float Properties:**
- `float_speed_multiplier` - Speed multiplier for floating/swimming movement (default: 0.6)
- `float_vertical_speed` - Vertical movement speed when pressing jump/crouch while floating (default: 4.0)
- `float_drag` - Drag factor to slow down over time while floating (default: 0.02)

### HeadbobStats

Controls camera wiggle/headbob:

**Strength:**
- `headbob_strength` - Overall multiplier (Minimal: 0.1, Average: 0.7, Full: 1.0)

**Per-State Intensity/Speed:**
- Walking: `wiggle_on_walking_intensity`, `wiggle_on_walking_speed`
- Sprinting: `wiggle_on_sprinting_intensity`, `wiggle_on_sprinting_speed`
- Crouching: `wiggle_on_crouching_intensity`, `wiggle_on_crouching_speed`

### InputSettings

Controls input sensitivity and behavior:

**Mouse:**
- `mouse_sens` - Mouse sensitivity (default: 0.25)
- `invert_y_axis` - Invert vertical look (default: true)

**Gamepad:**
- `joy_deadzone` - Stick deadzone (default: 0.25)
- `joy_v_sens` - Vertical sensitivity (default: 2.0)
- `joy_h_sens` - Horizontal sensitivity (default: 2.0)

**Crouch:**
- `toggle_crouch` - Toggle vs hold crouch (default: false)

### StairHandlingStats

Controls automatic stair stepping:

- `step_height_camera_lerp` - Camera smoothing speed (default: 2.5)
- `step_height_default` - Max step height (default: Vector3(0, 0.5, 0))
- `step_max_slope_degree` - Max slope for step detection (default: 0.0)

### LadderHandlingStats

Controls ladder climbing:

- `can_sprint_on_ladder` - Allow sprinting on ladder (default: false)
- `ladder_speed` - Normal climb speed (default: 2.0)
- `ladder_sprint_speed` - Sprint climb speed (default: 3.3)
- `ladder_cooldown` - Re-entry cooldown (default: 0.5)
- `ladder_jump_scale` - Jump velocity multiplier (default: 0.5)

### FreeLookSettings

Controls free look camera tilt:

- `free_look_tilt_amount` - Tilt in degrees (default: 5.0)

## State Machine Behavior

### State Transitions

**Grounded States:**
- `Idle` ↔ `Walk` (based on input direction)
- `Walk` ↔ `Sprint` (based on sprint input)
- `Walk`/`Sprint` → `Jump` (jump input)
- `Sprint` + `Crouch` → `Slide`
- `Crouch` ↔ `Stand` (crouch toggle/release)
- Any Grounded → `Sit` (interact with sittable)
- Any Grounded → `Airborne` (leaving ground)

**Airborne States:**
- `Jump` → `Fall` (when velocity.y <= 0)
- `Fall` → `Roll` (hard landing: velocity.y <= -7.5)
- `Fall` → `Walk`/`Idle` (normal landing)
- `Fall` → `Float` (when gravity is overridden - gravity zones, swimming, space)
- `AirControl` → `Fall` (when descending)
- `Idle`/`Walk` → `Float` (when entering gravity zone)

**Climbing States:**
- `Ladder` - Entered when interacting with ladder
- `Ledge` - Entered when climbing ledges

### Parent States

Parent states (`Grounded`, `Airborne`, `Climbing`) act as containers and can be transitioned to directly:

- `finished.emit("Grounded")` - Returns to appropriate grounded state
- `finished.emit("Airborne")` - Enters airborne state
- `finished.emit("Climbing")` - Enters climbing state

## Testing Checklist

After setup, verify:

- [ ] Player can move (WASD)
- [ ] Player can jump
- [ ] Player can sprint
- [ ] Player can crouch
- [ ] Mouse look works
- [ ] Gamepad look works (if using gamepad)
- [ ] Stairs are automatically stepped
- [ ] Footsteps play when walking
- [ ] Menu opens/closes (ESC)
- [ ] Inventory toggles (if implemented)
- [ ] AnimationController works (if assigned)
- [ ] No errors in Output log

## Troubleshooting

### "PlayerStateMachine: player_resources is not assigned"
**Solution:** Assign a `PlayerResources` resource to the `StateMachine` node's `Player Resources` property.

### "PlayerStateMachine: Could not find Body/Neck/Head nodes"
**Solution:** Ensure the player scene has the correct node hierarchy: `Body/Neck/Head/Eyes`

### "Input action not found" errors
**Solution:** Add missing input actions in Project Settings → Input Map

### AnimationController errors
**Solution:** Either assign an `AnimationController` node, or leave it empty (system works without it)

### States not transitioning
**Solution:** Check that state node names match exactly (case-sensitive) and are children of the correct parent state

## Advanced: Runtime Resource Swapping

You can swap player resources at runtime for environmental effects or power-ups:

```gdscript
var state_machine = $StateMachine
var new_resources = preload("res://Scripts/Resources/PlayerProfiles/fast_player.tres")
state_machine.change_player_resources(new_resources)
```

This allows dynamic player profile changes (e.g., "Fast Player", "Stealth Player", "Underwater Player").

## Float State and Gravity Zones

The `Float` state provides full 3D movement control for zero-gravity, underwater, and space environments.

**Entry Conditions:**
- Automatically enters when gravity is overridden via `player.override_gravity()`
- Triggered by gravity zones, swim zones, or any system that calls `override_gravity()`

**Controls:**
- **WASD:** Horizontal movement in camera direction (60% speed by default)
- **Space (Jump):** Ascend/rise up
- **Ctrl (Crouch):** Descend/sink down
- **No Input:** Gravity zone's gravity applies (if configured)

**Configuration:**
- Speed multiplier: `MovementStats.float_speed_multiplier` (default: 0.6)
- Vertical speed: `MovementStats.float_vertical_speed` (default: 4.0)
- Drag factor: `MovementStats.float_drag` (default: 0.02)

**Exits:**
- To `Walk`/`Idle` when landing on ground after gravity returns to normal
- To `Fall` when gravity returns to normal while in air

**Usage Examples:**
- **Gravity zones:** Set gravity direction and force via `gravity_zone.gd`
- **Swimming/underwater:** Set gravity to zero or very low
- **Space environments:** Set gravity to zero
- **Zero-gravity areas:** Set custom gravity direction and force

## Notes

- The system is designed to work **without** an AnimationController for headless/invisible players
- All input actions are centralized in `InputConstants` for easy rebinding
- Player profiles can be swapped at runtime for gameplay variety
- The state machine automatically handles transitions based on player state (on floor, in air, etc.)
- Combat/non-combat animation blending can be handled via `AnimationController.on_combat_status_changed()` when weapons are wielded


