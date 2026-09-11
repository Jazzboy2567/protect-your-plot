extends Node2D

# Game flow, economy, shop/deploy/battle UI, spawning, and the win/lose loop.
# You are the landowner: hire with gold, deploy peasants (box-select + move),
# then watch them auto-battle the incoming wave.

enum Phase { SHOP, GUILD, DEPLOY, BATTLE, GAMEOVER, WIN }

const ARENA := Vector2(1152, 648)
const START_GOLD := 70
const MAX_BATTLES := 12
const START_ARMY := ["peasant", "peasant", "peasant", "peasant"]
const FENCE_X := 357.0

# Peasants join free (capped); specialists cost gold (capped); buildings cost gold.
const PEASANT_IDS := ["peasant"]
const SPECIALIST_IDS := ["archer", "woodcutter", "hunter", "herbalist", "fisherman", "torchbearer", "baker", "monk"]
const BUILDING_IDS := ["barricade", "spikes", "palisade", "stone_wall", "church"]
const GUILD_NAMES := {
	"archer": "Archers' Guild", "woodcutter": "Woodsmen", "hunter": "Hunters' Lodge",
	"herbalist": "Apothecary", "fisherman": "Wharf", "torchbearer": "Wharf",
	"baker": "Bakers' Row", "monk": "Abbey",
}
const RECRUIT_CAP := 3
const MAX_CONTRACTS := 4

# Tile grid over your (left) side. Buildings snap to tiles; the castle is 3x3.
const TILE := 36.0
const GRID_COLS := 10
const GRID_ROWS := 18
const CASTLE_GX := 2
const CASTLE_GY := 7
const CASTLE_SPAN := 3

# Run-wide passive upgrades (buy once, from the Traveling Merchant every 4th battle).
const RELIC_DEFS := {
	"sharp_tools":      {"name": "Sharpened Tools (+25% dmg)", "cost": 60},
	"village_bell":     {"name": "Village Bell (+20% atk spd)", "cost": 60},
	"blacksmith_forge": {"name": "Blacksmith's Forge (+3 armor)", "cost": 55},
	"full_granary":     {"name": "Full Granary (+2 free peasants)", "cost": 50},
	"fortifier":        {"name": "Fortifier (walls +80% HP)", "cost": 45},
	"longbows":         {"name": "Longbows (archers +range/dmg)", "cost": 45},
	"shields":          {"name": "Shields (peasants +2 armor)", "cost": 40},
	"sharpened_axes":   {"name": "Sharpened Axes (woodcutter +8)", "cost": 40},
	"keen_edge":        {"name": "Keen Edge (+15% crit)", "cost": 55},
	"warhorn":          {"name": "War Horn (+15% atk speed)", "cost": 50},
	"swift_boots":      {"name": "Swift Boots (+20% move speed)", "cost": 40},
	"iron_rations":     {"name": "Iron Rations (+25% max HP)", "cost": 50},
	"hawk_eye":         {"name": "Hawk Eye (ranged +30 range)", "cost": 45},
	"berserkers_brew":  {"name": "Berserker's Brew (+40% dmg, -15% HP)", "cost": 55},
}
const STRUCT_ITEMS := ["barricade", "spikes", "palisade", "stone_wall"]

var gold: int = START_GOLD
var battle_num: int = 1
var army: Array = START_ARMY.duplicate()
var phase: int = Phase.SHOP
var info_text: String = ""

var rally_cd: float = 0.0
var rally_time: float = 0.0

var relics: Array = []
var contracts: Array = []      # specialist ids you've signed (max 4); only these are hireable
var guild_offer: Array = []    # the specialist contracts on offer this interlude
var peasant_recruits: int = RECRUIT_CAP
var specialist_recruits: int = RECRUIT_CAP
var dead_this_battle: Array = []
var buildings: Array = []          # persistent placed buildings: {id, gx, gy}
var _build_sel: String = ""        # building id selected for placement ("" = command mode)

var peasants: Array = []
var enemies: Array = []

var world: Node2D
var hud: CanvasLayer
var top_label: Label
var panel: Control
var rally_btn: Button
var banner: Label
var ctrl_speed: Button
var ctrl_full: Button
var _speed_i: int = 0
const SPEEDS := [1.0, 2.0, 3.0]

# RTS selection state
var _press_pos: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _sel_rect: Rect2 = Rect2()

