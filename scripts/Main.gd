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
const BUILDING_IDS := ["barricade", "spikes", "palisade", "stone_wall"]

# ---- Key palette: black/dark ground, gold-orange accent, cream text ----
const COL_PANEL := Color(0.11, 0.095, 0.065)
const COL_CARD := Color(0.17, 0.14, 0.085)
const COL_BTN := Color(0.21, 0.17, 0.09)
const COL_BTN_HOVER := Color(0.30, 0.23, 0.11)
const COL_GOLD := Color(0.94, 0.66, 0.18)
const COL_INK := Color(0.94, 0.89, 0.75)
const COL_SOFT := Color(0.70, 0.62, 0.46)
const COL_BORDER := Color(0.52, 0.39, 0.16)
const RECRUIT_CAP := 3
const MAX_CONTRACTS := 4

# Tile grid over your (left) side. Buildings snap to tiles; the castle is 3x3.
const TILE := 36.0
const GRID_COLS := 10
const GRID_ROWS := 18
const CASTLE_GX := 3
const CASTLE_GY := 7
const CASTLE_SPAN := 3


var gold: int = START_GOLD
var battle_num: int = 1
var army: Array = START_ARMY.duplicate()
var phase: int = Phase.SHOP
var info_text: String = ""

var relics: Array = []
var contracts: Array = []      # specialist ids you've signed (max 4); only these are hireable
var guild_offer: Array = []    # the specialist contracts on offer this interlude
var shop_offer: Array = []     # the (few) relics on sale this interlude
var recruits_left: int = RECRUIT_CAP          # shared 3 slots per interlude (peasant or specialist)
var recruited_this_cycle: Array = []          # unit ids that filled the slots this interlude
var dead_this_battle: Array = []
var total_fallen: int = 0          # units lost across the run (the church's revive pool)
var formation: Array = []          # saved unit layout {id, pos} so positions persist
var buildings: Array = []          # persistent placed buildings: {id, gx, gy}
var peasants: Array = []
var enemies: Array = []

var world: Node2D
var hud: CanvasLayer
var top_label: RichTextLabel
var panel: Control
var banner: Label
var ctrl_speed: Button
var ctrl_settings: Button
var hover_label: Label
var relic_dock: VBoxContainer
var settings_panel: Control
var ui_text_scale: float = 1.0     # info-text size multiplier (Settings)
var _shop_viewing: bool = false    # shop temporarily hidden to view the plot
var _shop_backdrop: ColorRect
var _shop_content: Control
var _toolbar_open: bool = false    # wall build toolbar expanded (Build ▸)
var _ui_hover_active: bool = false # a UI element (panel/card) owns the tooltip right now
var _speed_i: int = 0
const SPEEDS := [1.0, 2.0, 3.0]

# RTS selection / drag state
var _press_pos: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _sel_rect: Rect2 = Rect2()
var _grab = null                    # unit or wall grabbed on mouse-down
var _drag_units: Array = []         # the group of units being dragged together
var _drag_origins: Dictionary = {}  # node -> original global_position (for reset)
var _buy_id: String = ""            # wall id being placed via a ghost (drag-to-buy)
var _buy_press_pos: Vector2 = Vector2.ZERO  # where the buy-drag started (chip press)
var _mouse: Vector2 = Vector2.ZERO  # latest pointer position (for drag previews)
var _projectiles: Array = []        # in-flight shots: {from, to, t, dur, col}

func _ready() -> void:
	world = Node2D.new()
	add_child(world)

	hud = CanvasLayer.new()
	add_child(hud)

	top_label = RichTextLabel.new()
	top_label.bbcode_enabled = true
	top_label.fit_content = true
	top_label.scroll_active = false
	top_label.position = Vector2(12, 10)
	top_label.custom_minimum_size = Vector2(230, 0)
	top_label.add_theme_font_size_override("normal_font_size", 19)
	top_label.add_theme_font_size_override("bold_font_size", 19)
	var hudbg := StyleBoxFlat.new()
	hudbg.bg_color = Color(0.05, 0.05, 0.03, 0.72)
	hudbg.border_color = COL_BORDER
	hudbg.set_border_width_all(1)
	hudbg.set_corner_radius_all(4)
	hudbg.content_margin_left = 10
	hudbg.content_margin_right = 10
	hudbg.content_margin_top = 6
	hudbg.content_margin_bottom = 6
	top_label.add_theme_stylebox_override("normal", hudbg)
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
	ctrl_speed.position = Vector2(ARENA.x - 166, 10)
	ctrl_speed.size = Vector2(110, 30)
	ctrl_speed.pressed.connect(_cycle_speed)
	_style_button(ctrl_speed)
	hud.add_child(ctrl_speed)

	ctrl_settings = Button.new()
	ctrl_settings.text = "⚙"
	ctrl_settings.position = Vector2(ARENA.x - 50, 10)
	ctrl_settings.size = Vector2(40, 30)
	ctrl_settings.tooltip_text = "Settings"
	ctrl_settings.pressed.connect(_toggle_settings)
	_style_button(ctrl_settings)
	hud.add_child(ctrl_settings)

	hover_label = Label.new()
	hover_label.add_theme_color_override("font_color", COL_INK)
	hover_label.add_theme_font_size_override("font_size", 12)
	var hs := StyleBoxFlat.new()
	hs.bg_color = Color(0.08, 0.07, 0.04, 0.96)
	hs.border_color = COL_BORDER
	hs.set_border_width_all(1)
	hs.set_corner_radius_all(3)
	hs.content_margin_left = 8
	hs.content_margin_right = 8
	hs.content_margin_top = 6
	hs.content_margin_bottom = 6
	hover_label.add_theme_stylebox_override("normal", hs)
	hover_label.z_index = 200
	hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_label.visible = false
	hud.add_child(hover_label)

	relic_dock = VBoxContainer.new()
	relic_dock.add_theme_constant_override("separation", 6)
	relic_dock.position = Vector2(ARENA.x - 46, 52)
	hud.add_child(relic_dock)

	_build_settings_overlay()

	buildings = [{"id": "castle", "gx": CASTLE_GX, "gy": CASTLE_GY}, {"id": "church", "gx": 0, "gy": 8}]
	show_shop()

# ---------------------------------------------------------------- settings
func _build_settings_overlay() -> void:
	settings_panel = Control.new()
	settings_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_panel.z_index = 300
	settings_panel.visible = false
	hud.add_child(settings_panel)

	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.03, 0.78)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP   # block clicks to the game behind
	settings_panel.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	settings_panel.add_child(center)
	var plaque := PanelContainer.new()
	plaque.add_theme_stylebox_override("panel", _panel_style())
	plaque.custom_minimum_size = Vector2(460, 0)
	center.add_child(plaque)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	plaque.add_child(col)

	var head := Label.new()
	head.text = "Settings"
	head.add_theme_font_size_override("font_size", 24)
	head.add_theme_color_override("font_color", COL_GOLD)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)

	# --- Visuals ---
	col.add_child(_section_label("Visuals"))
	var fs := _menu_button("Toggle Fullscreen", _toggle_fullscreen)
	fs.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(fs)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var lbl := Label.new()
	lbl.text = "Info text size"
	lbl.add_theme_color_override("font_color", COL_INK)
	lbl.custom_minimum_size = Vector2(130, 0)
	row.add_child(lbl)
	var sl := HSlider.new()
	sl.min_value = 0.5
	sl.max_value = 3.0
	sl.step = 0.1
	sl.value = ui_text_scale
	sl.custom_minimum_size = Vector2(190, 0)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sl)
	var sb := SpinBox.new()
	sb.min_value = 0.5
	sb.max_value = 3.0
	sb.step = 0.1
	sb.value = ui_text_scale
	row.add_child(sb)
	sl.value_changed.connect(func(v): sb.set_value_no_signal(v); _set_text_scale(v))
	sb.value_changed.connect(func(v): sl.set_value_no_signal(v); _set_text_scale(v))
	col.add_child(row)

	# --- Audio (placeholder to flesh out) ---
	col.add_child(_section_label("Audio"))
	var av := Label.new()
	av.text = "Master volume — coming soon"
	av.add_theme_color_override("font_color", COL_SOFT)
	col.add_child(av)

	# --- Other (placeholder to flesh out) ---
	col.add_child(_section_label("Other"))
	var ov := Label.new()
	ov.text = "More options coming soon"
	ov.add_theme_color_override("font_color", COL_SOFT)
	col.add_child(ov)

	col.add_child(HSeparator.new())
	var close := _menu_button("Close", _toggle_settings)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(close)

