extends Node2D

const _BuildItems = preload("res://Scripts/build_items_config.gd")
const _UI_THEME: Theme = preload("res://themes/project_theme.tres")

## Ponto onde o jogador reaparece ao cair ou ao concluir (loop de teste).
@export var spawn_global_position: Vector2 = Vector2(-81, -3)
@export var spawn_peer_offset: Vector2 = Vector2(48, 0)
@export var player_scene: PackedScene

@onready var _kill_zone: Area2D = $KillZone
@onready var _meta: Area2D = $Meta
## Grade do chão do nível — snap de construção usa o mesmo `tile_size` e origem deste layer.
@onready var _chao: TileMapLayer = $Chao

var _overlay_layer: CanvasLayer
var _overlay_full: Control
var _overlay_center: CenterContainer
var _overlay_root: PanelContainer
var _overlay_title: Label
var _overlay_subtitle: Label
var _phase_item_preview: TextureRect
var _overlay_buttons: HBoxContainer
@export var _overlay_icon_button_size: Vector2 = Vector2(72, 72)
@export var _overlay_preview_size: Vector2 = Vector2(96, 96)
@export var _overlay_panel_pad_top: int = 22
@export var _overlay_panel_pad_bottom: int = 22
@export var _overlay_panel_pad_horizontal: int = 18
## Fallback se `$Chao` não existir (deve bater com `tile_set.tile_size` do mapa).
var _build_grid_size: float = 18.0
var _build_bounds := Rect2(-220, -120, 680, 300)

func _ready() -> void:
	NetworkManager.player_spawn_requested.connect(_spawn_player_from_signal)
	NetworkManager.game_phase_changed.connect(_on_phase_changed)
	NetworkManager.build_data_updated.connect(_refresh_overlay)
	NetworkManager.item_placed.connect(_spawn_build_item)
	_spawn_player(NetworkManager.my_player_id, spawn_global_position)
	
	var i = 1
	for client_key in NetworkManager.connected_clients.keys():
		var client_data = NetworkManager.connected_clients[client_key]
		var pos = spawn_global_position + (spawn_peer_offset * i)
		_spawn_player(client_data["id"], pos)
		i += 1
	
	_kill_zone.body_entered.connect(_on_kill_body_entered)
	_meta.body_entered.connect(_on_meta_body_entered)
	_setup_overlay()
	_spawn_existing_build_items()
	_refresh_overlay()

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
	if not body.is_in_group("players"):
		return
	var player = body as CharacterBody2D
	if player == null:
		return
	if player.player_id != NetworkManager.my_player_id:
		return
	NetworkManager.send_finish_reached()
	_respawn(player)


func _respawn(p: CharacterBody2D) -> void:
	p.velocity = Vector2.ZERO
	p.global_position = spawn_global_position

func _unhandled_input(event: InputEvent) -> void:
	if NetworkManager.current_state != NetworkManager.GameState.BUILDING:
		return
	if NetworkManager.current_builder_id != NetworkManager.my_player_id:
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	
	var item_type: String = str(NetworkManager.current_selected_items.get(NetworkManager.my_player_id, ""))
	if item_type == "":
		return
	
	var world_pos := get_global_mouse_position()
	var snapped_pos := _snap_build_position(world_pos)
	var place_pos := _placement_global_for_item(item_type, snapped_pos)
	if not _build_bounds.has_point(place_pos):
		return
	
	NetworkManager.send_item_placement(item_type, place_pos)

func _setup_overlay() -> void:
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = 10
	add_child(_overlay_layer)
	
	_overlay_full = Control.new()
	_overlay_full.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay_full.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_layer.add_child(_overlay_full)
	
	_overlay_center = CenterContainer.new()
	_overlay_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay_full.add_child(_overlay_center)
	
	_overlay_root = PanelContainer.new()
	_overlay_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay_root.theme = _UI_THEME
	_overlay_center.add_child(_overlay_root)
	
	var pad := MarginContainer.new()
	pad.add_theme_constant_override(&"margin_top", _overlay_panel_pad_top)
	pad.add_theme_constant_override(&"margin_bottom", _overlay_panel_pad_bottom)
	pad.add_theme_constant_override(&"margin_left", _overlay_panel_pad_horizontal)
	pad.add_theme_constant_override(&"margin_right", _overlay_panel_pad_horizontal)
	_overlay_root.add_child(pad)
	
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override(&"separation", 14)
	vb.custom_minimum_size = Vector2(520, 0)
	pad.add_child(vb)
	
	_overlay_title = Label.new()
	_overlay_title.text = ""
	_overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_title.add_theme_font_size_override(&"font_size", 14)
	vb.add_child(_overlay_title)
	
	_phase_item_preview = TextureRect.new()
	_phase_item_preview.visible = false
	_phase_item_preview.custom_minimum_size = _overlay_preview_size
	_phase_item_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vb.add_child(_phase_item_preview)
	
	_overlay_subtitle = Label.new()
	_overlay_subtitle.text = ""
	_overlay_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overlay_subtitle.custom_minimum_size = Vector2(480, 0)
	_overlay_subtitle.add_theme_font_size_override(&"font_size", 11)
	vb.add_child(_overlay_subtitle)
	
	_overlay_buttons = HBoxContainer.new()
	_overlay_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_overlay_buttons.add_theme_constant_override(&"separation", 12)
	vb.add_child(_overlay_buttons)