func _ready() -> void:
	world = Node2D.new()
	add_child(world)

	hud = CanvasLayer.new()
	add_child(hud)

	top_label = Label.new()
	top_label.position = Vector2(16, 10)
	top_label.add_theme_font_size_override("font_size", 20)
	top_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(top_label)

	panel = Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(panel)

	banner = Label.new()
	banner.add_theme_font_size_override("font_size", 48)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.size = Vector2(ARENA.x, 60)
	banner.position = Vector2(0, ARENA.y * 0.30)
	banner.modulate = Color(1, 1, 1, 0)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(banner)

	# Persistent top-right controls (survive panel rebuilds).
	ctrl_speed = Button.new()
	ctrl_speed.text = "Speed x1"
	ctrl_speed.position = Vector2(ARENA.x - 250, 10)
	ctrl_speed.size = Vector2(110, 30)
	ctrl_speed.pressed.connect(_cycle_speed)
	hud.add_child(ctrl_speed)

	ctrl_full = Button.new()
	ctrl_full.text = "Fullscreen"
	ctrl_full.position = Vector2(ARENA.x - 132, 10)
	ctrl_full.size = Vector2(122, 30)
	ctrl_full.pressed.connect(_toggle_fullscreen)
	hud.add_child(ctrl_full)

	buildings = [{"id": "castle", "gx": CASTLE_GX, "gy": CASTLE_GY}, {"id": "church", "gx": 1, "gy": 8}]
	show_shop()

func is_fighting() -> bool:
	return phase == Phase.BATTLE

func _cycle_speed() -> void:
	_speed_i = (_speed_i + 1) % SPEEDS.size()
	Engine.time_scale = SPEEDS[_speed_i]
	ctrl_speed.text = "Speed x%d" % int(SPEEDS[_speed_i])

func _toggle_fullscreen() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

# ---------------------------------------------------------------- flow

# Council entry point. Every 4th battle you get the Guild -> Shop interlude;
# other rounds go straight to a light pre-deploy screen (no new recruits).
func show_shop() -> void:
	_despawn_all()
	if army.is_empty():
		army.append("peasant")
		army.append("peasant")
		info_text = "Your land lies empty — 2 peasants volunteer."
	if is_interlude():
		peasant_recruits = RECRUIT_CAP
		specialist_recruits = RECRUIT_CAP
		guild_offer = _make_guild_offer()
		open_guild()
	else:
		open_predeploy()

func is_interlude() -> bool:
	return (battle_num - 1) % 4 == 0   # battles 1, 5, 9

func _make_guild_offer() -> Array:
	var pool: Array = []
	for id in SPECIALIST_IDS:
		if not (id in contracts):
			pool.append(id)
	pool.shuffle()
	return pool.slice(0, mini(3, pool.size()))

func open_guild() -> void:
	phase = Phase.GUILD
	_build_guild_ui()
	flash_banner("A guild offers a contract!", Color(1, 0.85, 0.4))
	_update_top()

func open_shop() -> void:
	phase = Phase.SHOP
	_build_shop_ui()
	_update_top()

func open_predeploy() -> void:
	phase = Phase.SHOP
	_build_predeploy_ui()
	_update_top()

func _sign_contract(id: String) -> void:
	if contracts.size() < MAX_CONTRACTS and not (id in contracts):
		contracts.append(id)
		info_text = "Signed with the %s — you can now hire them." % GameData.UNITS[id]["name"]
	guild_offer = []
	open_shop()

func start_deploy() -> void:
	phase = Phase.DEPLOY
	_build_sel = ""
	_despawn_all()
	_spawn_buildings()
	_spawn_peasants()
	_spawn_enemies()
	_build_deploy_ui()
	if battle_num % 4 == 0:
		flash_banner("The Black Death approaches!", Color(0.9, 0.4, 0.9))
	_update_top()

func begin_fight() -> void:
	phase = Phase.BATTLE
	dead_this_battle.clear()
	_build_battle_ui()
	_update_top()

func _win_battle() -> void:
	phase = Phase.SHOP
	var survivors := peasants.size()
	var tax := 10 + 2 * survivors
	gold += tax
	info_text = "Victory! Tax +%dg. Survivors: %d" % [tax, survivors]
	flash_banner("Battle %d won!  +%dg" % [battle_num, tax], Color(0.5, 0.95, 0.5))

	# Persist survivors into the roster; dead peasants are lost.
	var new_army: Array = []
	for p in peasants:
		new_army.append(p.type_id)
	army = new_army

	# A surviving Church revives one fallen unit for the next battle.
	if _has_building("church") and not dead_this_battle.is_empty():
		var revived: String = dead_this_battle[0]
		army.append(revived)
		info_text += "  The church revives a %s." % GameData.UNITS[revived]["name"]

	battle_num += 1
	if battle_num > MAX_BATTLES:
		_win_game()
	else:
		show_shop()

