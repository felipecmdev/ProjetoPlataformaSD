extends Node2D

## Ponto onde o jogador reaparece ao cair ou ao concluir (loop de teste).
@export var spawn_global_position: Vector2 = Vector2(-81, -3)
@export var spawn_peer_offset: Vector2 = Vector2(48, 0)
@export var player_scene: PackedScene

@onready var _kill_zone: Area2D = $KillZone
@onready var _meta: Area2D = $Meta

func _ready() -> void:
	NetworkManager.player_spawn_requested.connect(_spawn_player_from_signal)
	_spawn_player(NetworkManager.my_player_id, spawn_global_position)
	
	var i = 1
	for client_key in NetworkManager.connected_clients.keys():
		var client_data = NetworkManager.connected_clients[client_key]
		var pos = spawn_global_position + (spawn_peer_offset * i)
		_spawn_player(client_data["id"], pos)
		i += 1
	
	_kill_zone.body_entered.connect(_on_kill_body_entered)
	_meta.body_entered.connect(_on_meta_body_entered)

func _spawn_player(id: int, pos: Vector2) -> void:
	if player_scene == null:
		return
	
	var novo_jogador = player_scene.instantiate() as CharacterBody2D
	novo_jogador.global_position = pos
	novo_jogador.player_id = id
	
	# Aplica nome conhecido no momento do spawn (evita ficar "nome" até chegar pacote N|...).
	# O próprio jogador local já se esconde no `set_player_name`.
	if novo_jogador.has_method("set_player_name"):
		var nome: String = str(NetworkManager.players_data.get(id, ""))
		if nome != "":
			novo_jogador.set_player_name(nome)
	
	# Aplica skin conhecida no momento do spawn.
	if novo_jogador.has_method("set_skin"):
		var skin: String = str(NetworkManager.players_skin.get(id, "Azul"))
		if skin != "":
			novo_jogador.set_skin(skin)
	
	add_child(novo_jogador)
	NetworkManager.register_player_node(id, novo_jogador)
	
	if id == NetworkManager.my_player_id:
		var camera = Camera2D.new()
		camera.position = Vector2(0, -9)
		camera.zoom = Vector2(2.5, 2.5)
		novo_jogador.add_child(camera)

func _spawn_player_from_signal(id: int) -> void:
	if not NetworkManager.players_nodes.has(id):
		_spawn_player(id, spawn_global_position)

func _on_kill_body_entered(body: Node2D) -> void:
	if body.is_in_group("players"):
		_respawn(body as CharacterBody2D)


func _on_meta_body_entered(body: Node2D) -> void:
	if body.is_in_group("players"):
		print("Meta alcançada — placeholder até o multiplayer.")
		_respawn(body as CharacterBody2D)


func _respawn(p: CharacterBody2D) -> void:
	p.velocity = Vector2.ZERO
	p.global_position = spawn_global_position
