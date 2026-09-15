class_name Unit
extends Node2D

# One combatant (peasant, enemy, or structure). Drawn as a stick figure in _draw().
# Behaviour: find nearest enemy -> move into range (unless Hold) -> attack on cooldown.

const ENGAGE_RADIUS := 120.0          # how far a unit chases a foe that nears its post
const AGGRO_RADIUS := 95.0            # a foe this close to the unit itself is engaged, wherever it strays
const NEIGHBOR_DIST := 62.0           # social aggro: a foe a comrade this close is fighting, I fight too

var main = null                       # reference to Main (owns the unit arrays)
var team: int = 0                     # 0 = peasant, 1 = enemy
var type_id: String = "farmer"
var display_name: String = "Farmer"
var max_hp: float = 30.0
var hp: float = 30.0
var damage: float = 5.0
var attack_range: float = 6.0
var attack_cooldown: float = 1.0
var move_speed: float = 55.0
var radius: float = 7.0
var is_structure: bool = false
var foot_w: float = 0.0                # footprint px width (structures); 0 => square of radius*2
var foot_h: float = 0.0                # footprint px height
var body_color: Color = Color(0.78, 0.80, 0.85)
var gold_drop: int = 0
var armor: float = 0.0                 # flat damage reduction (min 1 damage taken)
var pierce: bool = false               # attacks ignore target armor
var aura: String = ""                  # "", "heal", or "haste"
var aura_range: float = 0.0
var aura_value: float = 0.0            # heal = hp/sec to allies; haste = attack-speed bonus
var is_beast: bool = false
var applies_burn: bool = false
var applies_slow: bool = false
var knockback: float = 0.0
var bonus_beast: float = 1.0          # damage multiplier vs beast enemies
var invulnerable: bool = false        # cannot be damaged or knocked (e.g. the church)
var behavior: String = ""             # "" or "diver" (target the backline)
var crit_chance: float = 0.0          # 0..1 chance to crit
var crit_mult: float = 1.5            # crit damage multiplier
var heals: bool = false               # attacks heal the most-hurt nearby ally
var heal_amount: float = 0.0
var heal_range: float = 0.0           # reach for healing (longer than the attack range)
var evasion: float = 0.0              # 0..1 chance to dodge a hit (rare)
var targets: String = ""             # "" units; "structures" = go for walls/castle

var burn_time: float = 0.0
var burn_dps: float = 0.0
var slow_time: float = 0.0

var command_point: Vector2 = Vector2.ZERO   # where you've ordered this unit to hold
var _home := Vector2(INF, INF)               # structures lock here — nothing can shove them
var engaging: bool = false                   # currently committed to a foe (drives social aggro)
var being_dragged: bool = false              # player is dragging this structure right now
var attacker = null                          # who last hit me (so comrades can rally to a struck wall)
var attacker_time: float = 0.0               # seconds the call-for-help stays warm
var selected: bool = false
var target = null
var _cd: float = 0.0
var _flash: float = 0.0
var _dead: bool = false

func setup(def: Dictionary, _team: int, _main) -> void:
	main = _main
	team = _team
	type_id = def.get("id", "unit")
	display_name = def.get("name", "Unit")
	max_hp = float(def.get("hp", 30))
	hp = max_hp
	damage = float(def.get("damage", 5))
	attack_range = float(def.get("range", 6))
	attack_cooldown = float(def.get("cooldown", 1.0))
	move_speed = float(def.get("speed", 55))
	radius = float(def.get("radius", 7))
	is_structure = bool(def.get("structure", false))
	gold_drop = int(def.get("drop", 0))
	armor = float(def.get("armor", 0))
	pierce = bool(def.get("pierce", false))
	aura = def.get("aura", "")
	aura_range = float(def.get("aura_range", 0))
	aura_value = float(def.get("aura_value", 0))
	is_beast = bool(def.get("beast", false))
	invulnerable = bool(def.get("invuln", false))
	applies_burn = bool(def.get("applies_burn", false))
	applies_slow = bool(def.get("applies_slow", false))
	knockback = float(def.get("knockback", 0))
	bonus_beast = float(def.get("bonus_beast", 1.0))
	behavior = def.get("behavior", "")
	heals = bool(def.get("heals", false))
	heal_amount = float(def.get("heal_amount", 0))
	heal_range = float(def.get("heal_range", attack_range))
	evasion = float(def.get("evasion", 0))
	targets = def.get("targets", "")
	body_color = def.get("color", Color(0.78, 0.80, 0.85))
	_cd = randf() * attack_cooldown