func _toggle_settings() -> void:
	if settings_panel:
		settings_panel.visible = not settings_panel.visible

func _set_text_scale(v: float) -> void:
	ui_text_scale = clampf(v, 0.5, 3.0)
	_apply_text_scale()

func _apply_text_scale() -> void:
	var s := ui_text_scale
	if top_label:
		top_label.add_theme_font_size_override("normal_font_size", int(round(19 * s)))
		top_label.add_theme_font_size_override("bold_font_size", int(round(19 * s)))
	if hover_label:
		hover_label.add_theme_font_size_override("font_size", int(round(12 * s)))

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
	_shop_viewing = false
	if army.is_empty():
		army.append("peasant")
		army.append("peasant")
		info_text = "Your land lies empty — 2 peasants volunteer."
	# Spawn a static preview of the plot so "View plot" shows the real layout.
	_spawn_buildings()
	_spawn_peasants()
	if is_interlude():
		recruits_left = RECRUIT_CAP
		recruited_this_cycle = []
		guild_offer = _make_guild_offer()
		shop_offer = _make_shop_offer()
		open_guild()
	else:
		open_predeploy()

func _make_shop_offer() -> Array:
	var pool: Array = []
	for id in GameData.RELIC_DEFS:
		if id in relics:
			continue
		var req: Array = GameData.RELIC_REQUIRES.get(id, [])
		if not req.is_empty():
			var ok := false
			for c in req:
				if c in contracts:
					ok = true
					break
			if not ok:
				continue   # you lack a contract for the unit this relic buffs
		pool.append(id)
	pool.shuffle()
	return pool.slice(0, mini(4, pool.size()))

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
	_update_top()

func open_shop() -> void:
	phase = Phase.SHOP
	_build_shop_ui()
	_update_top()

func open_predeploy() -> void:
	# Non-interlude rounds skip the intermediate screen — straight to the grid,
	# where you re-arrange units and walls against the telegraphed wave.
	start_deploy()

func _sign_contract(id: String) -> void:
	if contracts.size() < MAX_CONTRACTS and not (id in contracts):
		contracts.append(id)
		info_text = "Signed with the %s — you can now hire them." % GameData.UNITS[id]["name"]
	guild_offer = []
	open_shop()

func start_deploy() -> void:
	phase = Phase.DEPLOY
	_buy_id = ""
	_despawn_all()
	_spawn_buildings()
	_spawn_peasants()
	_spawn_enemies()
	_refresh_relic_dock()
	_build_deploy_ui()
	if battle_num % 4 == 0:
		flash_banner("The Black Death approaches!", Color(0.9, 0.4, 0.9))
	_update_top()

func begin_fight() -> void:
	phase = Phase.BATTLE
	dead_this_battle.clear()
	_build_battle_ui()
	_update_top()
	queue_redraw()   # drop the deploy grid the moment combat starts

func _win_battle() -> void:
	phase = Phase.SHOP
	var survivors := peasants.size()
	var tax := 10 + 2 * survivors
	gold += tax
	info_text = "Victory! Tax +%dg. Survivors: %d" % [tax, survivors]
	flash_banner("Wave %d survived!  +%dg" % [battle_num, tax], Color(0.5, 0.95, 0.5))

	# Persist surviving units AND their positions so the layout carries over.
	var new_army: Array = []
	var new_formation: Array = []
	for p in peasants:
		if p.is_structure:
			continue
		new_army.append(p.type_id)
		new_formation.append({"id": p.type_id, "pos": p.command_point})
	army = new_army
	formation = new_formation

	# A surviving Church revives one fallen unit. If several *kinds* fell, let the
	# player choose which to bring back; if only one kind fell, revive it silently.
	if _has_building("church") and not dead_this_battle.is_empty():
		var kinds: Array = []
		for d in dead_this_battle:
			if not (d in kinds):
				kinds.append(d)
		if kinds.size() > 1:
			_show_revive_choice(kinds)
			return
		_do_revive(kinds[0])
	_after_win()

func _do_revive(id: String) -> void:
	army.append(id)
	total_fallen = maxi(0, total_fallen - 1)
	flash_banner("The church revives a %s." % GameData.UNITS[id]["name"], Color(0.8, 0.9, 1))

func _after_win() -> void:
	battle_num += 1
	if battle_num > MAX_BATTLES:
		_win_game()
	else:
		show_shop()

func _show_revive_choice(kinds: Array) -> void:
	phase = Phase.SHOP
	_clear_panel()
	top_label.visible = true
	_add_backdrop(0.85)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	var head := Label.new()
	head.text = "The church can revive one of the fallen — choose:"
	head.add_theme_font_size_override("font_size", 20)
	head.add_theme_color_override("font_color", COL_GOLD)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(row)
	for id in kinds:
		var b := _menu_button(GameData.UNITS[id]["name"], func(): _do_revive(id); _after_win())
		b.custom_minimum_size = Vector2(160, 44)
		row.add_child(b)

func _lose_battle() -> void:
	phase = Phase.GAMEOVER
	_clear_panel()
	var lbl := Label.new()
	lbl.text = "Your plot has fallen.\nYou held until Wave %d." % battle_num
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
	relics = []
	_refresh_relic_dock()
	contracts = []
	guild_offer = []
	shop_offer = []
	recruits_left = RECRUIT_CAP
	recruited_this_cycle = []
	dead_this_battle = []
	total_fallen = 0
	formation = []
	buildings = [{"id": "castle", "gx": CASTLE_GX, "gy": CASTLE_GY}, {"id": "church", "gx": 0, "gy": 8}]
	_buy_id = ""
	info_text = ""
	show_shop()

# ---------------------------------------------------------------- spawning

func _spawn_peasants() -> void:
	var ids: Array = []
	for id in army:
		if not GameData.UNITS[id].get("structure", false):
			ids.append(id)   # structures are placed on tiles, not spawned from the roster
	if "full_granary" in relics:
		ids.append("peasant")
		ids.append("peasant")

	# Each unit reuses its saved position (formation) if it has one; new units
	# fill default tiles so the layout you set carries over between battles.
	var fcopy := formation.duplicate(true)
	var placements: Array = []   # Vector2 or null
	var need := 0
	for id in ids:
		var pos = null
		for k in fcopy.size():
			if fcopy[k]["id"] == id:
				pos = fcopy[k]["pos"]
				fcopy.remove_at(k)
				break
		placements.append(pos)
		if pos == null:
			need += 1
	var max_gx := int((FENCE_X - 1.0) / TILE)
	# Tiles already claimed by units keeping their saved spot — don't spawn onto them.
	var avoid := {}
	for pl in placements:
		if pl != null:
			avoid[Vector2i(int(pl.x / TILE), int(pl.y / TILE))] = true
	var tiles := _tiles_around(7, 8, need, max_gx, avoid)   # start just right of the keep
	var ti := 0
	for i in ids.size():
		var u := _make_unit(ids[i], 0)
		var cp: Vector2
		if placements[i] != null:
			cp = placements[i]
		else:
			var t: Vector2i = tiles[ti] if ti < tiles.size() else Vector2i(7, 8)
			ti += 1
			cp = Vector2((t.x + 0.5) * TILE, (t.y + 0.5) * TILE)
		u.position = cp
		u.command_point = cp
		_apply_relics(u)
		world.add_child(u)
		peasants.append(u)

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
	if u.is_structure:
		var sp := _span(id)
		u.foot_w = sp.x * TILE
		u.foot_h = sp.y * TILE
		u.radius = maxf(u.foot_w, u.foot_h) * 0.5   # collision/blocking spans the footprint
	return u

# Building footprint in tiles (defaults to 1x1 for anything without span keys).
func _span(id: String) -> Vector2i:
	var d: Dictionary = GameData.UNITS.get(id, {})
	return Vector2i(int(d.get("span_x", 1)), int(d.get("span_y", 1)))

