extends CharacterBody2D

const SPEED := 130.0
const JUMP_VELOCITY := -300.0
const COOLDOWN_EMPURRAO := 1.0

var player_id: int = -1

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

var facing_direction: float = 1.0
var push_cooldown: float = 0.0

func _ready() -> void:
	add_to_group("players")
	_ensure_gameplay_actions()


func _physics_process(delta: float) -> void:
	if not NetworkManager.is_online():
		return

	if not is_on_floor():
		velocity.y += gravity * delta

	_disable_passive_collision()

	if player_id == NetworkManager.my_player_id:
		if push_cooldown > 0:
			push_cooldown -= delta
		_handle_local_input()
		_check_active_push()
		move_and_slide()
	
	if velocity.x != 0:
		$AnimatedSprite2D.flip_h = !(velocity.x < 0)
		facing_direction = signf(velocity.x)

func _handle_local_input() -> void:
	if Input.is_action_just_pressed(&"jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	
	var direction := Input.get_axis(&"move_left", &"move_right")
	if direction:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

func _disable_passive_collision() -> void:
	var others := get_tree().get_nodes_in_group("players")
	for other in others:
		if other != self:
			add_collision_exception_with(other)
	
func _check_active_push() -> void:
	if Input.is_action_just_pressed(&"push") and push_cooldown <= 0.0:
		push_cooldown = COOLDOWN_EMPURRAO
		var others := get_tree().get_nodes_in_group("players")
		for other in others:
			if other == self:
				continue
		
			if global_position.distance_to(other.global_position) < 40:
				NetworkManager.send_push_command(other.player_id, facing_direction)
				
func receive_knockback(push_dir: float) -> void:
	velocity.y = -150
	
	velocity.x = push_dir * 800
	
func _ensure_gameplay_actions() -> void:
	_add_key_to_action(&"move_left", KEY_A)
	_add_key_to_action(&"move_left", KEY_LEFT)
	_add_key_to_action(&"move_right", KEY_D)
	_add_key_to_action(&"move_right", KEY_RIGHT)
	_add_key_to_action(&"jump", KEY_SPACE)
	_add_key_to_action(&"jump", KEY_W)
	_add_key_to_action(&"jump", KEY_UP)
	
	# essas aqui são pra empurrar o coleguinha
	_add_key_to_action(&"push", KEY_E)
	_add_key_to_action(&"push", KEY_SHIFT)


func _add_key_to_action(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and ev.physical_keycode == keycode:
			return
	var ke := InputEventKey.new()
	ke.physical_keycode = keycode
	InputMap.action_add_event(action, ke)