func _lose_battle() -> void:
	phase = Phase.GAMEOVER
	_clear_panel()
	var lbl := Label.new()
	lbl.text = "Your plot has fallen.\nYou held until Battle %d." % battle_num
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector2(ARENA.x / 2.0 - 160.0, 210.0)
	lbl.size = Vector2(320, 80)
	lbl.add_theme_font_size_override("font_size", 26)
	panel.add_child(lbl)
	_mk_button("Try Again", Vector2(ARENA.x / 2.0 - 80.0, 310.0), Vector2(160, 44), _restart)
	_update_top()

func _win_game() -> void:
	phase = Phase.WIN
	_clear_panel()
	var lbl := Label.new()
	lbl.text = "The realm is safe!\nYour plot endures. You win."
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector2(ARENA.x / 2.0 - 160.0, 210.0)
	lbl.size = Vector2(320, 80)
	lbl.add_theme_font_size_override("font_size", 26)
	panel.add_child(lbl)
	_mk_button("Play Again", Vector2(ARENA.x / 2.0 - 80.0, 310.0), Vector2(160, 44), _restart)
	_update_top()

func _restart() -> void:
	gold = START_GOLD
	battle_num = 1
	army = START_ARMY.duplicate()
	rally_cd = 0.0
	rally_time = 0.0
	relics = []
	contracts = []
	guild_offer = []
	peasant_recruits = RECRUIT_CAP
	specialist_recruits = RECRUIT_CAP
	dead_this_battle = []
	buildings = [{"id": "castle", "gx": CASTLE_GX, "gy": CASTLE_GY}, {"id": "church", "gx": 1, "gy": 8}]
	_build_sel = ""
	info_text = ""
	show_shop()

# ---------------------------------------------------------------- spawning

func _spawn_peasants() -> void:
	var fight_i := 0
	for id in army:
		if GameData.UNITS[id].get("structure", false):
			continue   # structures are placed on tiles, not spawned from the roster
		var u := _make_unit(id, 0)
		var col := fight_i / 8
		var row := fight_i % 8
		u.position = Vector2(215 + col * 34 + randf_range(-6, 6), 120 + row * 52 + randf_range(-8, 8))
		fight_i += 1
		u.command_point = u.position
		_apply_relics(u)
		world.add_child(u)
		peasants.append(u)

	# Full Granary relic: extra free peasants each deploy.
	if "full_granary" in relics:
		for k in 2:
			var f := _make_unit("peasant", 0)
			f.position = Vector2(40 + randf_range(-6, 6), 300 + k * 50)
			f.command_point = f.position
			_apply_relics(f)
			world.add_child(f)
			peasants.append(f)

func _apply_relics(u: Unit) -> void:
	for r in relics:
		match r:
			"sharp_tools":
				u.damage *= 1.25
			"village_bell":
				u.attack_cooldown /= 1.2
			"blacksmith_forge":
				if not u.is_structure:
					u.armor += 3
			"rat_charm":
				u.plague_immune = true
			"fortifier":
				if u.is_structure:
					u.max_hp *= 1.8
					u.hp = u.max_hp
			"longbows":
				if u.type_id == "archer":
					u.attack_range += 40
					u.damage += 3
			"shields":
				if u.type_id == "peasant":
					u.armor += 2
			"sharpened_axes":
				if u.type_id == "woodcutter":
					u.damage += 8
			"keen_edge":
				u.crit_chance += 0.15
			"warhorn":
				u.attack_cooldown /= 1.15
			"swift_boots":
				if not u.is_structure:
					u.move_speed *= 1.2
			"iron_rations":
				u.max_hp *= 1.25
				u.hp = u.max_hp
			"hawk_eye":
				if u.attack_range >= 100.0:
					u.attack_range += 30
			"berserkers_brew":
				u.damage *= 1.4
				u.max_hp *= 0.85
				u.hp = u.max_hp

func _spawn_enemies() -> void:
	var wave := GameData.generate_wave(battle_num)
	var i := 0
	for id in wave:
		var u := _make_unit(id, 1)
		var col := i / 10
		var row := i % 10
		u.position = Vector2(1040 - col * 36 + randf_range(-6, 6), 110 + row * 46 + randf_range(-8, 8))
		u.command_point = u.position
		world.add_child(u)
		enemies.append(u)
		i += 1

func _make_unit(id: String, team: int) -> Unit:
	var u := Unit.new()
	u.setup(GameData.UNITS[id], team, self)
	return u

func _spawn_buildings() -> void:
	for b in buildings:
		var u := _make_unit(b["id"], 0)
		u.position = _building_center(b)
		u.command_point = u.position
		u.set_meta("bref", b)
		_apply_relics(u)
		world.add_child(u)
		peasants.append(u)