func _spawn_buildings() -> void:
	for b in buildings:
		var u := _make_unit(b["id"], 0)
		_apply_footprint(u, b)   # honour a saved rotation so the sprite isn't off-centre
		u.position = _building_center(b)
		u.command_point = u.position
		u.set_meta("bref", b)
		_apply_relics(u)
		world.add_child(u)
		peasants.append(u)

# A placed building's footprint, honouring its rotation (walls can be turned).
func _bspan(b: Dictionary) -> Vector2i:
	var s := _span(b["id"])
	if int(b.get("rot", 0)) == 1:
		return Vector2i(s.y, s.x)
	return s

func _apply_footprint(u: Unit, b: Dictionary) -> void:
	var sp := _bspan(b)
	u.foot_w = sp.x * TILE
	u.foot_h = sp.y * TILE
	u.radius = maxf(u.foot_w, u.foot_h) * 0.5

func _building_center(b: Dictionary) -> Vector2:
	var sp := _bspan(b)
	return Vector2((b["gx"] + sp.x / 2.0) * TILE, (b["gy"] + sp.y / 2.0) * TILE)

func _tile_occupied(gx: int, gy: int) -> bool:
	for b in buildings:
		var sp := _bspan(b)
		if gx >= b["gx"] and gx < b["gx"] + sp.x and gy >= b["gy"] and gy < b["gy"] + sp.y:
			return true
	return false

func _has_building(id: String) -> bool:
	for b in buildings:
		if b["id"] == id:
			return true
	return false

func _plural(nm: String, n: int) -> String:
	return nm if n == 1 else nm + "s"

func _tile_occupied_except(gx: int, gy: int, except_b) -> bool:
	for b in buildings:
		if b == except_b:
			continue
		var sp := _bspan(b)
		if gx >= b["gx"] and gx < b["gx"] + sp.x and gy >= b["gy"] and gy < b["gy"] + sp.y:
			return true
	return false

func _units_in_footprint(gx: int, gy: int, sp: Vector2i) -> bool:
	var rect := Rect2(gx * TILE, gy * TILE, sp.x * TILE, sp.y * TILE)
	for p in peasants:
		if not is_instance_valid(p) or p.is_structure:
			continue
		if rect.has_point(p.global_position):
			return true
	return false

# A footprint is placeable only if it's in-bounds and clear of buildings AND units.
func _footprint_free(gx: int, gy: int, sp: Vector2i, except_b = null) -> bool:
	if gx < 0 or gy < 0 or gx + sp.x > GRID_COLS or gy + sp.y > GRID_ROWS:
		return false
	for dx in sp.x:
		for dy in sp.y:
			if _tile_occupied_except(gx + dx, gy + dy, except_b):
				return false
	return not _units_in_footprint(gx, gy, sp)

func _do_place(id: String, gx: int, gy: int) -> Unit:
	var b := {"id": id, "gx": gx, "gy": gy}
	buildings.append(b)
	var u := _make_unit(id, 0)
	u.position = _building_center(b)
	u.command_point = u.position
	u.set_meta("bref", b)
	_apply_relics(u)
	world.add_child(u)
	peasants.append(u)
	return u

func _tile_of(pos: Vector2) -> Vector2i:
	return Vector2i(int(pos.x / TILE), int(pos.y / TILE))

func _center_of(t: Vector2i) -> Vector2:
	return Vector2((t.x + 0.5) * TILE, (t.y + 0.5) * TILE)

func _unit_at_tile(t: Vector2i, exclude: Dictionary):
	for p in peasants:
		if not is_instance_valid(p) or p.is_structure or exclude.has(p):
			continue
		if _tile_of(p.global_position) == t:
			return p
	return null

func _wall_covering(gx: int, gy: int, except_b):
	for bb in buildings:
		if bb == except_b or bb["id"] == "castle" or bb["id"] == "church":
			continue
		var sp := _bspan(bb)
		if gx >= bb["gx"] and gx < bb["gx"] + sp.x and gy >= bb["gy"] and gy < bb["gy"] + sp.y:
			return bb
	return null

func _wall_unit(b):
	for p in peasants:
		if is_instance_valid(p) and p.is_structure and p.has_meta("bref") and p.get_meta("bref") == b:
			return p
	return null

# Toolbar: begin placing a wall as a ghost that follows the cursor. Gold is only
# spent when it's dropped on a valid spot that overlaps no units.
func _start_buy(id: String) -> void:
	if gold < int(GameData.UNITS[id]["cost"]):
		info_text = "Not enough gold for that."
		_update_top()
		return
	_buy_id = id
	_buy_press_pos = get_global_mouse_position()
	_clear_selection()
	info_text = "Drag onto the field and release to place, or click a tile. Right-click cancels."
	_update_top()
	queue_redraw()

# Releasing the wall chip: if you dragged away from it, place at the cursor;
# a plain click leaves the ghost armed so you can click a tile instead.
func _buy_chip_release() -> void:
	if _buy_id != "" and get_global_mouse_position().distance_to(_buy_press_pos) > 8.0:
		_place_buy(get_global_mouse_position())

func _place_buy(pos: Vector2) -> void:
	if _buy_id == "":
		return
	var sp := _span(_buy_id)
	var gx := clampi(int(pos.x / TILE), 0, GRID_COLS - sp.x)
	var gy := clampi(int(pos.y / TILE), 0, GRID_ROWS - sp.y)
	if not _footprint_free(gx, gy, sp):
		info_text = "Can't build there — blocked or over a unit."
		_update_top()
		queue_redraw()
		return   # keep the ghost so they can try elsewhere
	var cost: int = int(GameData.UNITS[_buy_id]["cost"])
	if gold < cost:
		info_text = "Not enough gold."
		_buy_id = ""
	else:
		gold -= cost
		var nm: String = GameData.UNITS[_buy_id]["name"]
		_do_place(_buy_id, gx, gy)
		info_text = "Built %s." % nm
		_buy_id = ""
	_build_deploy_ui()
	_update_top()
	queue_redraw()

# Drop a dragged wall: snap to the tile, swap with a same-size wall there, or
# snap back if the spot is blocked.
func _drop_wall(wall, pos: Vector2) -> void:
	if not wall.has_meta("bref"):
		return
	var b = wall.get_meta("bref")
	# Dragged off the build area (out onto the field) — sell it for a refund.
	if pos.x > FENCE_X + 70.0:
		_remove_wall(wall)
		return
	var sp := _bspan(b)
	var gx := clampi(int(pos.x / TILE), 0, GRID_COLS - sp.x)
	var gy := clampi(int(pos.y / TILE), 0, GRID_ROWS - sp.y)
	if _footprint_free(gx, gy, sp, b):
		b["gx"] = gx
		b["gy"] = gy
		wall.relocate(_building_center(b))
	else:
		var other = _wall_covering(gx, gy, b)
		if other != null and _bspan(other) == sp:
			var ob: Dictionary = other
			var og: int = int(ob["gx"])
			var oy: int = int(ob["gy"])
			var ow = _wall_unit(ob)
			ob["gx"] = b["gx"]
			ob["gy"] = b["gy"]
			b["gx"] = og
			b["gy"] = oy
			wall.relocate(_building_center(b))
			if ow != null:
				ow.relocate(_building_center(ob))
		elif _drag_origins.has(wall):
			wall.relocate(_drag_origins[wall])   # blocked: snap back
	queue_redraw()

func _rotate_wall(wall) -> void:
	if not wall.has_meta("bref"):
		return
	var b = wall.get_meta("bref")
	if b["id"] == "castle" or b["id"] == "church":
		return
	var newrot := 1 - int(b.get("rot", 0))
	var s := _span(b["id"])
	var sp := Vector2i(s.y, s.x) if newrot == 1 else s
	var gx := clampi(int(b["gx"]), 0, GRID_COLS - sp.x)
	var gy := clampi(int(b["gy"]), 0, GRID_ROWS - sp.y)
	if _footprint_free(gx, gy, sp, b):
		b["rot"] = newrot
		b["gx"] = gx
		b["gy"] = gy
		_apply_footprint(wall, b)
		wall.relocate(_building_center(b))
		info_text = "Rotated %s." % GameData.UNITS[b["id"]]["name"]
	else:
		info_text = "No room to rotate that here."
	_update_top()
	queue_redraw()

