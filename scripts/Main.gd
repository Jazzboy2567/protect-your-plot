extends Node2D

# Game flow, economy, shop/deploy/battle UI, spawning, and the win/lose loop.
# You are the landowner: hire with gold, deploy peasants (position + stance),
# then watch them auto-battle the incoming wave.

enum Phase { SHOP, DEPLOY, BATTLE, GAMEOVER, WIN }

const ARENA := Vector2(1152, 648)
const START_GOLD := 70
const MAX_BATTLES := 12
const START_ARMY := ["farmer", "farmer", "farmer", "militia"]
const FENCE_X := 357.0

var gold: int = START_GOLD
var battle_num: int = 1
var army: Array = START_ARMY.duplicate()
var peasant_stance: int = Unit.Stance.AGGRESSIVE
var phase: int = Phase.SHOP
var info_text: String = ""

var rally_cd: float = 0.0
var rally_time: float = 0.0

var peasants: Array = []
var enemies: Array = []

var world: Node2D
var hud: CanvasLayer
var top_label: Label
var panel: Control
var rally_btn: Button
var banner: Label

var _drag_unit = null
var _drag_moved: bool = false
var _press_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	world = Node2D.new()
	add_child(world)

	hud = CanvasLayer.new()
	add_child(hud)

	top_label = Label.new()
	top_label.position = Vector2(16, 10)
	top_label.add_theme_font_size_override("font_size", 20)
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

	show_shop()

func is_fighting() -> bool:
	return phase == Phase.BATTLE

# ---------------------------------------------------------------- flow

func show_shop() -> void:
	phase = Phase.SHOP
	_despawn_all()
	if army.is_empty():
		army.append("farmer")
		army.append("farmer")
		info_text = "Your land lies empty — 2 serfs volunteer."
	_build_shop_ui()
	_update_top()

func start_deploy() -> void:
	phase = Phase.DEPLOY
	_despawn_all()
	_spawn_peasants()
	_spawn_enemies()
	_build_deploy_ui()
	if battle_num % 4 == 0:
		flash_banner("The Black Death approaches!", Color(0.9, 0.4, 0.9))
	_update_top()

func begin_fight() -> void:
	phase = Phase.BATTLE
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
	lbl.text = "The plague is broken!\nYour plot endures. You win."
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
	peasant_stance = Unit.Stance.AGGRESSIVE
	rally_cd = 0.0
	rally_time = 0.0
	info_text = ""
	show_shop()

# ---------------------------------------------------------------- spawning

func _spawn_peasants() -> void:
	var struct_i := 0
	var fight_i := 0
	for id in army:
		var u := _make_unit(id, 0)
		if u.is_structure:
			u.position = Vector2(330, 150 + struct_i * 70 + randf_range(-6, 6))
			struct_i += 1
		else:
			var col := fight_i / 8
			var row := fight_i % 8
			u.position = Vector2(120 + col * 36 + randf_range(-6, 6), 130 + row * 52 + randf_range(-8, 8))
			fight_i += 1
		u.stance = peasant_stance
		u.home_pos = u.position
		world.add_child(u)
		peasants.append(u)

func _spawn_enemies() -> void:
	var wave := GameData.generate_wave(battle_num)
	var i := 0
	for id in wave:
		var u := _make_unit(id, 1)
		var col := i / 10
		var row := i % 10
		u.position = Vector2(1040 - col * 36 + randf_range(-6, 6), 110 + row * 46 + randf_range(-8, 8))
		u.home_pos = u.position
		world.add_child(u)
		enemies.append(u)
		i += 1

func _make_unit(id: String, team: int) -> Unit:
	var u := Unit.new()
	u.setup(GameData.UNITS[id], team, self)
	return u

func _despawn_all() -> void:
	for c in world.get_children():
		c.queue_free()
	peasants.clear()
	enemies.clear()

# ---------------------------------------------------------------- combat queries

func get_nearest_enemy(u: Unit):
	var pool: Array = enemies if u.team == 0 else peasants
	var best = null
	var best_d := INF
	for e in pool:
		if not is_instance_valid(e) or e.hp <= 0.0:
			continue
		var d: float = u.global_position.distance_squared_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best

func get_allies(u: Unit) -> Array:
	return peasants if u.team == 0 else enemies

func get_follow_leader(u: Unit):
	var best = null
	var best_d := INF
	for p in peasants:
		if p == u or not is_instance_valid(p) or p.hp <= 0.0 or p.is_structure or p.stance == Unit.Stance.FOLLOW:
			continue
		var d: float = u.global_position.distance_squared_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best

func damage_mult(team: int) -> float:
	return 1.6 if (team == 0 and rally_time > 0.0) else 1.0

func on_unit_died(u: Unit) -> void:
	if u.team == 1 and phase == Phase.BATTLE:
		gold += u.gold_drop
	peasants.erase(u)
	enemies.erase(u)
	if phase != Phase.BATTLE:
		return
	if enemies.is_empty():
		_win_battle()
	elif peasants.is_empty():
		_lose_battle()

# ---------------------------------------------------------------- input (deploy)

func _unhandled_input(event: InputEvent) -> void:
	if phase != Phase.DEPLOY:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_unit = _peasant_at(event.position)
			_drag_moved = false
			_press_pos = event.position
		else:
			if _drag_unit != null and not _drag_moved:
				_cycle_unit_stance(_drag_unit)
			_drag_unit = null
	elif event is InputEventMouseMotion and _drag_unit != null:
		if event.position.distance_to(_press_pos) > 6.0:
			_drag_moved = true
		var p: Vector2 = event.position
		p.x = clampf(p.x, 28.0, FENCE_X - 12.0)
		p.y = clampf(p.y, 28.0, ARENA.y - 20.0)
		_drag_unit.global_position = p
		_drag_unit.home_pos = p

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