func _building_center(b: Dictionary) -> Vector2:
	if b["id"] == "castle":
		return Vector2((b["gx"] + CASTLE_SPAN / 2.0) * TILE, (b["gy"] + CASTLE_SPAN / 2.0) * TILE)
	return Vector2((b["gx"] + 0.5) * TILE, (b["gy"] + 0.5) * TILE)

func _tile_occupied(gx: int, gy: int) -> bool:
	for b in buildings:
		if b["id"] == "castle":
			if gx >= b["gx"] and gx < b["gx"] + CASTLE_SPAN and gy >= b["gy"] and gy < b["gy"] + CASTLE_SPAN:
				return true
		elif b["gx"] == gx and b["gy"] == gy:
			return true
	return false

func _has_building(id: String) -> bool:
	for b in buildings:
		if b["id"] == id:
			return true
	return false

func _place_building(pos: Vector2) -> void:
	var gx := int(pos.x / TILE)
	var gy := int(pos.y / TILE)
	if gx < 0 or gx >= GRID_COLS or gy < 0 or gy >= GRID_ROWS:
		info_text = "Build on your own tiles (left side)."
		_update_top()
		return
	if _tile_occupied(gx, gy):
		info_text = "That tile is occupied."
		_update_top()
		return
	var cost: int = GameData.UNITS[_build_sel]["cost"]
	if gold < cost:
		info_text = "Not enough gold for that building."
		_update_top()
		return
	gold -= cost
	var b := {"id": _build_sel, "gx": gx, "gy": gy}
	buildings.append(b)
	var u := _make_unit(_build_sel, 0)
	u.position = _building_center(b)
	u.command_point = u.position
	u.set_meta("bref", b)
	_apply_relics(u)
	world.add_child(u)
	peasants.append(u)
	_build_deploy_ui()
	_update_top()
	queue_redraw()

# Nearest wall directly in an advancing enemy's path (so a wall line blocks it).
func structure_ahead(u: Unit):
	var best = null
	var best_d := 56.0
	for p in peasants:
		if not is_instance_valid(p) or not p.is_structure or p.hp <= 0.0:
			continue
		var dx: float = u.global_position.x - p.global_position.x   # >0: wall is to the left (ahead)
		var dy: float = absf(u.global_position.y - p.global_position.y)
		if dx > -8.0 and dy < p.radius + 12.0:
			var d: float = u.global_position.distance_to(p.global_position)
			if d < best_d:
				best_d = d
				best = p
	return best

func _despawn_all() -> void:
	for c in world.get_children():
		c.queue_free()
	peasants.clear()
	enemies.clear()

# ---------------------------------------------------------------- combat queries

func get_nearest_enemy(u: Unit):
	# Prefer living units; enemies fall back to structures when no units remain.
	var pool: Array = enemies if u.team == 0 else peasants
	var best = null
	var best_d := INF
	for e in pool:
		if not is_instance_valid(e) or e.hp <= 0.0 or e.is_structure:
			continue
		var d: float = u.global_position.distance_squared_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	if best == null and u.team == 1:
		best = get_nearest_structure(u)
	return best

func get_nearest_structure(u: Unit):
	var best = null
	var best_d := INF
	for p in peasants:
		if not is_instance_valid(p) or not p.is_structure or p.hp <= 0.0:
			continue
		var d: float = u.global_position.distance_squared_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best

func get_heal_target(u: Unit):
	# Most-hurt living non-structure ally within the healer's range.
	var best = null
	var best_frac := 1.0
	for a in peasants:
		if a == u or not is_instance_valid(a) or a.is_structure or a.hp <= 0.0:
			continue
		if a.hp >= a.max_hp:
			continue
		if u.global_position.distance_to(a.global_position) > u.attack_range + a.radius + u.radius:
			continue
		var frac: float = a.hp / a.max_hp
		if frac < best_frac:
			best_frac = frac
			best = a
	return best

func get_allies(u: Unit) -> Array:
	return peasants if u.team == 0 else enemies

func get_backline_peasant():
	var best = null
	var best_x := INF
	for p in peasants:
		if not is_instance_valid(p) or p.hp <= 0.0 or p.is_structure:
			continue
		if p.global_position.x < best_x:
			best_x = p.global_position.x
			best = p
	return best

func try_spread_plague(u: Unit) -> void:
	for a in get_allies(u):
		if a == u or not is_instance_valid(a) or a.is_structure or a.plague_immune or a.plague_time > 0.0:
			continue
		if u.global_position.distance_to(a.global_position) < 34.0:
			a.infect(u.plague_dps, 4.0)
			return

func damage_mult(team: int) -> float:
	return 1.6 if (team == 0 and rally_time > 0.0) else 1.0