# Drop the dragged unit group: preserve their formation, allow a swap for a
# single unit, and snap the whole group back if any target is invalid.
func _drop_units(pos: Vector2) -> void:
	if _drag_units.is_empty() or not is_instance_valid(_grab):
		_reset_drag()
		return
	var max_gx := int((FENCE_X - 1.0) / TILE)
	var delta := Vector2i(clampi(int(pos.x / TILE), 0, max_gx), clampi(int(pos.y / TILE), 0, GRID_ROWS - 1)) - _tile_of(_drag_origins[_grab])
	var excl := {}
	for u in _drag_units:
		excl[u] = true
	if _drag_units.size() == 1:
		var u0 = _drag_units[0]
		var nt := _tile_of(_drag_origins[u0]) + delta
		nt = Vector2i(clampi(nt.x, 0, max_gx), clampi(nt.y, 0, GRID_ROWS - 1))
		if _tile_occupied(nt.x, nt.y):
			_reset_drag()
			return
		var occ = _unit_at_tile(nt, excl)
		if occ != null:   # swap places
			var ocp := _center_of(_tile_of(_drag_origins[u0]))
			occ.global_position = ocp
			occ.command_point = ocp
		var cp := _center_of(nt)
		u0.global_position = cp
		u0.command_point = cp
		_clear_selection()
		return
	var targets := {}
	for u in _drag_units:
		var nt := _tile_of(_drag_origins[u]) + delta
		if nt.x < 0 or nt.x > max_gx or nt.y < 0 or nt.y >= GRID_ROWS or _tile_occupied(nt.x, nt.y) or _unit_at_tile(nt, excl) != null:
			_reset_drag()
			return
		targets[u] = nt
	for u in _drag_units:
		var cp := _center_of(targets[u])
		u.global_position = cp
		u.command_point = cp
	_clear_selection()

func _reset_drag() -> void:
	for n in _drag_origins:
		if not is_instance_valid(n):
			continue
		if n.is_structure:
			n.relocate(_drag_origins[n])
		else:
			n.global_position = _drag_origins[n]
			n.command_point = _drag_origins[n]

func _clear_grab_state() -> void:
	if is_instance_valid(_grab) and _grab.is_structure:
		_grab.being_dragged = false
	_grab = null
	_dragging = false
	_drag_units.clear()
	_drag_origins.clear()

func _remove_wall(wall) -> void:
	var cost: int = int(GameData.UNITS[wall.type_id]["cost"])
	gold += cost
	if wall.has_meta("bref"):
		buildings.erase(wall.get_meta("bref"))
	peasants.erase(wall)
	wall.queue_free()
	info_text = "Sold %s (+%dg)." % [GameData.UNITS[wall.type_id]["name"], cost]
	_build_deploy_ui()
	_update_top()
	queue_redraw()

# Nearest wall directly in an advancing enemy's path (so a wall line blocks it).
func structure_ahead(u: Unit):
	var best = null
	var best_d := 56.0
	for p in peasants:
		if not is_instance_valid(p) or not p.is_structure or p.hp <= 0.0 or p.invulnerable:
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
	_projectiles.clear()

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
		if not is_instance_valid(p) or not p.is_structure or p.hp <= 0.0 or p.invulnerable:
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
		if u.global_position.distance_to(a.global_position) > u.heal_range + a.radius + u.radius:
			continue
		var frac: float = a.hp / a.max_hp
		if frac < best_frac:
			best_frac = frac
			best = a
	return best

func get_allies(u: Unit) -> Array:
	return peasants if u.team == 0 else enemies

# --- Wall collision: a solid structure footprint blocks movement (units route around) ---
func blocking_wall(pos: Vector2, r: float, ignore = null):
	for p in peasants:
		if p == ignore or not is_instance_valid(p) or not p.is_structure or p.hp <= 0.0:
			continue
		var w: float = p.foot_w if p.foot_w > 0.0 else p.radius * 2.0
		var h: float = p.foot_h if p.foot_h > 0.0 else p.radius * 2.0
		var rect := Rect2(p.global_position - Vector2(w, h) * 0.5, Vector2(w, h)).grow(r * 0.6)
		if rect.has_point(pos):
			return p
	return null

func wall_blocks(pos: Vector2, r: float, ignore = null) -> bool:
	return blocking_wall(pos, r, ignore) != null

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


func on_unit_died(u: Unit) -> void:
	if u.team == 1 and phase == Phase.BATTLE:
		gold += u.gold_drop
	elif u.team == 0 and phase == Phase.BATTLE and not u.is_structure:
		dead_this_battle.append(u.type_id)
		total_fallen += 1
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
			_mouse = event.position
			_dragging = false
			if _buy_id != "":
				return   # a ghost is being placed; the release drops it
			# Grab a unit (with its selected group) to drag; else grab a wall.
			var u = _peasant_at(event.position)
			if u != null:
				_grab = u
				if not u.selected:
					_clear_selection()
					u.selected = true
					u.queue_redraw()
				for p in peasants:
					if is_instance_valid(p) and p.selected and not p.is_structure:
						_drag_units.append(p)
						_drag_origins[p] = p.global_position
			else:
				var w = _wall_at(event.position)
				if w != null:
					_grab = w
					w.being_dragged = true
					_drag_origins[w] = w.global_position
		else:
			if _buy_id != "":
				_place_buy(event.position)
			elif not _drag_units.is_empty():
				if _dragging:
					_drop_units(event.position)
				else:
					_handle_click(event.position)
			elif _grab != null and _grab.is_structure:
				if _dragging:
					_drop_wall(_grab, event.position)
				# a plain click does nothing now — sell by dragging it off the field
			elif _dragging:
				_select_in_rect(Rect2(_press_pos, event.position - _press_pos).abs())
			else:
				_handle_click(event.position)
			_clear_grab_state()
			queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if _buy_id != "":
			_buy_id = ""            # right-click cancels a pending wall purchase
			info_text = ""
			queue_redraw()
		else:
			var w = _wall_at(event.position)
			if w != null:
				_rotate_wall(w)     # right-click a wall to rotate it
			else:
				_command_selected_to(event.position)   # else move the selection
	elif event is InputEventMouseMotion:
		_mouse = event.position
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			if event.position.distance_to(_press_pos) > 6.0:
				_dragging = true
			if _dragging:
				if not _drag_units.is_empty():
					var d: Vector2 = event.position - _press_pos
					for u in _drag_units:
						if is_instance_valid(u):
							u.global_position = _drag_origins[u] + d   # units follow the cursor
				elif _grab != null and _grab.is_structure:
					_grab.global_position = event.position            # wall follows the cursor
				elif _grab == null and _buy_id == "":
					_sel_rect = Rect2(_press_pos, event.position - _press_pos).abs()
			queue_redraw()
		elif _buy_id != "":
			queue_redraw()   # ghost tracks the cursor before you click

func _handle_click(pos: Vector2) -> void:
	var u = _peasant_at(pos)
	if u != null:
		_clear_selection()
		u.selected = true
		u.queue_redraw()
	elif _has_selection():
		_command_selected_to(pos)
	else:
		_clear_selection()

func _wall_at(pos: Vector2):
	for p in peasants:
		if not is_instance_valid(p) or not p.is_structure:
			continue
		if p.type_id == "castle" or p.type_id == "church":
			continue   # you can't remove your keep or church
		if pos.distance_to(p.global_position) <= p.radius + 4.0:
			return p
	return null

func _command_selected_to(pos: Vector2) -> void:
	var sel: Array = []
	for p in peasants:
		if is_instance_valid(p) and p.selected and not p.is_structure:
			sel.append(p)
	if sel.is_empty():
		return
	# Snap the target to a grid tile and give each selected unit its own tile,
	# steering clear of tiles other (non-selected) units already stand on.
	var max_gx := int((FENCE_X - 1.0) / TILE) if phase == Phase.DEPLOY else GRID_COLS + 14
	var gx := clampi(int(pos.x / TILE), 0, max_gx)
	var gy := clampi(int(pos.y / TILE), 0, GRID_ROWS - 1)
	var avoid := {}
	for p in peasants:
		if is_instance_valid(p) and not p.is_structure and not p.selected:
			avoid[Vector2i(int(p.global_position.x / TILE), int(p.global_position.y / TILE))] = true
	var tiles := _tiles_around(gx, gy, sel.size(), max_gx, avoid)
	for i in mini(sel.size(), tiles.size()):
		var t: Vector2i = tiles[i]
		var cp := Vector2((t.x + 0.5) * TILE, (t.y + 0.5) * TILE)
		sel[i].command_point = cp
		if phase == Phase.DEPLOY:
			sel[i].global_position = cp
		sel[i].queue_redraw()
	_clear_selection()   # a move order deselects the group