func _clear_overlay_buttons() -> void:
	for child in _overlay_buttons.get_children():
		child.queue_free()

func _refresh_overlay() -> void:
	if not is_inside_tree():
		return
	_clear_overlay_buttons()
	
	match NetworkManager.current_state:
		NetworkManager.GameState.PICKING:
			_overlay_root.visible = true
			_overlay_title.text = "Rodada %d — escolha um item" % NetworkManager.round_number
			_phase_item_preview.visible = false
			_overlay_subtitle.text = "Toque no ícone do bloco que quer adicionar."
			var opts: Array = NetworkManager.current_build_options.get(NetworkManager.my_player_id, [])
			var already_chose := NetworkManager.current_selected_items.has(NetworkManager.my_player_id)
			for item in opts:
				var id_str := str(item)
				var btn := TextureButton.new()
				btn.ignore_texture_size = true
				btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
				btn.custom_minimum_size = _overlay_icon_button_size
				btn.texture_normal = _item_atlas_texture(id_str)
				btn.tooltip_text = _BuildItems.label_for_item(id_str)
				btn.disabled = already_chose
				btn.focus_mode = Control.FOCUS_NONE
				btn.pressed.connect(_on_item_choice_pressed.bind(id_str))
				_overlay_buttons.add_child(btn)
			
			if already_chose:
				var sel := str(NetworkManager.current_selected_items[NetworkManager.my_player_id])
				_phase_item_preview.texture = _item_atlas_texture(sel)
				_phase_item_preview.visible = true
				_overlay_subtitle.text = "Você escolheu este item. Aguardando os outros jogadores…"
		
		NetworkManager.GameState.BUILDING:
			_overlay_root.visible = true
			var builder_id = NetworkManager.current_builder_id
			var builder_name = str(NetworkManager.players_data.get(builder_id, "Jogador %d" % builder_id))
			var sel_id := str(NetworkManager.current_selected_items.get(builder_id, ""))
			var sel_label: String = _BuildItems.label_for_item(sel_id)
			_overlay_title.text = "Construção — vez de %s" % builder_name
			if sel_id != "":
				_phase_item_preview.texture = _item_atlas_texture(sel_id)
				_phase_item_preview.visible = true
			else:
				_phase_item_preview.visible = false
			if builder_id == NetworkManager.my_player_id:
				_overlay_subtitle.text = "Seu turno: clique no mapa para posicionar (%s)." % sel_label
			else:
				_overlay_subtitle.text = "%s vai posicionar (%s) no mapa." % [builder_name, sel_label]
		
		_:
			_overlay_root.visible = (NetworkManager.current_state != NetworkManager.GameState.PLAYING)
			_overlay_title.text = ""
			_overlay_subtitle.text = ""
			_phase_item_preview.visible = false

func _on_item_choice_pressed(item_type: String) -> void:
	if NetworkManager.current_state != NetworkManager.GameState.PICKING:
		return
	if NetworkManager.current_selected_items.has(NetworkManager.my_player_id):
		return
	NetworkManager.send_item_selection(item_type)

func _on_phase_changed(_new_state: int) -> void:
	_refresh_overlay()
	if NetworkManager.current_state == NetworkManager.GameState.PLAYING:
		_respawn_all_players()

func _respawn_all_players() -> void:
	for id in NetworkManager.players_nodes.keys():
		var p = NetworkManager.players_nodes[id]
		if is_instance_valid(p):
			_respawn(p)