func _process(delta: float) -> void:
	# Structures are immovable: pin them to where they were placed so no
	# knockback or jostling can ever slide a wall/castle/church off its tiles.
	if is_structure and not being_dragged:
		if _home == Vector2(INF, INF):
			_home = global_position
		elif global_position != _home:
			global_position = _home
	if attacker_time > 0.0:
		attacker_time -= delta
	if _flash > 0.0:
		_flash -= delta
		queue_redraw()

# Move a structure to a new spot and re-pin it there (used when the player drags a wall).
func relocate(pos: Vector2) -> void:
	global_position = pos
	command_point = pos
	_home = pos
	queue_redraw()   # footprint may have changed size/orientation — repaint it

# Remember who just struck me so nearby allies can rally to my defence.
func note_attacker(who) -> void:
	attacker = who
	attacker_time = 1.0

func _physics_process(delta: float) -> void:
	if _dead or is_structure or main == null:
		return
	if not main.is_fighting():   # frozen during the deploy phase
		return
	_cd -= delta

	# Damage-over-time: burn ticks down HP.
	if slow_time > 0.0:
		slow_time -= delta
	var dot := false
	if burn_time > 0.0:
		burn_time -= delta
		hp -= burn_dps * delta
		dot = true
	if dot:
		queue_redraw()
		if hp <= 0.0:
			die()
			return

	# --- Acquire / re-acquire a target ---
	if team == 0:
		# Your units always fight the nearest threat — including whoever is
		# currently attacking them — so they never sit still and get chewed up.
		if heals:
			var ht = main.get_heal_target(self)
			target = ht if ht != null else main.get_nearest_enemy(self)
		else:
			target = main.get_nearest_enemy(self)
	elif target == null or not is_instance_valid(target) or target.hp <= 0.0:
		# Enemies commit to a target until it dies, then re-pick.
		target = null
		if behavior == "diver":
			target = main.get_backline_peasant()
		elif targets == "structures":
			target = main.get_nearest_structure(self)
		if target == null:
			target = main.get_nearest_enemy(self)

	# A wall directly ahead must be broken through first (structure-hunters skip this).
	if team == 1 and targets != "structures":
		var wall = main.structure_ahead(self)
		if wall != null:
			target = wall

	# --- Single ally pass: separation, auras, and a social-aggro candidate ---
	var sep := Vector2.ZERO
	var haste := 0.0
	var heal_rate := 0.0
	var social = null   # a foe a nearby comrade (or a struck wall) is dealing with
	for a in main.get_allies(self):
		if a == self or not is_instance_valid(a):
			continue
		var d: Vector2 = global_position - a.global_position
		var dl := d.length()
		var mind: float = radius + a.radius + 2.0
		if dl > 0.001 and dl < mind and not a.is_structure:
			sep += d / dl * (mind - dl)
		if a.aura != "" and dl <= a.aura_range:
			if a.aura == "haste":
				haste += a.aura_value
			elif a.aura == "heal":
				heal_rate += a.aura_value
		# Social aggro (fighting units only): rally to a comrade already engaged,
		# or to a wall/keep currently under attack, if it's about a tile away.
		if team == 0 and not heals and social == null:
			var near_thr: float = NEIGHBOR_DIST + (a.radius if a.is_structure else 0.0)
			if dl <= near_thr:
				if a.is_structure and a.attacker_time > 0.0 and is_instance_valid(a.attacker) and a.attacker.team == 1 and a.attacker.hp > 0.0:
					social = a.attacker
				elif a.engaging and is_instance_valid(a.target) and a.target.team == 1:
					social = a.target
	if sep != Vector2.ZERO:
		global_position += sep * 0.5
	if heal_rate > 0.0 and hp < max_hp:
		hp = minf(max_hp, hp + heal_rate * delta)
		queue_redraw()

	# --- Decide engagement (your non-healer units drive & spread social aggro) ---
	engaging = false
	if team == 0 and not heals and is_instance_valid(target) and target.team == 1:
		var td := global_position.distance_to(target.global_position)
		if td <= AGGRO_RADIUS or target.global_position.distance_to(command_point) <= ENGAGE_RADIUS:
			engaging = true
		elif social != null:
			target = social
			engaging = true

	var has_t: bool = target != null and is_instance_valid(target)
	var healing: bool = heals and has_t and target.team == team
	var eff_range: float = heal_range if healing else attack_range
	var dist: float = INF
	var reach: float = eff_range + radius
	if has_t:
		dist = global_position.distance_to(target.global_position)
		reach = eff_range + radius + target.radius

	# Act on whatever is in range: healers mend a hurt ally, everyone else strikes.
	if has_t and dist <= reach and _cd <= 0.0:
		_cd = attack_cooldown / (1.0 + haste)
		if healing:
			target.hp = minf(target.max_hp, target.hp + heal_amount)
			target.queue_redraw()
			if main:
				main.spawn_float_text(target.global_position + Vector2(0, -target.radius - 4), "+" + str(int(heal_amount)), Color(0.5, 0.95, 0.5))
		else:
			var dmg := damage
			if bonus_beast > 1.0 and target.is_beast:
				dmg *= bonus_beast
			var is_crit := crit_chance > 0.0 and randf() < crit_chance
			if is_crit:
				dmg *= crit_mult
			if team == 1:
				target.note_attacker(self)
			# Ranged attackers loose a visible shot instead of hitting invisibly.
			if attack_range >= 20.0 and main:
				main.spawn_projectile(global_position, target.global_position, body_color.lerp(Color.WHITE, 0.3))
			target.take_damage(dmg, pierce, is_crit)
			if applies_burn:
				target.ignite(3.0, 3.0)
			if applies_slow:
				target.slow_for(1.5)
			if knockback > 0.0 and not target.is_structure:
				var kb: Vector2 = target.global_position - global_position
				var kl := kb.length()
				if kl > 0.001:
					target.global_position += kb / kl * knockback

	# Move toward the goal, routing around walls instead of through them.
	var goal = _movement_goal(has_t, dist, reach)
	if goal != null:
		var spd := move_speed * (0.5 if slow_time > 0.0 else 1.0)
		_step_toward(goal, spd * delta)

	# Final guarantee: never rest inside a wall — separation, knockback, or a
	# tight squeeze can nudge a body in, so eject it to the nearest open edge.
	_eject_from_walls()