func _tiles_around(gx: int, gy: int, count: int, max_gx: int, avoid: Dictionary = {}) -> Array:
	var res: Array = []
	var r := 0
	while res.size() < count and r < 40:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue   # only the outer ring at radius r
				var tx := gx + dx
				var ty := gy + dy
				if tx < 0 or tx > max_gx or ty < 0 or ty >= GRID_ROWS:
					continue
				if _tile_occupied(tx, ty):
					continue   # skip building footprints
				if avoid.has(Vector2i(tx, ty)):
					continue   # skip tiles other units already hold
				res.append(Vector2i(tx, ty))
				if res.size() >= count:
					return res
		r += 1
	return res

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
func _add_backdrop(alpha: float = 0.62) -> ColorRect:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.04, alpha)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(bg)
	return bg

func _card_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COL_CARD
	s.border_color = COL_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(5)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	return s

func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COL_PANEL
	s.border_color = COL_BORDER
	s.set_border_width_all(2)
	s.set_corner_radius_all(7)
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 18
	s.content_margin_bottom = 20
	return s

# Give any Button the dark/gold theme.
func _style_button(b: Button) -> void:
	var n := StyleBoxFlat.new()
	n.bg_color = COL_BTN
	n.border_color = COL_BORDER
	n.set_border_width_all(1)
	n.set_corner_radius_all(4)
	n.content_margin_left = 10
	n.content_margin_right = 10
	n.content_margin_top = 6
	n.content_margin_bottom = 6
	var h: StyleBoxFlat = n.duplicate()
	h.bg_color = COL_BTN_HOVER
	h.border_color = COL_GOLD
	var dis: StyleBoxFlat = n.duplicate()
	dis.bg_color = Color(0.13, 0.12, 0.08)
	dis.border_color = Color(0.30, 0.27, 0.20)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("focus", h)
	b.add_theme_stylebox_override("disabled", dis)
	b.add_theme_color_override("font_color", COL_INK)
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.9, 0.6))
	b.add_theme_color_override("font_disabled_color", COL_SOFT)

func _menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(256, 30)
	b.pressed.connect(cb)
	_style_button(b)
	return b

# Green primary-action styling (for the big Deploy / Fight button).
func _style_green_button(b: Button) -> void:
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0.28, 0.42, 0.16)
	n.border_color = Color(0.52, 0.74, 0.32)
	n.set_border_width_all(1)
	n.set_corner_radius_all(5)
	n.content_margin_left = 12
	n.content_margin_right = 12
	n.content_margin_top = 8
	n.content_margin_bottom = 8
	var h: StyleBoxFlat = n.duplicate()
	h.bg_color = Color(0.37, 0.54, 0.21)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("focus", h)
	b.add_theme_color_override("font_color", Color(0.96, 1.0, 0.90))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_font_size_override("font_size", 18)

func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", COL_GOLD)
	l.add_theme_font_size_override("font_size", 16)
	return l

func _stat_row(label_text: String, value_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var a := Label.new()
	a.text = label_text
	a.add_theme_color_override("font_color", COL_SOFT)
	a.add_theme_font_size_override("font_size", 13)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b := Label.new()
	b.text = value_text
	b.add_theme_color_override("font_color", COL_INK)
	b.add_theme_font_size_override("font_size", 13)
	row.add_child(a)
	row.add_child(sp)
	row.add_child(b)
	return row

func _unit_tooltip(id: String) -> String:
	var d: Dictionary = GameData.UNITS[id]
	var rng := float(d.get("range", 6))
	var lines: Array = [str(d["name"]), "Health: %d" % int(d["hp"])]
	if float(d.get("damage", 0)) > 0.0:
		lines.append("Damage: %d" % int(d["damage"]))
	lines.append("Atk speed: %.1f / s" % (1.0 / float(d.get("cooldown", 1.0))))
	lines.append("Range: %s" % ("melee" if rng <= 12.0 else str(int(rng))))
	if float(d.get("armor", 0)) > 0.0:
		lines.append("Armor: %d" % int(d["armor"]))
	if GameData.SPECIALTY.has(id):
		lines.append(str(GameData.SPECIALTY[id]))
	return "\n".join(lines)

func _guild_card(id: String) -> Control:
	var d: Dictionary = GameData.UNITS[id]
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _card_style())
	pc.custom_minimum_size = Vector2(224, 0)
	pc.mouse_filter = Control.MOUSE_FILTER_PASS
	pc.mouse_entered.connect(func(): _show_hover(_unit_tooltip(id), pc.global_position + Vector2(0, -118)))
	pc.mouse_exited.connect(_hide_hover)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE   # let the whole card own the hover
	pc.add_child(v)
	var gl := Label.new()
	gl.text = str(GameData.GUILD_NAMES.get(id, "Guild")).to_upper()
	gl.add_theme_color_override("font_color", COL_GOLD)
	gl.add_theme_font_size_override("font_size", 11)
	gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(gl)
	var nm := Label.new()
	nm.text = d["name"]
	nm.add_theme_color_override("font_color", COL_INK)
	nm.add_theme_font_size_override("font_size", 22)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nm)
	var sp := Label.new()
	sp.text = str(GameData.SPECIALTY.get(id, ""))
	sp.add_theme_color_override("font_color", COL_INK)
	sp.add_theme_font_size_override("font_size", 14)
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sp)
	var hs := HSeparator.new()
	hs.mouse_filter = Control.MOUSE_FILTER_IGNORE   # the bar no longer steals the hover
	v.add_child(hs)
	var btn := Button.new()
	btn.text = "Sign Contract"
	btn.pressed.connect(func(): _sign_contract(id))
	# Keep the unit's stats showing while the pointer is over the button too.
	btn.mouse_entered.connect(func(): _show_hover(_unit_tooltip(id), pc.global_position + Vector2(0, -118)))
	btn.mouse_exited.connect(_hide_hover)
	_style_button(btn)
	v.add_child(btn)
	return pc

# Slay-the-Spire-style relic: the box shows name / who it affects / effect, and
# the gold cost sits BELOW the box (outside it). Click the box to buy; hover it
# for the full description (room for an icon later).
func _relic_card(id: String) -> Control:
	var d: Dictionary = GameData.RELIC_DEFS[id]
	var cost: int = int(d["cost"])
	var eff: String = str(d.get("effect", ""))
	var scope_name: String = str(GameData.RELIC_SCOPE.get(id, "Everyone"))
	var affordable: bool = gold >= cost

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	if not affordable:
		outer.modulate = Color(1, 1, 1, 0.55)

	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _card_style())
	pc.custom_minimum_size = Vector2(210, 118)
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	outer.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(v)

	var nm := Label.new()
	nm.text = d["name"]
	nm.add_theme_color_override("font_color", COL_INK)
	nm.add_theme_font_size_override("font_size", 16)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.custom_minimum_size = Vector2(186, 0)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nm)

	var af := Label.new()
	af.text = scope_name.to_upper()
	af.add_theme_color_override("font_color", COL_GOLD)
	af.add_theme_font_size_override("font_size", 11)
	af.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	af.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(af)

	var el := Label.new()
	el.text = eff
	el.add_theme_color_override("font_color", COL_SOFT)
	el.add_theme_font_size_override("font_size", 13)
	el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	el.custom_minimum_size = Vector2(186, 0)
	el.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(el)

	# Cost OUTSIDE the box, in gold.
	var cl := Label.new()
	cl.text = "%d gold" % cost
	cl.add_theme_color_override("font_color", COL_GOLD if affordable else COL_SOFT)
	cl.add_theme_font_size_override("font_size", 17)
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(cl)

	var tip := "%s\nAffects: %s\n%s" % [d["name"], scope_name, eff]
	pc.mouse_entered.connect(func(): _show_hover(tip, pc.global_position + Vector2(0, -84)))
	pc.mouse_exited.connect(_hide_hover)
	pc.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and affordable:
			_buy_relic(id))
	return outer