func _snap_build_position(world_pos: Vector2) -> Vector2:
	var tile_px := _get_build_tile_size()
	if _chao != null and _chao.tile_set != null:
		# Godot 4: `map_to_local(célula)` já é o CENTRO da célula — usar sempre a API do layer.
		var local := _chao.to_local(world_pos)
		var cell: Vector2i = _chao.local_to_map(local)
		var center_local: Vector2 = _chao.map_to_local(cell)
		return _chao.to_global(center_local)
	return Vector2(
		round(world_pos.x / tile_px.x) * tile_px.x,
		round(world_pos.y / tile_px.y) * tile_px.y
	)

func _get_build_tile_size() -> Vector2:
	if _chao != null and _chao.tile_set != null:
		var ts: Vector2i = _chao.tile_set.tile_size
		return Vector2(ts)
	return Vector2(_build_grid_size, _build_grid_size)

## Escada (sprite 2× altura, `Sprite2D` centrado): ancora pela base da célula clicada.
## `map_to_local` no Godot 4 devolve o *centro* da célula — não somar (tile/2, tile) de novo.
func _placement_global_for_item(item_type: String, snapped_center_global: Vector2) -> Vector2:
	if item_type != _BuildItems.ITEM_LADDER:
		return snapped_center_global
	if _chao == null or _chao.tile_set == null:
		var half := _BuildItems.region_for_item(item_type).size.y * 0.5
		return snapped_center_global + Vector2(0.0, -half + _build_grid_size * 0.5)
	var local_point := _chao.to_local(snapped_center_global)
	var cell: Vector2i = _chao.local_to_map(local_point)
	var cell_center_local: Vector2 = _chao.map_to_local(cell)
	var tile_sz := _get_build_tile_size()
	# Centro da borda inferior da célula = centro da célula + meia altura para baixo.
	var bottom_center_local: Vector2 = cell_center_local + Vector2(0.0, tile_sz.y * 0.5)
	var half_sprite: float = _BuildItems.region_for_item(item_type).size.y * 0.5
	var sprite_center_local: Vector2 = bottom_center_local + Vector2(0.0, -half_sprite)
	return _chao.to_global(sprite_center_local)

func _spawn_existing_build_items() -> void:
	for item in NetworkManager.placed_items:
		var item_type = str(item.get("type", ""))
		var pos = Vector2(float(item.get("x", 0.0)), float(item.get("y", 0.0)))
		_spawn_build_item(item_type, pos)

func _spawn_build_item(item_type: String, pos: Vector2) -> void:
	var root := Node2D.new()
	root.name = "BuildItem_%s_%d" % [item_type, randi()]
	root.global_position = pos
	var region: Rect2 = _BuildItems.region_for_item(item_type)
	
	var sprite := _create_build_sprite(item_type)
	sprite.name = "Sprite"
	root.add_child(sprite)
	
	match item_type:
		_BuildItems.ITEM_LADDER:
			# Escada: só Area2D por agora (não bloqueia passagem; lógica de escalar depois).
			var area := Area2D.new()
			var col := CollisionShape2D.new()
			var shape := RectangleShape2D.new()
			shape.size = region.size
			col.shape = shape
			area.add_child(col)
			root.add_child(area)
		_BuildItems.ITEM_SPIKE:
			var hazard := Area2D.new()
			var col_s := CollisionShape2D.new()
			var shape_s := RectangleShape2D.new()
			shape_s.size = region.size
			col_s.shape = shape_s
			hazard.add_child(col_s)
			hazard.body_entered.connect(_on_kill_body_entered)
			root.add_child(hazard)
		_BuildItems.ITEM_COIN:
			# Coletável depois (pontuação / rede); por agora só sensor passável.
			var coin_area := Area2D.new()
			var col_c := CollisionShape2D.new()
			var shape_c := RectangleShape2D.new()
			shape_c.size = region.size
			col_c.shape = shape_c
			coin_area.add_child(col_c)
			coin_area.body_entered.connect(_on_build_coin_body_entered)
			root.add_child(coin_area)
		_:
			var body := StaticBody2D.new()
			var col := CollisionShape2D.new()
			var shape := RectangleShape2D.new()
			shape.size = region.size
			col.shape = shape
			body.add_child(col)
			root.add_child(body)
	
	add_child(root)

func _on_build_coin_body_entered(body: Node2D) -> void:
	## Placeholder até haver pontuação sincronizada.
	if body.is_in_group("players"):
		pass

func _item_atlas_texture(item_id: String) -> AtlasTexture:
	var region: Rect2 = _BuildItems.region_for_item(item_id)
	var tex := AtlasTexture.new()
	tex.atlas = load(_BuildItems.ATLAS_PATH) as Texture2D
	tex.region = region
	return tex

func _create_build_sprite(item_id: String) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = _item_atlas_texture(item_id)
	s.centered = true
	return s