func on_unit_died(u: Unit) -> void:
	if u.team == 1 and phase == Phase.BATTLE:
		gold += u.gold_drop
	elif u.team == 0 and phase == Phase.BATTLE and not u.is_structure:
		dead_this_battle.append(u.type_id)
	if u.team == 0 and u.is_structure and u.has_meta("bref"):
		buildings.erase(u.get_meta("bref"))   # destroyed buildings don't persist
	peasants.erase(u)
	enemies.erase(u)
	if phase != Phase.BATTLE:
		return
	if u.type_id == "castle":
		_lose_battle()   # the keep has fallen
		return
	if enemies.is_empty():
		_win_battle()
	elif peasants.is_empty():
		_lose_battle()

# ------------------------------------------------ RTS selection & commands

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F11:
		_toggle_fullscreen()
		return
	if phase != Phase.DEPLOY:   # positioning happens in Deploy only; battle is watch-only
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_pos = event.position
			_dragging = false
		else:
			if _dragging:
				_select_in_rect(Rect2(_press_pos, event.position - _press_pos).abs())
				_dragging = false
				queue_redraw()
			else:
				_handle_click(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_command_selected_to(event.position)   # right-click also moves (desktop)
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		if event.position.distance_to(_press_pos) > 8.0:
			_dragging = true
		if _dragging:
			_sel_rect = Rect2(_press_pos, event.position - _press_pos).abs()
			queue_redraw()

func _handle_click(pos: Vector2) -> void:
	if _build_sel != "" and phase == Phase.DEPLOY:
		_place_building(pos)
		return
	var u = _peasant_at(pos)
	if u != null:
		_clear_selection()
		u.selected = true
		u.queue_redraw()
	elif _has_selection():
		_command_selected_to(pos)
	else:
		_clear_selection()

func _command_selected_to(pos: Vector2) -> void:
	var sel: Array = []
	for p in peasants:
		if is_instance_valid(p) and p.selected and not p.is_structure:
			sel.append(p)
	if sel.is_empty():
		return
	var cp := pos
	# During deploy, keep units on your own side; they may advance once fighting.
	var max_x := (FENCE_X - 12.0) if phase == Phase.DEPLOY else 880.0
	cp.x = clampf(cp.x, 24.0, max_x)
	cp.y = clampf(cp.y, 24.0, ARENA.y - 20.0)
	var i := 0
	for p in sel:
		var ox := float((i % 6) * 22 - 55)
		var oy := float((i / 6) * 22)
		var pt := cp + Vector2(ox, oy)
		p.command_point = pt
		if phase == Phase.DEPLOY:
			p.global_position = pt
		p.queue_redraw()
		i += 1

func _select_in_rect(r: Rect2) -> void:
	# A tiny rect (a stray click read as a drag) selects nothing extra.
	for p in peasants:
		if not is_instance_valid(p):
			continue
		var s: bool = (not p.is_structure) and r.has_point(p.global_position)
		if p.selected != s:
			p.selected = s
			p.queue_redraw()

func _clear_selection() -> void:
	for p in peasants:
		if is_instance_valid(p) and p.selected:
			p.selected = false
			p.queue_redraw()

func _has_selection() -> bool:
	for p in peasants:
		if is_instance_valid(p) and p.selected:
			return true
	return false

func _peasant_at(pos: Vector2):
	var best = null
	var best_d := 22.0 * 22.0
	for p in peasants:
		if not is_instance_valid(p) or p.is_structure:
			continue
		var d: float = p.global_position.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = p
	return best

# ---------------------------------------------------------------- UI

# A dark full-screen backdrop behind a modal (blocks the field, hides bleed-through).
func _add_backdrop() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.05, 0.62)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(bg)

func _card_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.95, 0.92, 0.83)
	s.border_color = Color(0.70, 0.64, 0.47)
	s.set_border_width_all(1)
	s.set_corner_radius_all(5)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	return s