# The Guild page: a centered modal — sign one free contract to unlock a specialist.
func _build_guild_ui() -> void:
	_clear_panel()
	top_label.visible = true
	_add_backdrop(0.45)   # keep the field faintly visible behind the modal
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(center)
	var plaque := PanelContainer.new()
	plaque.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(plaque)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	plaque.add_child(col)

	var head := Label.new()
	head.text = "Thanks for protecting the land!  Choose a guild to partner with and gain their services."
	head.add_theme_font_size_override("font_size", 20)
	head.add_theme_color_override("font_color", COL_GOLD)
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
	_style_button(cont)
	col.add_child(cont)

# The Shop + Recruit page (interlude): a centered modal with two columns.
func _build_shop_ui() -> void:
	_clear_panel()
	top_label.visible = true
	_shop_backdrop = _add_backdrop(0.9)   # solid overlay over the field
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(center)
	_shop_content = center   # the whole modal we can hide with View
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(pc)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	pc.add_child(outer)

	var head := Label.new()
	head.text = "Shop & Recruit"
	head.add_theme_font_size_override("font_size", 22)
	head.add_theme_color_override("font_color", COL_GOLD)
	head.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	outer.add_child(head)

	# --- Shop: a few relic cards ---
	outer.add_child(_section_label("Shop"))
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 14)
	srow.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	outer.add_child(srow)
	var offered := 0
	for id in shop_offer:
		if id in relics:
			continue
		srow.add_child(_relic_card(id))
		offered += 1
	if offered == 0:
		var sold := Label.new()
		sold.text = "The merchant is sold out."
		sold.add_theme_color_override("font_color", COL_SOFT)
		srow.add_child(sold)

	# --- Recruit: 3 slots filled from the palette below ---
	outer.add_child(_section_label("Recruit — %d of %d slots left" % [recruits_left, RECRUIT_CAP]))
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 10)
	slots.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	outer.add_child(slots)
	for i in RECRUIT_CAP:
		if i < recruited_this_cycle.size():
			var uid: String = recruited_this_cycle[i]
			var idx := i
			var sb := Button.new()
			sb.text = GameData.UNITS[uid]["name"] + "   ✕"
			sb.custom_minimum_size = Vector2(154, 40)
			sb.tooltip_text = "Click to remove"
			_style_button(sb)
			sb.pressed.connect(func(): _unrecruit(idx))
			sb.mouse_entered.connect(func(): _show_hover(_unit_tooltip(uid), sb.global_position + Vector2(0, -116)))
			sb.mouse_exited.connect(_hide_hover)
			slots.add_child(sb)
		else:
			var slot := PanelContainer.new()
			slot.add_theme_stylebox_override("panel", _card_style())
			slot.custom_minimum_size = Vector2(154, 40)
			var sl := Label.new()
			sl.text = "— empty —"
			sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			sl.add_theme_color_override("font_color", COL_SOFT)
			slot.add_child(sl)
			slots.add_child(slot)

	# Palette of units you can drop into a slot.
	var pal := HBoxContainer.new()
	pal.add_theme_constant_override("separation", 10)
	pal.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	outer.add_child(pal)
	var pcost: int = GameData.UNITS["peasant"]["cost"]
	var pb := _priced_chip("Peasant", "%dg" % pcost, func(): _buy("peasant"), recruits_left > 0 and gold >= pcost)
	pb.custom_minimum_size = Vector2(170, 34)
	pb.mouse_entered.connect(func(): _show_hover(_unit_tooltip("peasant"), pb.global_position + Vector2(0, -116)))
	pb.mouse_exited.connect(_hide_hover)
	pal.add_child(pb)
	if contracts.is_empty():
		var hint := Label.new()
		hint.text = "Sign guild contracts to unlock specialists."
		hint.add_theme_color_override("font_color", COL_SOFT)
		hint.add_theme_font_size_override("font_size", 13)
		pal.add_child(hint)
	else:
		for id in contracts:
			var cost: int = GameData.UNITS[id]["cost"]
			var b := _priced_chip(str(GameData.UNITS[id]["name"]), "%dg" % cost, func(): _buy(id), recruits_left > 0 and gold >= cost)
			b.custom_minimum_size = Vector2(170, 34)
			b.mouse_entered.connect(func(): _show_hover(_unit_tooltip(id), b.global_position + Vector2(0, -116)))
			b.mouse_exited.connect(_hide_hover)
			pal.add_child(b)

	# View + Continue in the bottom-right stay visible even when the modal is
	# hidden: View toggles the shop away so you can look over your plot and
	# relics before spending.
	# While viewing, surface the same forces/relics/contracts panels as deploy.
	if _shop_viewing:
		_build_field_hud()
	var view_btn := _mk_button("View plot" if not _shop_viewing else "Back to shop", Vector2(ARENA.x - 310, ARENA.y - 56), Vector2(140, 40), _toggle_shop_view)
	_style_button(view_btn)
	var cont2 := _mk_button("Continue  >>", Vector2(ARENA.x - 160, ARENA.y - 56), Vector2(150, 40), start_deploy)
	_style_green_button(cont2)

	_apply_shop_view()

func _toggle_shop_view() -> void:
	_shop_viewing = not _shop_viewing
	_build_shop_ui()   # rebuild so the button label and visibility both update

func _apply_shop_view() -> void:
	if _shop_backdrop:
		_shop_backdrop.visible = not _shop_viewing
	if _shop_content:
		_shop_content.visible = not _shop_viewing

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

	# Incoming-wave telegraph, centred across the top.
	var tele := Label.new()
	tele.text = "Incoming:  " + _wave_summary(battle_num)
	tele.size = Vector2(ARENA.x, 24)
	tele.position = Vector2(0, 12)
	tele.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tele.add_theme_font_size_override("font_size", 15)
	tele.add_theme_color_override("font_color", COL_INK)
	tele.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(tele)

	# Building toolbar (bottom-left) hides behind a Build button. Open it to pick a
	# wall; click a wall to pick it up as a ghost, place, drag to move, right-click
	# to rotate, click to sell.
	var byy := ARENA.y - 50.0
	if not _toolbar_open:
		_mk_button("Build ▸", Vector2(16, byy), Vector2(120, 36), func(): _toolbar_open = true; _build_deploy_ui())
	else:
		_mk_button("◂ Build", Vector2(16, byy), Vector2(120, 36), func(): _toolbar_open = false; _build_deploy_ui())
		var names := {"barricade": "Barricade", "spikes": "Spikes", "palisade": "Palisade", "stone_wall": "Stone Wall"}
		var bx := 142.0
		for id in BUILDING_IDS:
			var cost: int = GameData.UNITS[id]["cost"]
			# Press the chip to pick up a ghost; drag it onto the field and drop, or
			# click the chip then click a tile. Gold is spent only on a valid placement.
			var chip := _priced_chip(names[id], "%dg" % cost, func(): _start_buy(id), gold >= cost, func(): _buy_chip_release())
			chip.position = Vector2(bx, byy)
			chip.size = Vector2(150, 36)
			chip.custom_minimum_size = Vector2(150, 36)
			var bd: Dictionary = GameData.UNITS[id]
			var btip := "%s\nHealth: %d  ·  Armor: %d" % [bd["name"], int(bd["hp"]), int(bd.get("armor", 0))]
			chip.mouse_entered.connect(func(): _show_hover(btip, chip.global_position + Vector2(0, -70)))
			chip.mouse_exited.connect(_hide_hover)
			panel.add_child(chip)
			bx += 156

	var fb := _mk_button("Fight!  >>", Vector2(ARENA.x - 320, ARENA.y - 108), Vector2(300, 52), begin_fight)
	_style_green_button(fb)
	_build_field_hud()
	queue_redraw()

func _build_battle_ui() -> void:
	_clear_panel()
	top_label.visible = true
	_build_field_hud()

func _hud_bg() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.03, 0.80)
	sb.border_color = COL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb

