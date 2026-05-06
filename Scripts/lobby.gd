extends Control

@onready var player_list = $MarginContainer/SplitVertical/SplitHorizontal/LadoDireito/PlayerList
@onready var slot_template = $MarginContainer/SplitVertical/SplitHorizontal/LadoDireito/PlayerList/PlayerSlot1
@onready var button_start = $MarginContainer/SplitVertical/SplitHorizontal/LadoDireito/ButtonStart
@onready var skins_bar = $MarginContainer/SplitVertical/Skins
@onready var btn_skin_verde: TextureButton = $MarginContainer/SplitVertical/Skins/SkinVerde
@onready var btn_skin_amarelo: TextureButton = $MarginContainer/SplitVertical/Skins/SkinAmarelo
@onready var btn_skin_rosa: TextureButton = $MarginContainer/SplitVertical/Skins/SkinRosa
@onready var btn_skin_azul: TextureButton = $MarginContainer/SplitVertical/Skins/SkinAzul
@onready var btn_skin_laranja: TextureButton = $MarginContainer/SplitVertical/Skins/SkinLaranja
var pronto: bool = false
var _skin_botoes: Dictionary = {}

func _ready() -> void:
	slot_template.hide()
	if NetworkManager.is_host():
		button_start.text = "Iniciar"
	
	else:
		button_start.text = "Pronto"
		
	NetworkManager.lobby_players_updated.connect(_on_lobby_players_updated)
	_setup_skin_buttons()
	_update_skin_buttons_visual()
	atualizar_lista_jogadores()

func _on_lobby_players_updated() -> void:
	atualizar_lista_jogadores()
	_update_skin_buttons_visual()

func _setup_skin_buttons() -> void:
	_skin_botoes = {
		"Verde": btn_skin_verde,
		"Amarelo": btn_skin_amarelo,
		"Rosa": btn_skin_rosa,
		"Azul": btn_skin_azul,
		"Laranja": btn_skin_laranja,
	}
	
	for skin in _skin_botoes.keys():
		var btn: TextureButton = _skin_botoes[skin]
		if btn != null and not btn.pressed.is_connected(_on_skin_pressed):
			btn.pressed.connect(_on_skin_pressed.bind(skin))

func _on_skin_pressed(skin: String) -> void:
	NetworkManager.send_skin_state(skin)
	_update_skin_buttons_visual()

func _update_skin_buttons_visual() -> void:
	var atual: String = str(NetworkManager.players_skin.get(NetworkManager.my_player_id, NetworkManager.my_skin_name))
	for skin in _skin_botoes.keys():
		var btn: TextureButton = _skin_botoes[skin]
		if btn == null:
			continue
		btn.modulate = Color(1, 1, 1, 1) if skin == atual else Color(1, 1, 1, 0.45)

func atualizar_lista_jogadores() -> void:
	for filho in player_list.get_children():
		if filho != slot_template:
			filho.queue_free()
	
	for id in NetworkManager.players_data.keys():
		_criar_slot_na_tela(id, NetworkManager.players_data[id])
	
	# Garante que o destaque do botão de skin não “atrase” em updates recebidos da rede.
	_update_skin_buttons_visual()

func _criar_slot_na_tela(id_jogador: int, nome_jogador: String) -> void:
	var novo_slot = slot_template.duplicate()
	novo_slot.show()
	var label_nome = novo_slot.get_node("HBoxContainer/PlayerName")
	label_nome.text = nome_jogador
	
	var check_ready = novo_slot.get_node("HBoxContainer/ReadyCheck")
	check_ready.button_pressed = NetworkManager.players_ready.get(id_jogador, false)
	
	if id_jogador == 0:
		check_ready.hide()
	
	# Mostra a skin escolhida no ícone do slot (usando o atlas da cena).
	var skin_icon = novo_slot.get_node("HBoxContainer/SkinFrame/SkinIcon") as TextureRect
	if skin_icon != null:
		var skin: String = str(NetworkManager.players_skin.get(id_jogador, "Azul"))
		_apply_skin_to_slot_icon(skin_icon, skin)
	
	player_list.add_child(novo_slot)

func _apply_skin_to_slot_icon(icon: TextureRect, skin: String) -> void:
	# Reaproveita o mesmo spritesheet do lobby.
	var atlas: Texture2D = load("res://assets/sprites/tilemap-characters_packed.png")
	var tex := AtlasTexture.new()
	tex.atlas = atlas
	
	match skin:
		"Verde":
			tex.region = Rect2(0, 0, 24, 24)
		"Azul":
			tex.region = Rect2(48, 0, 24, 24)
		"Rosa":
			tex.region = Rect2(96, 0, 24, 24)
		"Amarelo":
			tex.region = Rect2(144, 0, 24, 24)
		"Laranja":
			tex.region = Rect2(0, 24, 24, 24)
		_:
			tex.region = Rect2(48, 0, 24, 24)
	
	icon.texture = tex


func _on_button_start_pressed() -> void:
	if NetworkManager.is_host():
		var todos_prontos := true
		for id in NetworkManager.players_data.keys():
			if (id != NetworkManager.my_player_id 
			and not NetworkManager.players_ready.get(id, false)):
				todos_prontos = false
				break
		
		if todos_prontos:
			print ("Todos prontos! Iniciando partida...")
			NetworkManager.start_game_host()
			
		else:
			# TODO transformar isso em um ErrorLabel igual o do Menu ao invés de ser um print
			print ("Alguém não está pronto")
	
	else:
		pronto = !pronto
		if pronto:
			button_start.text = "Cancelar"
		else:
			button_start.text = "Pronto"
			
		NetworkManager.send_ready_state(pronto)
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