func _stat_row(label_text: String, value_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var a := Label.new()
	a.text = label_text
	a.add_theme_color_override("font_color", Color(0.42, 0.39, 0.32))
	a.add_theme_font_size_override("font_size", 13)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b := Label.new()
	b.text = value_text
	b.add_theme_color_override("font_color", Color(0.16, 0.14, 0.11))
	b.add_theme_font_size_override("font_size", 13)
	row.add_child(a)
	row.add_child(sp)
	row.add_child(b)
	return row

func _guild_card(id: String) -> Control:
	var d: Dictionary = GameData.UNITS[id]
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _card_style())
	pc.custom_minimum_size = Vector2(214, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	pc.add_child(v)
	var gl := Label.new()
	gl.text = str(GUILD_NAMES.get(id, "Guild")).to_upper()
	gl.add_theme_color_override("font_color", Color(0.62, 0.45, 0.10))
	gl.add_theme_font_size_override("font_size", 11)
	v.add_child(gl)
	var nm := Label.new()
	nm.text = d["name"]
	nm.add_theme_color_override("font_color", Color(0.14, 0.12, 0.09))
	nm.add_theme_font_size_override("font_size", 20)
	v.add_child(nm)
	var rng := float(d.get("range", 6))
	v.add_child(_stat_row("Health", str(int(d["hp"]))))
	v.add_child(_stat_row("Damage", str(int(d["damage"]))))
	v.add_child(_stat_row("Atk speed", "%.1f / s" % (1.0 / float(d.get("cooldown", 1.0)))))
	v.add_child(_stat_row("Range", "melee" if rng <= 12.0 else str(int(rng))))
	v.add_child(_stat_row("Cost", "%dg" % int(d["cost"])))
	var btn := Button.new()
	btn.text = "Sign Contract"
	btn.pressed.connect(func(): _sign_contract(id))
	v.add_child(btn)
	return pc

# The Guild page: a centered modal — sign one free contract to unlock a specialist.
func _build_guild_ui() -> void:
	_clear_panel()
	top_label.visible = false
	_add_backdrop()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)

	var head := Label.new()
	head.text = "Guild Contract   ·   Choose one (free)   ·   Contracts %d/%d   ·   Gold %d" % [contracts.size(), MAX_CONTRACTS, gold]
	head.add_theme_font_size_override("font_size", 22)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(head)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(row)
	if contracts.size() >= MAX_CONTRACTS or guild_offer.is_empty():
		var l := Label.new()
		l.text = "All contract slots are full." if contracts.size() >= MAX_CONTRACTS else "No guilds are visiting this round."
		row.add_child(l)
	else:
		for id in guild_offer:
			row.add_child(_guild_card(id))

	var cont := Button.new()
	cont.text = "Continue to Shop  >>"
	cont.custom_minimum_size = Vector2(240, 40)
	cont.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cont.pressed.connect(open_shop)
	col.add_child(cont)

# The Shop + Recruit page (interlude): recruit peasants, hire contracted
# specialists, buy relics, then deploy.
func _build_shop_ui() -> void:
	_clear_panel()
	top_label.visible = false
	_add_backdrop()
	_shop_header("Shop & Recruit  ·  Gold %d  ·  Battle %d/%d" % [gold, battle_num, MAX_BATTLES], 24, 20)
	var x := 24.0
	var y := 64.0
	_shop_header("Recruit", x, y)
	y += 32
	var pb := _mk_button("Call Peasant (free) — %d left" % peasant_recruits, Vector2(x, y), Vector2(264, 26), func(): _buy("peasant"))
	pb.disabled = peasant_recruits <= 0
	y += 32
	if contracts.is_empty():
		var l := Label.new()
		l.text = "Sign guild contracts to hire specialists."
		l.position = Vector2(x, y)
		l.add_theme_font_size_override("font_size", 13)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(l)
		y += 28
	else:
		for id in contracts:
			var cost: int = GameData.UNITS[id]["cost"]
			var b := _mk_button("%s — %dg  (%d left)" % [GameData.UNITS[id]["name"], cost, specialist_recruits], Vector2(x, y), Vector2(264, 26), func(): _buy(id))
			b.disabled = specialist_recruits <= 0 or gold < cost
			y += 28
	y += 14
	_mk_button("Deploy for Battle %d  >>" % battle_num, Vector2(x, y), Vector2(264, 40), start_deploy)

	# Relic shop on the right.
	var rx := 340.0
	var ry := 60.0
	_shop_header("Shop", rx, ry)
	ry += 32
	for id in RELIC_DEFS:
		if id in relics:
			continue
		var d: Dictionary = RELIC_DEFS[id]
		var b := _mk_button("%s — %dg" % [d["name"], d["cost"]], Vector2(rx, ry), Vector2(340, 24), func(): _buy_relic(id))
		b.disabled = gold < int(d["cost"])
		ry += 26

# Non-interlude rounds: no shopping — just deploy your standing force.
func _build_predeploy_ui() -> void:
	_clear_panel()
	top_label.visible = false
	_add_backdrop()
	_shop_header("Battle %d/%d  ·  Gold %d  —  hold the line (recruiting returns every 4th battle)" % [battle_num, MAX_BATTLES, gold], 24, 40)
	_mk_button("Deploy for Battle %d  >>" % battle_num, Vector2(24, 92), Vector2(264, 40), start_deploy)
	_build_roster_label()

