## I set the player mesh on Layer 5, made it so FirstPerson camera can not see 5
extends Node3D

## This sends a signal to the CharacterModel/AnimationController (_on_camera_camera_rotated)
signal camera_rotated(_rotation: Vector2)

@export var character: CharacterBody3D
@export var edge_spring_arm: SpringArm3D
@export var rear_spring_arm: SpringArm3D
@export var third_person_camera: Camera3D
@export var first_person_camera: Camera3D
@export var model: Node3D
var model_controller: AnimationController
var model_mesh: MeshInstance3D


@export var camera_alignment_speed: float = 0.2

var camera_rotation: Vector2 = Vector2.ZERO

@export var mouse_sensitivity: float = 0.025
@export var max_y_rotation: float = 1.2

var camera_tween: Tween

enum CameraAlignment {LEFT = -1, RIGHT = 1, CENTRE = 0}
var current_camera_alignment : int = CameraAlignment.RIGHT

@onready var default_edge_spring_arm_length: float = edge_spring_arm.spring_length
@onready var default_rear_spring_arm_length: float = rear_spring_arm.spring_length
@onready var default_fov: float = third_person_camera.fov

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if model:
		model_controller = model
		if model.character_mesh:
			model_mesh = model.character_mesh
	handle_shadows(true)
	pass

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(InputConstants.INPUT_TOGGLE_CAMERA):
		if third_person_camera.current:
			third_person_camera.current = false
			first_person_camera.current = true
			handle_shadows(true)
		else:
			third_person_camera.current = true
			first_person_camera.current = false
			handle_shadows(false)
	
	if third_person_camera.current == false:
		return

	if event is InputEventMouseMotion:
		var mouse_event: Vector2 = event.screen_relative * mouse_sensitivity
		camera_look(mouse_event)
		
	if event.is_action_pressed(InputConstants.INPUT_SWITCH_CAMERA_SIDE):
		swap_camera_alignment()

func handle_shadows(is_fp: bool) -> void:
	if is_fp == true:
		model_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	else:
		model_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	
func camera_look(mouse_movement: Vector2) -> void:
	camera_rotation += mouse_movement
	
	transform.basis = Basis()
	character.transform.basis = Basis()
	
	character.rotate_object_local(Vector3(0,1,0), -camera_rotation.x)
	rotate_object_local(Vector3(1,0,0), -camera_rotation.y)
	
	camera_rotation.y = clamp(camera_rotation.y, -max_y_rotation, max_y_rotation)
	camera_rotated.emit(camera_rotation)

func swap_camera_alignment() -> void:
	match current_camera_alignment:
		CameraAlignment.RIGHT:
			set_current_camera_alignment(CameraAlignment.LEFT)
		CameraAlignment.LEFT:
			set_current_camera_alignment(CameraAlignment.RIGHT)
		CameraAlignment.CENTRE:
			return
	
	var new_pos: float = default_edge_spring_arm_length * current_camera_alignment
	set_rear_spring_arm_position(new_pos,camera_alignment_speed)

func set_current_camera_alignment(alignment: CameraAlignment) -> void:
	current_camera_alignment = alignment

func set_rear_spring_arm_position(pos: float, speed: float) -> void:
	if camera_tween:
		camera_tween.kill()
	
	camera_tween = get_tree().create_tween()
	camera_tween.set_trans(Tween.TRANS_EXPO)
	camera_tween.set_ease(Tween.EASE_OUT)
	

	camera_tween.tween_property(edge_spring_arm, "spring_length", pos, speed)