func _eject_from_walls() -> void:
	if main == null:
		return
	var guard := 0
	var b = main.blocking_wall(global_position, radius, self)
	while b != null and guard < 5:
		var w: float = b.foot_w if b.foot_w > 0.0 else b.radius * 2.0
		var h: float = b.foot_h if b.foot_h > 0.0 else b.radius * 2.0
		var rect := Rect2(b.global_position - Vector2(w, h) * 0.5, Vector2(w, h)).grow(radius * 0.6)
		var to_left: float = global_position.x - rect.position.x
		var to_right: float = rect.end.x - global_position.x
		var to_top: float = global_position.y - rect.position.y
		var to_bot: float = rect.end.y - global_position.y
		var m: float = min(min(to_left, to_right), min(to_top, to_bot))
		# Nudge just PAST the edge — landing exactly on it still counts as inside
		# (has_point is inclusive), which would pin the unit and stop it sliding.
		if m == to_left:
			global_position.x = rect.position.x - 0.5
		elif m == to_right:
			global_position.x = rect.end.x + 0.5
		elif m == to_top:
			global_position.y = rect.position.y - 0.5
		else:
			global_position.y = rect.end.y + 0.5
		guard += 1
		b = main.blocking_wall(global_position, radius, self)

func _movement_goal(has_t: bool, dist: float, reach: float):
	# Enemies always advance on the nearest target.
	if team == 1:
		return target.global_position if (has_t and dist > reach) else null
	# Already in striking (or healing) range: stand and act.
	if has_t and dist <= reach:
		return null
	# Committed to a foe (directly, socially, or via a struck wall) — or a
	# healer moving to a hurt ally: close the distance. Otherwise hold post.
	if has_t and (engaging or (heals and target.team == team)):
		return target.global_position
	if global_position.distance_to(command_point) > 8.0:
		return command_point
	return null

# Advance toward a goal but never walk through a wall. If the direct step is
# blocked, head for the wall corner that best rounds toward the goal (a little
# visibility-graph hop), so the unit actually paths around instead of jamming
# against the face or a corner.
func _step_toward(goal: Vector2, maxd: float) -> void:
	var to_goal: Vector2 = goal - global_position
	var dl := to_goal.length()
	if dl < 0.001:
		return
	var dir: Vector2 = to_goal / dl
	var d: float = minf(maxd, dl)
	if main == null or not main.wall_blocks(global_position + dir * d, radius, self):
		global_position += dir * d
		return
	var b = main.blocking_wall(global_position + dir * d, radius, self)
	if b == null:
		return
	var w: float = b.foot_w if b.foot_w > 0.0 else b.radius * 2.0
	var h: float = b.foot_h if b.foot_h > 0.0 else b.radius * 2.0
	var ex: float = w * 0.5 + radius + 3.0
	var ey: float = h * 0.5 + radius + 3.0
	# Head for the free corner we can actually step toward that minimises
	# (walk to it + corner to goal) — i.e. round the near side of the wall.
	var best_step := Vector2.ZERO
	var best_cost := INF
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var c: Vector2 = b.global_position + Vector2(sx * ex, sy * ey)
			if main.wall_blocks(c, radius, self):
				continue
			var cdir: Vector2 = c - global_position
			var cl := cdir.length()
			if cl < 0.001:
				continue
			var step: Vector2 = cdir / cl * minf(d, cl)
			if main.wall_blocks(global_position + step, radius, self):
				continue   # can't head that way without clipping the wall
			var cost: float = cl + c.distance_to(goal)
			if cost < best_cost:
				best_cost = cost
				best_step = step
	if best_step != Vector2.ZERO:
		global_position += best_step

