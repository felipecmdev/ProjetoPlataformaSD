extends CharacterBody2D

const SPEED = 130.0
const JUMP_VELOCITY = -300.0

var player_id: int = -1

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")


func _ready() -> void:
	add_to_group("players")
	_ensure_gameplay_actions()


func _physics_process(delta: float) -> void:
	if not NetworkManager.is_online():
		return

	if not is_on_floor():
		velocity.y += gravity * delta

	if player_id == NetworkManager.my_player_id:
		_handle_local_input()
		
	elif NetworkManager.is_host() and NetworkManager.clients_input.has(player_id):
		_handle_network_input()
	
	else:
		pass
		
	if NetworkManager.is_host() or player_id == NetworkManager.my_player_id:
		_push_other_player()
		move_and_slide()
	
	if velocity.x != 0:
		$AnimatedSprite2D.flip_h = !(velocity.x < 0)

func _handle_local_input() -> void:
	if Input.is_action_just_pressed(&"jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	
	var direction := Input.get_axis(&"move_left", &"move_right")
	if direction:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		
func _handle_network_input() -> void:
	var input_remoto = NetworkManager.clients_input[player_id]
	
	if input_remoto["jump"] and is_on_floor():
		velocity.y = JUMP_VELOCITY
		input_remoto["jump"] = false #reseta o pulo pra não sair voando
	
	var direction = input_remoto["move_x"]
	if direction:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

func _push_other_player() -> void:
	var others := get_tree().get_nodes_in_group("players")
	for other in others:
		if other == self:
			continue
		var diff: Vector2 = other.global_position - global_position
		if diff.length() < 16.1:
			var push_dir := signf(diff.x)
			if push_dir == 0:
				push_dir = 1.0
			other.velocity.x += push_dir * 140.0  #força da empurrada

func _ensure_gameplay_actions() -> void:
	_add_key_to_action(&"move_left", KEY_A)
	_add_key_to_action(&"move_left", KEY_LEFT)
	_add_key_to_action(&"move_right", KEY_D)
	_add_key_to_action(&"move_right", KEY_RIGHT)
	_add_key_to_action(&"jump", KEY_SPACE)
	_add_key_to_action(&"jump", KEY_W)
	_add_key_to_action(&"jump", KEY_UP)


func _add_key_to_action(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and ev.physical_keycode == keycode:
			return
	var ke := InputEventKey.new()
	ke.physical_keycode = keycode
	InputMap.action_add_event(action, ke)