func _shop_header(text: String, x: float, y: float) -> void:
	var l := Label.new()
	l.text = text
	l.position = Vector2(x, y)
	l.add_theme_font_size_override("font_size", 19)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(l)

func _wave_summary(n: int) -> String:
	var counts := {}
	for id in GameData.generate_wave(n):
		counts[id] = int(counts.get(id, 0)) + 1
	var parts: Array = []
	for id in counts:
		parts.append("%d x %s" % [counts[id], GameData.UNITS[id]["name"]])
	return " · ".join(parts)

func _build_deploy_ui() -> void:
	_clear_panel()
	top_label.visible = true
	var hint := Label.new()
	hint.text = "DEPLOY — Move Units: drag a box to select, click a spot to send them (set up now; the battle then plays out).\nOr pick a building and click a tile on your side to place it. Walls block enemies until destroyed."
	hint.position = Vector2(16, 44)
	hint.add_theme_font_size_override("font_size", 14)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hint)

	var tele := Label.new()
	tele.text = "Incoming wave:  " + _wave_summary(battle_num)
	tele.position = Vector2(392, 12)
	tele.add_theme_font_size_override("font_size", 14)
	tele.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(tele)

	var bx := 16.0
	var by := 82.0
	var mv := _mk_button("Move Units" + (" <" if _build_sel == "" else ""), Vector2(bx, by), Vector2(200, 28), func(): _set_build_sel(""))
	mv.disabled = _build_sel == ""
	by += 32
	for id in BUILDING_IDS:
		var cost: int = GameData.UNITS[id]["cost"]
		var mark := " <" if _build_sel == id else ""
		var b := _mk_button("%s — %dg%s" % [GameData.UNITS[id]["name"], cost, mark], Vector2(bx, by), Vector2(200, 28), func(): _set_build_sel(id))
		b.disabled = gold < cost
		by += 30
	by += 8
	_mk_button("Fight!  >>", Vector2(bx, by), Vector2(200, 40), begin_fight)
	_build_roster_label()
	queue_redraw()

func _set_build_sel(id: String) -> void:
	_build_sel = id
	if id != "":
		_clear_selection()
		info_text = "Placing %s — click a tile on your side." % GameData.UNITS[id]["name"]
	else:
		info_text = "Move mode — drag to select units, click to move them."
	_build_deploy_ui()
	_update_top()

func _build_battle_ui() -> void:
	_clear_panel()
	top_label.visible = true
	rally_btn = _mk_button("Rally!", Vector2(16, 46), Vector2(130, 34), _rally)

func _build_roster_label() -> void:
	var comp := {}
	for id in army:
		comp[id] = int(comp.get(id, 0)) + 1
	var atext := "Your forces:\n"
	for id in comp:
		atext += "  %d x %s\n" % [comp[id], GameData.UNITS[id]["name"]]
	if not relics.is_empty():
		atext += "\nRelics:\n"
		for r in relics:
			atext += "  * %s\n" % RELIC_DEFS[r]["name"]
	var al := Label.new()
	al.text = atext
	al.position = Vector2(ARENA.x - 300, 84)
	al.add_theme_font_size_override("font_size", 15)
	al.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(al)