# A titled black-backed list whose entries pop a tooltip on hover. Returns its
# pixel height so callers can stack panels. `entries` are {text, meta, hex}.
func _hud_list(title: String, entries: Array, tip_cb: Callable, pos: Vector2, from_bottom: bool) -> float:
	var s := "[b][color=#e8dcbe]%s[/color][/b]\n" % title
	for e in entries:
		s += "[url=%s][color=#%s]%s[/color][/url]\n" % [e["meta"], e["hex"], e["text"]]
	if entries.is_empty():
		s += "[color=#8a8069]— none yet —[/color]\n"
	var rows := maxi(1, entries.size()) + 1
	var h := float(rows) * 22.0 + 16.0
	var rl := RichTextLabel.new()
	rl.bbcode_enabled = true
	rl.text = s
	rl.fit_content = true
	rl.scroll_active = false
	rl.mouse_filter = Control.MOUSE_FILTER_STOP   # needs hover; PASS wouldn't fire meta signals
	rl.add_theme_font_size_override("normal_font_size", 15)
	rl.add_theme_font_size_override("bold_font_size", 15)
	rl.add_theme_stylebox_override("normal", _hud_bg())
	rl.size = Vector2(214, h)
	rl.position = Vector2(pos.x, (ARENA.y - 66.0 - h) if from_bottom else pos.y)
	if tip_cb.is_valid():
		var on_right := pos.x > ARENA.x * 0.5
		rl.meta_hover_started.connect(func(m):
			if on_right:
				# Below-left of the cursor, so it never covers the right-side panels.
				_show_hover(tip_cb.call(str(m)), get_global_mouse_position() + Vector2(0.0, 20.0), true)
			else:
				_show_hover(tip_cb.call(str(m)), rl.global_position + Vector2(rl.size.x + 8.0, 0.0)))
		rl.meta_hover_ended.connect(func(_m): _hide_hover())
	panel.add_child(rl)
	return h

func _relic_tip(id: String) -> String:
	var d: Dictionary = GameData.RELIC_DEFS.get(id, {})
	return "%s\n%s\nAffects: %s" % [str(d.get("name", id)), str(d.get("effect", "")), str(GameData.RELIC_SCOPE.get(id, "Everyone"))]

# Roster (bottom-left), relics and contracts (right) — all with hover tooltips.
func _build_field_hud() -> void:
	var unit_tip := Callable(self, "_unit_tooltip")
	# Your forces
	var comp := {}
	var order: Array = []
	for id in army:
		if GameData.UNITS[id].get("structure", false):
			continue
		if not comp.has(id):
			order.append(id)
		comp[id] = int(comp.get(id, 0)) + 1
	var forces: Array = []
	for id in order:
		var hex: String = "ffffff" if id == "peasant" else GameData.UNITS[id]["color"].to_html(false)
		forces.append({"text": "%d  %s" % [comp[id], _plural(GameData.UNITS[id]["name"], comp[id])], "meta": id, "hex": hex})
	_hud_list("Your forces", forces, unit_tip, Vector2(16, 0), true)
	# Relics (right)
	var rrelics: Array = []
	for id in relics:
		rrelics.append({"text": str(GameData.RELIC_DEFS[id]["name"]), "meta": id, "hex": "f2ab2e"})
	var rh := _hud_list("Relics", rrelics, Callable(self, "_relic_tip"), Vector2(ARENA.x - 230, 56), false)
	# Contracts (right, below relics)
	var rcon: Array = []
	for id in contracts:
		rcon.append({"text": str(GameData.GUILD_NAMES.get(id, GameData.UNITS[id]["name"])), "meta": id, "hex": "e8dcbe"})
	_hud_list("Contracts", rcon, unit_tip, Vector2(ARENA.x - 230, 56.0 + rh + 12.0), false)

func _mk_button(text: String, pos: Vector2, size: Vector2, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = size
	b.pressed.connect(cb)
	_style_button(b)
	panel.add_child(b)
	return b

# A clickable chip: name in cream, price in gold. `on_press` fires on left-press,
# `on_release` (if given) on left-release — so a wall chip starts a ghost on press
# and places it on release wherever you dragged to.
func _priced_chip(nm: String, cost_text: String, on_press: Callable, enabled: bool, on_release: Callable = Callable()) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _card_style())
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	if not enabled:
		pc.modulate = Color(1, 1, 1, 0.5)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 8)
	pc.add_child(h)
	var l := Label.new()
	l.text = nm
	l.add_theme_color_override("font_color", COL_INK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(l)
	if cost_text != "":
		var c := Label.new()
		c.text = cost_text
		c.add_theme_color_override("font_color", COL_GOLD)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(c)
	if enabled:
		pc.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
				if e.pressed:
					on_press.call()
				elif on_release.is_valid():
					on_release.call())
	return pc

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
	_hide_hover()
	for c in panel.get_children():
		panel.remove_child(c)
		c.queue_free()

func _update_top() -> void:
	var units := 0
	for id in army:
		if id in PEASANT_IDS or id in SPECIALIST_IDS:
			units += 1
	var income := 10 + 2 * units
	var s := "[b][color=#f2ab2e]Gold  %d[/color]\n[color=#8fd06a]Income  +%d/turn[/color]\n[color=#e8dcbe]Wave  %d/%d[/color][/b]" % [gold, income, battle_num, MAX_BATTLES]
	if phase == Phase.BATTLE:
		s += "\n[color=#cfc6ad]Units %d · Enemies %d[/color]" % [peasants.size(), enemies.size()]
	# Transient messages only clutter the menus, not the battlefield HUD.
	if info_text != "" and (phase == Phase.SHOP or phase == Phase.GUILD):
		s += "\n[color=#b7ad92]%s[/color]" % info_text
	top_label.text = s

func _update_hover() -> void:
	if _ui_hover_active:
		return   # a panel/card tooltip is showing — don't fight it
	var mp := get_global_mouse_position()
	var found = null
	for u in peasants:
		if is_instance_valid(u) and u.hp > 0.0 and not u.invulnerable and mp.distance_to(u.global_position) <= u.radius + 5.0:
			found = u
			break
	if found == null:
		for u in enemies:
			if is_instance_valid(u) and u.hp > 0.0 and mp.distance_to(u.global_position) <= u.radius + 5.0:
				found = u
				break
	if found == null:
		hover_label.visible = false
		return
	var txt := ""
	if found.is_structure:
		# Walls/keep: just the name and how much punishment it can take.
		txt = "%s\nHealth: %d / %d" % [found.display_name, int(ceil(found.hp)), int(found.max_hp)]
		if found.armor > 0.0:
			txt += "\nArmor: %d" % int(found.armor)
		if found.type_id != "castle" and found.type_id != "church" and phase == Phase.DEPLOY:
			txt += "\nRight-click to rotate"
	else:
		var rng: float = found.attack_range
		var side := "Your unit" if found.team == 0 else "Enemy"
		txt = "%s (%s)\nHP: %d / %d" % [found.display_name, side, int(ceil(found.hp)), int(found.max_hp)]
		if found.damage > 0.0:
			txt += "\nDamage: %d\nAtk speed: %.1f / s" % [int(found.damage), 1.0 / maxf(found.attack_cooldown, 0.01)]
		txt += "\nRange: %s" % ("melee" if rng <= 12.0 else str(int(rng)))
		if found.armor > 0.0:
			txt += "\nArmor: %d" % int(found.armor)
		if found.heals:
			txt += "\nHeals allies · light attack"
	hover_label.text = txt
	_position_hover(mp + Vector2(14, 12))

# ---------------------------------------------------------------- actions

func _buy(id: String) -> void:
	var uname: String = GameData.UNITS[id]["name"]
	var cost: int = GameData.UNITS[id]["cost"]
	if id in PEASANT_IDS:
		if recruits_left <= 0:
			info_text = "No recruit slots left this cycle."
		elif gold < cost:
			info_text = "Not enough gold for %s." % uname
		else:
			gold -= cost
			recruits_left -= 1
			recruited_this_cycle.append(id)
			army.append(id)
			info_text = "%s joins your service." % uname
	elif id in SPECIALIST_IDS:
		if not (id in contracts):
			info_text = "Sign the %s guild's contract first." % uname
		elif recruits_left <= 0:
			info_text = "No recruit slots left this cycle."
		elif gold < cost:
			info_text = "Not enough gold for %s." % uname
		else:
			gold -= cost
			recruits_left -= 1
			recruited_this_cycle.append(id)
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

