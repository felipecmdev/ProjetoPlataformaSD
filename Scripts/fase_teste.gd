extends Node2D

## Ponto onde o jogador reaparece ao cair ou ao concluir (loop de teste).
@export var spawn_global_position: Vector2 = Vector2(-81, -3)
@export var spawn_peer1_offset: Vector2 = Vector2(48, 0)

@onready var _player: CharacterBody2D = $Player
@onready var _player2: CharacterBody2D = $Player2
@onready var _kill_zone: Area2D = $KillZone
@onready var _meta: Area2D = $Meta


func _ready() -> void:
	NetworkManager.register_players(_player, _player2)
	if not NetworkManager.is_online():
		_player2.visible = false
		_player2.collision_layer = 0
		_player2.collision_mask = 0
		_player2.set_physics_process(false)
	else:
		_player2.visible = true
		_player2.collision_layer = 1
		_player2.collision_mask = 1
		_player2.set_physics_process(true)
		_player.global_position = spawn_global_position
		_player2.global_position = spawn_global_position + spawn_peer1_offset
		_setup_camera_for_local_peer()

	_kill_zone.body_entered.connect(_on_kill_body_entered)
	_meta.body_entered.connect(_on_meta_body_entered)


func _physics_process(_delta: float) -> void:
	if NetworkManager.is_host():
		NetworkManager.poll_receive_host()


func _setup_camera_for_local_peer() -> void:
	var cam := _player.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	if NetworkManager.is_client():
		_player.remove_child(cam)
		_player2.add_child(cam)
		cam.position = Vector2(0, -9)


func _on_kill_body_entered(body: Node2D) -> void:
	if body.is_in_group("players"):
		_respawn(body as CharacterBody2D)


func _on_meta_body_entered(body: Node2D) -> void:
	if body.is_in_group("players"):
		print("Meta alcançada — placeholder até o multiplayer.")
		_respawn(body as CharacterBody2D)


func _respawn(p: CharacterBody2D) -> void:
	p.velocity = Vector2.ZERO
	if p == _player:
		p.global_position = spawn_global_position
	else:
		p.global_position = spawn_global_position + spawn_peer1_offset