func take_damage(amount: float, pierce_flag: bool = false, is_crit: bool = false) -> void:
	if _dead or invulnerable:
		return
	if evasion > 0.0 and randf() < evasion:
		if main:
			main.spawn_float_text(global_position + Vector2(0, -radius - 4), "miss", Color(0.82, 0.82, 0.88))
		return
	var dealt := amount if pierce_flag else maxf(1.0, amount - armor)
	hp -= dealt
	_flash = 0.12
	if main and dealt >= 3.0:
		var col := Color(1, 0.5, 0.15) if is_crit else Color(1, 0.92, 0.45)
		var txt := str(int(round(dealt))) + ("!" if is_crit else "")
		main.spawn_float_text(global_position + Vector2(0, -radius - 4), txt, col)
	queue_redraw()
	if hp <= 0.0:
		die()

func ignite(dps: float, t: float) -> void:
	if _dead:
		return
	burn_dps = maxf(burn_dps, dps)
	burn_time = maxf(burn_time, t)

func slow_for(t: float) -> void:
	slow_time = maxf(slow_time, t)

func die() -> void:
	if _dead:
		return
	_dead = true
	if main:
		main.on_unit_died(self)
	# Fade-and-pop the corpse out (logic already removed it from the arrays).
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.18)
	t.parallel().tween_property(self, "scale", Vector2(1.5, 1.5), 0.18)
	t.tween_callback(queue_free)

func _draw() -> void:
	# HP bar — only while damaged, so full-health units/buildings stay clean.
	if hp < max_hp and not invulnerable:
		var w: float = foot_w if (is_structure and foot_w > 0.0) else radius * 2.0
		var half_h: float = (foot_h * 0.5) if (is_structure and foot_h > 0.0) else radius
		var frac := clampf(hp / max_hp, 0.0, 1.0)
		var bar_y := -half_h - 9.0
		draw_rect(Rect2(-w * 0.5, bar_y, w, 3.0), Color(0, 0, 0, 0.5))
		var bar_col := Color(0.25, 0.9, 0.3) if team == 0 else Color(0.9, 0.3, 0.2)
		draw_rect(Rect2(-w * 0.5, bar_y, w * frac, 3.0), bar_col)

	# Hit flash: briefly wash the body toward white when struck.
	var c := body_color
	if _flash > 0.0:
		c = body_color.lerp(Color.WHITE, clampf(_flash / 0.12, 0.0, 1.0) * 0.85)

	if is_structure:
		var w: float = foot_w if foot_w > 0.0 else radius * 2.0
		var h: float = foot_h if foot_h > 0.0 else radius * 2.0
		var rect := Rect2(-w * 0.5, -h * 0.5, w, h)
		draw_rect(rect, c)
		draw_rect(rect, Color(0.25, 0.16, 0.08), false, 2.0)
		return

	# Stick figure
	draw_circle(Vector2(0, -radius * 0.5), radius * 0.45, c)          # head
	draw_line(Vector2(0, -radius * 0.1), Vector2(0, radius * 0.6), c, 2.0)   # body
	draw_line(Vector2(-radius * 0.5, radius * 0.15), Vector2(radius * 0.5, radius * 0.15), c, 2.0)  # arms
	draw_line(Vector2(0, radius * 0.6), Vector2(-radius * 0.4, radius), c, 2.0)  # left leg
	draw_line(Vector2(0, radius * 0.6), Vector2(radius * 0.4, radius), c, 2.0)   # right leg

	# Selection ring when this unit is currently selected.
	if selected:
		draw_arc(Vector2.ZERO, radius + 4.0, 0.0, TAU, 20, Color(1, 1, 0.4, 0.9), 1.6)