func _unrecruit(i: int) -> void:
	if i < 0 or i >= recruited_this_cycle.size():
		return
	var uid: String = recruited_this_cycle[i]
	recruited_this_cycle.remove_at(i)
	army.erase(uid)
	recruits_left += 1
	if uid in SPECIALIST_IDS:
		gold += int(GameData.UNITS[uid]["cost"])   # refund the hire
	info_text = "Removed %s." % GameData.UNITS[uid]["name"]
	_build_shop_ui()
	_update_top()

func _buy_relic(id: String) -> void:
	if id in relics:
		return
	var cost: int = int(GameData.RELIC_DEFS[id]["cost"])
	if gold >= cost:
		gold -= cost
		relics.append(id)
		info_text = "Acquired %s." % GameData.RELIC_DEFS[id]["name"]
		_refresh_relic_dock()
	else:
		info_text = "Not enough gold."
	_build_shop_ui()
	_update_top()

func spawn_projectile(from: Vector2, to: Vector2, col: Color) -> void:
	_projectiles.append({"from": from, "to": to, "t": 0.0, "dur": 0.13, "col": col})

func _process(_delta: float) -> void:
	if _buy_id != "":
		_mouse = get_global_mouse_position()   # ghost follows the cursor as you drag
	if not _projectiles.is_empty():
		for p in _projectiles:
			p["t"] += _delta
		_projectiles = _projectiles.filter(func(p): return p["t"] < p["dur"])
		queue_redraw()
	if phase == Phase.BATTLE:
		_update_top()
	if phase == Phase.DEPLOY or phase == Phase.BATTLE or _shop_viewing:
		_update_hover()
		queue_redraw()   # keep the grid + building labels live

func _show_hover(text: String, at: Vector2 = Vector2(-9999, -9999), left_of: bool = false) -> void:
	_ui_hover_active = true   # keep the per-frame unit-hover from stealing this
	hover_label.text = text
	var anchor: Vector2 = (get_global_mouse_position() + Vector2(14, 12)) if at.x < -9000.0 else at
	_position_hover(anchor, left_of)

# Size the tooltip to its text and keep it fully on-screen — flipping it above
# the anchor near the bottom, and placing it to the LEFT of the anchor when asked
# (so right-edge panels don't get covered by their own tooltip).
func _position_hover(anchor: Vector2, left_of: bool = false) -> void:
	hover_label.reset_size()   # shrink the box to fit the text (no dead space)
	var sz: Vector2 = hover_label.size
	var p: Vector2 = anchor
	if left_of:
		p.x = anchor.x - sz.x        # tooltip sits to the left of the anchor
	elif p.x + sz.x > ARENA.x - 4.0:
		p.x = anchor.x - sz.x - 24.0   # flip to the left of the pointer
	if p.y + sz.y > ARENA.y - 4.0:
		p.y = anchor.y - sz.y - 24.0   # flip above the pointer
	p.x = clampf(p.x, 4.0, ARENA.x - sz.x - 4.0)
	p.y = clampf(p.y, 4.0, ARENA.y - sz.y - 4.0)
	hover_label.position = p
	hover_label.visible = true

func _hide_hover() -> void:
	_ui_hover_active = false
	if hover_label:
		hover_label.visible = false

func _refresh_relic_dock() -> void:
	# The on-field relic dock was clutter and couldn't be hovered mid-battle;
	# relics still apply, they're just not drawn on the battlefield anymore.
	if relic_dock == null:
		return
	for c in relic_dock.get_children():
		c.queue_free()
	relic_dock.visible = false

# ---------------------------------------------------------------- helpers / background

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, ARENA), Color(0.30, 0.42, 0.20))                       # field
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

	# Only the keep and church carry a permanent label — the church above it and
	# the keep below, so their names never collide. Walls stay unlabelled (hover
	# shows their name and health instead).
	if phase == Phase.DEPLOY or phase == Phase.BATTLE or _shop_viewing:
		var font := ThemeDB.fallback_font
		if font != null:
			var col := Color(0.97, 0.94, 0.8)
			for p in peasants:
				if not is_instance_valid(p) or not p.is_structure:
					continue
				var half_h: float = (p.foot_h if p.foot_h > 0.0 else p.radius * 2.0) * 0.5
				if p.type_id == "church":
					var ch := "×%d fallen" % total_fallen
					draw_string(font, Vector2(p.global_position.x - 80.0, p.global_position.y - half_h - 6.0), ch, HORIZONTAL_ALIGNMENT_CENTER, 160.0, 13, col)
				elif p.type_id == "castle":
					draw_string(font, Vector2(p.global_position.x - 80.0, p.global_position.y + half_h + 18.0), "Castle Keep", HORIZONTAL_ALIGNMENT_CENTER, 160.0, 13, col)

	# In-flight projectiles for ranged attacks (a dart with a short trail).
	for pr in _projectiles:
		var f: float = clampf(pr["t"] / pr["dur"], 0.0, 1.0)
		var tip: Vector2 = pr["from"].lerp(pr["to"], f)
		var tail: Vector2 = pr["from"].lerp(pr["to"], maxf(0.0, f - 0.25))
		draw_line(tail, tip, pr["col"], 2.0)
		draw_circle(tip, 3.0, pr["col"])

	# --- Drag previews (green = valid, yellow = swaps a spot, red = blocked) ---
	var mgx := int((FENCE_X - 1.0) / TILE)
	if _buy_id != "":
		var sp := _span(_buy_id)
		var gx := clampi(int(_mouse.x / TILE), 0, GRID_COLS - sp.x)
		var gy := clampi(int(_mouse.y / TILE), 0, GRID_ROWS - sp.y)
		_draw_footprint_preview(gx, gy, sp, 0 if _footprint_free(gx, gy, sp) else 2)
	elif _dragging and not _drag_units.is_empty() and is_instance_valid(_grab):
		var delta := Vector2i(clampi(int(_mouse.x / TILE), 0, mgx), clampi(int(_mouse.y / TILE), 0, GRID_ROWS - 1)) - _tile_of(_drag_origins[_grab])
		var excl := {}
		for u in _drag_units:
			excl[u] = true
		var single := _drag_units.size() == 1
		for u in _drag_units:
			var nt := _tile_of(_drag_origins[u]) + delta
			var inb := nt.x >= 0 and nt.x <= mgx and nt.y >= 0 and nt.y < GRID_ROWS
			var st := 2
			if inb and not _tile_occupied(nt.x, nt.y):
				var occ = _unit_at_tile(nt, excl)
				if occ == null:
					st = 0
				elif single:
					st = 1   # a single unit swaps with whoever's there
			_draw_tile_preview(nt, st)
	elif _dragging and _grab != null and _grab.is_structure and _grab.has_meta("bref"):
		var b = _grab.get_meta("bref")
		var sp2 := _bspan(b)
		var gx2 := clampi(int(_mouse.x / TILE), 0, GRID_COLS - sp2.x)
		var gy2 := clampi(int(_mouse.y / TILE), 0, GRID_ROWS - sp2.y)
		var st2 := 2
		if _footprint_free(gx2, gy2, sp2, b):
			st2 = 0
		else:
			var swp = _wall_covering(gx2, gy2, b)
			if swp != null and _bspan(swp) == sp2:
				st2 = 1   # swap with a same-size wall
		_draw_footprint_preview(gx2, gy2, sp2, st2)
	elif _dragging and _grab == null and _buy_id == "":
		draw_rect(_sel_rect, Color(1, 1, 0.4, 0.12))
		draw_rect(_sel_rect, Color(1, 1, 0.4, 0.7), false, 1.5)

const _PREVIEW_FILL := [Color(0.4, 0.9, 0.4, 0.35), Color(0.95, 0.85, 0.3, 0.4), Color(0.95, 0.35, 0.3, 0.35)]

func _draw_tile_preview(t: Vector2i, state: int) -> void:
	var r := Rect2(t.x * TILE, t.y * TILE, TILE, TILE)
	draw_rect(r, _PREVIEW_FILL[state])
	draw_rect(r, Color(1, 1, 1, 0.6), false, 1.5)

func _draw_footprint_preview(gx: int, gy: int, sp: Vector2i, state: int) -> void:
	var r := Rect2(gx * TILE, gy * TILE, sp.x * TILE, sp.y * TILE)
	draw_rect(r, _PREVIEW_FILL[state])
	draw_rect(r, Color(1, 1, 1, 0.7), false, 2.0)
