extends Control

@onready var player_list = $MarginContainer/SplitVertical/SplitHorizontal/LadoDireito/PlayerList
@onready var slot_template = $MarginContainer/SplitVertical/SplitHorizontal/LadoDireito/PlayerList/PlayerSlot1
@onready var button_start = $MarginContainer/SplitVertical/SplitHorizontal/LadoDireito/ButtonStart
var pronto: bool = false

func _ready() -> void:
	slot_template.hide()
	if NetworkManager.is_host():
		button_start.text = "Iniciar"
	
	else:
		button_start.text = "Pronto"
		
	NetworkManager.lobby_players_updated.connect(atualizar_lista_jogadores)
	atualizar_lista_jogadores()

func atualizar_lista_jogadores() -> void:
	for filho in player_list.get_children():
		if filho != slot_template:
			filho.queue_free()
	
	for id in NetworkManager.players_data.keys():
		_criar_slot_na_tela(id, NetworkManager.players_data[id])

func _criar_slot_na_tela(id_jogador: int, nome_jogador: String) -> void:
	var novo_slot = slot_template.duplicate()
	novo_slot.show()
	var label_nome = novo_slot.get_node("HBoxContainer/PlayerName")
	label_nome.text = nome_jogador
	
	var check_ready = novo_slot.get_node("HBoxContainer/ReadyCheck")
	check_ready.button_pressed = NetworkManager.players_ready.get(id_jogador, false)
	
	if id_jogador == 0:
		check_ready.hide()
	# TODO: Colocar a skin correta aqui, agora é só uma imagem estática da skin padrão
	
	player_list.add_child(novo_slot)


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
