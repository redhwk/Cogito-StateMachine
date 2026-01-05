extends Node

## Constants for all input action names used by the state machine.
## Centralizes input action strings to match the project's input map configuration.
## Follows the same pattern as OptionsConstants for consistency with the addon architecture.
class_name InputConstants

## Movement input actions
const INPUT_FORWARD: StringName = &"forward"
const INPUT_BACKWARD: StringName = &"back"
const INPUT_LEFT: StringName = &"left"
const INPUT_RIGHT: StringName = &"right"
const INPUT_JUMP: StringName = &"jump"
const INPUT_SPRINT: StringName = &"sprint"
const INPUT_CROUCH: StringName = &"crouch"
const INPUT_FREE_LOOK: StringName = &"free_look"

## Combat/Weapon input actions
const INPUT_AIM: StringName = &"aim" #TODO: Find the correct input action name
const INPUT_SHOOT: StringName = &"action_primary" #TODO: Find the correct input action name
const INPUT_RELOAD: StringName = &"reload"
const INPUT_HOLSTER_WEAPON: StringName = &"holster_weapon" #TODO: Find the correct input action name
const INPUT_DROP_WEAPON: StringName = &"drop_weapon" #TODO: Find the correct input action name

## Interaction input actions
const INPUT_INTERACT: StringName = &"interact"
const INPUT_INTERACT_2: StringName = &"interact2"
const INPUT_ACTION_PRIMARY: StringName = &"action_primary"
const INPUT_ACTION_SECONDARY: StringName = &"action_secondary"

## Menu/UI input actions
const INPUT_MENU: StringName = &"menu"
const INPUT_INVENTORY: StringName = &"inventory"
const INPUT_INVENTORY_MOVE_ITEM: StringName = &"inventory_move_item"
const INPUT_INVENTORY_USE_ITEM: StringName = &"inventory_use_item"
const INPUT_INVENTORY_DROP_ITEM: StringName = &"inventory_drop_item"
const INPUT_INVENTORY_ASSIGN_ITEM: StringName = &"inventory_assign_item"
const INPUT_UI_NEXT_TAB: StringName = &"ui_next_tab"
const INPUT_UI_PREV_TAB: StringName = &"ui_prev_tab"

## Quick slot input actions
const INPUT_QUICKSLOT_1: StringName = &"quickslot_1"
const INPUT_QUICKSLOT_2: StringName = &"quickslot_2"
const INPUT_QUICKSLOT_3: StringName = &"quickslot_3"
const INPUT_QUICKSLOT_4: StringName = &"quickslot_4"
const INPUT_QUICKSLOT_PREV: StringName = &"quickslot_prev_wieldable"
const INPUT_QUICKSLOT_NEXT: StringName = &"quickslot_next_wieldable"