func _mk_button(text: String, pos: Vector2, size: Vector2, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = size
	b.pressed.connect(cb)
	panel.add_child(b)
	return b

func flash_banner(text: String, color: Color) -> void:
	banner.text = text
	banner.modulate = Color(color.r, color.g, color.b, 1.0)
	var t := create_tween()
	t.tween_interval(0.7)
	t.tween_property(banner, "modulate:a", 0.0, 0.9)

func spawn_float_text(pos: Vector2, text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.modulate = color
	l.position = pos
	l.z_index = 100
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(l)
	var t := create_tween()
	t.tween_property(l, "position:y", pos.y - 22.0, 0.6)
	t.parallel().tween_property(l, "modulate:a", 0.0, 0.6)
	t.tween_callback(l.queue_free)

func _clear_panel() -> void:
	rally_btn = null
	for c in panel.get_children():
		panel.remove_child(c)
		c.queue_free()

func _update_top() -> void:
	var units := 0
	for id in army:
		if id in PEASANT_IDS or id in SPECIALIST_IDS:
			units += 1
	var income := 10 + 2 * units
	var s := "Gold: %d\nIncome: +%d/turn\nBattle: %d/%d" % [gold, income, battle_num, MAX_BATTLES]
	if phase == Phase.BATTLE:
		s += "\nUnits: %d   Enemies: %d" % [peasants.size(), enemies.size()]
	if info_text != "":
		s += "\n" + info_text
	top_label.text = s

# ---------------------------------------------------------------- actions

func _buy(id: String) -> void:
	var uname: String = GameData.UNITS[id]["name"]
	var cost: int = GameData.UNITS[id]["cost"]
	if id in PEASANT_IDS:
		if peasant_recruits <= 0:
			info_text = "No more peasants will join this cycle."
		else:
			peasant_recruits -= 1
			army.append(id)
			info_text = "%s joins your service (free)." % uname
	elif id in SPECIALIST_IDS:
		if not (id in contracts):
			info_text = "Sign the %s guild's contract first." % uname
		elif specialist_recruits <= 0:
			info_text = "No more specialists will join this cycle."
		elif gold < cost:
			info_text = "Not enough gold for %s." % uname
		else:
			gold -= cost
			specialist_recruits -= 1
			army.append(id)
			info_text = "%s enters your service." % uname
	else:  # building / structure
		if gold < cost:
			info_text = "Not enough gold for %s." % uname
		else:
			gold -= cost
			army.append(id)
			info_text = "Built %s." % uname
	_build_shop_ui()
	_update_top()

func _buy_relic(id: String) -> void:
	if id in relics:
		return
	var cost: int = int(RELIC_DEFS[id]["cost"])
	if gold >= cost:
		gold -= cost
		relics.append(id)
		info_text = "Acquired %s." % RELIC_DEFS[id]["name"]
	else:
		info_text = "Not enough gold."
	_build_shop_ui()
	_update_top()

func _rally() -> void:
	if rally_cd <= 0.0:
		rally_time = 5.0
		rally_cd = 18.0
		info_text = "To arms! The peasants surge forward."

func _process(delta: float) -> void:
	if phase == Phase.DEPLOY:
		queue_redraw()   # keep the build grid live
	if rally_time > 0.0:
		rally_time -= delta
	if rally_cd > 0.0:
		rally_cd -= delta
	if phase == Phase.BATTLE:
		if is_instance_valid(rally_btn):
			rally_btn.disabled = rally_cd > 0.0
			rally_btn.text = "Rally!" if rally_cd <= 0.0 else "Rally (%ds)" % int(ceil(rally_cd))
		_update_top()

# ---------------------------------------------------------------- helpers / background

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, ARENA), Color(0.30, 0.42, 0.20))                       # field
	# The battlefield (plot, crops, walls, grid) only shows during deploy & battle;
	# the shop/guild screens draw their own modal over a plain ground.
	if phase != Phase.DEPLOY and phase != Phase.BATTLE:
		return
	draw_rect(Rect2(Vector2.ZERO, Vector2(FENCE_X, ARENA.y)), Color(0.34, 0.40, 0.19))   # your tilled plot
	draw_rect(Rect2(Vector2(900, 0), Vector2(252, ARENA.y)), Color(0.25, 0.28, 0.17))    # enemy approach

	# Crop flair (placeholder yellow) above & below the castle footprint.
	var cx0 := CASTLE_GX * TILE
	var cw := CASTLE_SPAN * TILE
	draw_rect(Rect2(cx0, (CASTLE_GY - 2) * TILE, cw, 2 * TILE), Color(0.72, 0.60, 0.16))
	draw_rect(Rect2(cx0, (CASTLE_GY + CASTLE_SPAN) * TILE, cw, 2 * TILE), Color(0.72, 0.60, 0.16))

	draw_line(Vector2(FENCE_X, 0), Vector2(FENCE_X, ARENA.y), Color(0.45, 0.32, 0.18), 4.0)  # fence

	# Build grid over your side during deploy (hidden once the battle starts).
	if phase == Phase.DEPLOY:
		for gx in GRID_COLS:
			for gy in GRID_ROWS:
				var r := Rect2(gx * TILE, gy * TILE, TILE, TILE)
				draw_rect(r, Color(1, 0.6, 0.2, 0.14) if _tile_occupied(gx, gy) else Color(1, 1, 1, 0.04))
				draw_rect(r, Color(1, 1, 1, 0.10), false, 1.0)

	# Relic dock: a gold-ringed circle per relic taken, down the top-right.
	var ry := 52.0
	for i in relics.size():
		draw_circle(Vector2(ARENA.x - 24.0, ry), 11.0, Color(0.12, 0.10, 0.05, 0.85))
		draw_arc(Vector2(ARENA.x - 24.0, ry), 11.0, 0.0, TAU, 22, Color(0.66, 0.49, 0.13), 2.0)
		ry += 28.0

	if _dragging:
		draw_rect(_sel_rect, Color(1, 1, 0.4, 0.12))
		draw_rect(_sel_rect, Color(1, 1, 0.4, 0.7), false, 1.5)