func _cycle_unit_stance(u) -> void:
	u.stance = (u.stance + 1) % 4
	u.queue_redraw()
	info_text = "%s -> %s" % [u.display_name, _stance_name(u.stance)]
	_update_top()

# ---------------------------------------------------------------- UI

func _build_shop_ui() -> void:
	_clear_panel()
	var x := 40.0
	var y := 86.0

	var title := Label.new()
	title.text = "— War Council —   (Battle %d of %d)" % [battle_num, MAX_BATTLES]
	title.position = Vector2(x, y)
	title.add_theme_font_size_override("font_size", 22)
	panel.add_child(title)
	y += 42

	var hires := [
		["Hire Farmer", "farmer"],
		["Hire Militia", "militia"],
		["Hire Archer", "archer"],
		["Hire Woodcutter", "woodcutter"],
		["Hire Baker (heal)", "baker"],
		["Hire Monk (haste)", "monk"],
		["Build Barricade", "barricade"],
	]
	for h in hires:
		var id: String = h[1]
		var cost: int = GameData.UNITS[id]["cost"]
		var b := _mk_button("%s — %dg" % [h[0], cost], Vector2(x, y), Vector2(230, 34), func(): _buy(id))
		b.disabled = gold < cost
		y += 38

	y += 8
	_mk_button("Default stance: " + _stance_name(peasant_stance), Vector2(x, y), Vector2(230, 34), _toggle_stance)
	y += 46
	_mk_button("Deploy for Battle %d  >>" % battle_num, Vector2(x, y), Vector2(230, 46), start_deploy)

	_build_roster_label()

func _build_deploy_ui() -> void:
	_clear_panel()
	var hint := Label.new()
	hint.text = "DEPLOY  —  drag peasants to position; click a peasant to change its stance.\nMarkers:  red = Aggressive   blue = Hold   cyan = Defend   yellow = Follow"
	hint.position = Vector2(16, 44)
	hint.add_theme_font_size_override("font_size", 15)
	panel.add_child(hint)
	_mk_button("Set all: " + _stance_name(peasant_stance), Vector2(16, 96), Vector2(230, 34), _toggle_stance)
	_mk_button("Fight!  >>", Vector2(16, 138), Vector2(230, 42), begin_fight)
	_build_roster_label()

func _build_battle_ui() -> void:
	_clear_panel()
	_mk_button("Set all: " + _stance_name(peasant_stance), Vector2(16, 46), Vector2(200, 34), _toggle_stance)
	rally_btn = _mk_button("Rally!", Vector2(226, 46), Vector2(130, 34), _rally)

func _build_roster_label() -> void:
	var comp := {}
	for id in army:
		comp[id] = int(comp.get(id, 0)) + 1
	var atext := "Your forces:\n"
	for id in comp:
		atext += "  %d x %s\n" % [comp[id], GameData.UNITS[id]["name"]]
	var al := Label.new()
	al.text = atext
	al.position = Vector2(ARENA.x - 300, 86)
	al.add_theme_font_size_override("font_size", 18)
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
	var s := "Gold: %d    Battle: %d/%d" % [gold, battle_num, MAX_BATTLES]
	if phase == Phase.BATTLE:
		s += "    Peasants: %d    Enemies: %d" % [peasants.size(), enemies.size()]
	if info_text != "":
		s += "\n" + info_text
	top_label.text = s

# ---------------------------------------------------------------- actions

func _buy(id: String) -> void:
	var cost: int = GameData.UNITS[id]["cost"]
	if gold >= cost:
		gold -= cost
		army.append(id)
		info_text = "Recruited %s." % GameData.UNITS[id]["name"]
	else:
		info_text = "Not enough gold for %s." % GameData.UNITS[id]["name"]
	_build_shop_ui()
	_update_top()

func _toggle_stance() -> void:
	peasant_stance = (peasant_stance + 1) % 4
	for p in peasants:
		if not p.is_structure:
			p.stance = peasant_stance
			p.queue_redraw()
	match phase:
		Phase.SHOP:
			_build_shop_ui()
		Phase.DEPLOY:
			_build_deploy_ui()
		Phase.BATTLE:
			_build_battle_ui()

func _rally() -> void:
	if rally_cd <= 0.0:
		rally_time = 5.0
		rally_cd = 18.0
		info_text = "To arms! The peasants surge forward."

func _process(delta: float) -> void:
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

func _stance_name(s: int) -> String:
	match s:
		Unit.Stance.AGGRESSIVE:
			return "Aggressive"
		Unit.Stance.HOLD:
			return "Hold"
		Unit.Stance.DEFEND:
			return "Defend"
		Unit.Stance.FOLLOW:
			return "Follow"
	return "?"

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, ARENA), Color(0.30, 0.45, 0.22))            # field
	draw_rect(Rect2(Vector2.ZERO, Vector2(360, ARENA.y)), Color(0.34, 0.40, 0.20))  # your tilled plot
	draw_line(Vector2(FENCE_X, 0), Vector2(FENCE_X, ARENA.y), Color(0.45, 0.32, 0.18), 4.0) # fence
	draw_rect(Rect2(Vector2(900, 0), Vector2(252, ARENA.y)), Color(0.28, 0.30, 0.20)) # enemy approach
