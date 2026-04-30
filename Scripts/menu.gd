extends Control


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	NetworkManager.connection_approved.connect(_on_connection_approved)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_host_button_pressed() -> void:
	print("Iniciando como Host")
	NetworkManager.role = NetworkManager.Role.HOST
	NetworkManager.setup_connection()
	get_tree().change_scene_to_file("res://scenes/FaseTeste.tscn")


func _on_join_button_pressed() -> void:
	var ip_digitado = %LineEdit.text # Pega o texto do nó LineEdit
	if ip_digitado.strip_edges() == "":
		print ("Nenhum IP foi digitado. Usando IP local para teste (127.0.0.1)")
		ip_digitado = "127.0.0.1"
	
	print ("Conectando ao IP: ", ip_digitado)
	NetworkManager.role = NetworkManager.Role.CLIENT
	NetworkManager.join_address = ip_digitado
	NetworkManager.setup_connection()
	print("Aguardando Aprovação do servidor...")
	
func _on_connection_approved() -> void: # Só muda de cena quando a conexão é aprovada, 
	# senão da um caos completo e ele vira o player 1
	get_tree().change_scene_to_file("res://scenes/FaseTeste.tscn")
