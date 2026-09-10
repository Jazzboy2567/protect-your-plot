class_name GameData
extends RefCounted

# Central stat tables + wave generator. Accessed statically, e.g. GameData.UNITS["farmer"].
# team is decided at spawn time, not here. "structure": true means it does not move/attack.

const UNITS := {
	# --- Peasants (your side) — greyish / blue-grey stick figures ---
	"farmer":     {"id":"farmer","name":"Farmer","hp":30,"damage":5,"range":6,"cooldown":1.0,"speed":55,"radius":7,"cost":10,"color":Color(0.80,0.82,0.86)},
	"militia":    {"id":"militia","name":"Militia","hp":48,"damage":9,"range":8,"cooldown":0.9,"speed":60,"radius":8,"cost":20,"color":Color(0.66,0.72,0.85)},
	"archer":     {"id":"archer","name":"Archer","hp":24,"damage":8,"range":150,"cooldown":1.1,"speed":50,"radius":7,"cost":25,"color":Color(0.60,0.80,0.62)},
	"woodcutter": {"id":"woodcutter","name":"Woodcutter","hp":65,"damage":15,"range":9,"cooldown":1.4,"speed":45,"radius":9,"cost":35,"pierce":true,"color":Color(0.72,0.62,0.50)},
	"baker":      {"id":"baker","name":"Baker","hp":34,"damage":4,"range":7,"cooldown":1.2,"speed":52,"radius":8,"cost":30,"aura":"heal","aura_range":95,"aura_value":5,"color":Color(0.86,0.78,0.55)},
	"monk":       {"id":"monk","name":"Monk","hp":34,"damage":4,"range":7,"cooldown":1.2,"speed":52,"radius":8,"cost":35,"aura":"haste","aura_range":95,"aura_value":0.30,"color":Color(0.70,0.66,0.80)},
	"barricade":  {"id":"barricade","name":"Barricade","hp":220,"damage":0,"range":0,"cooldown":1.0,"speed":0,"radius":14,"cost":30,"structure":true,"color":Color(0.50,0.35,0.20)},

	# --- Enemies (right side) — reddish ---
	"sheep":       {"id":"sheep","name":"Sheep","hp":18,"damage":2,"range":6,"cooldown":1.2,"speed":45,"radius":8,"drop":3,"color":Color(0.90,0.90,0.90)},
	"rat":         {"id":"rat","name":"Plague Rat","hp":12,"damage":3,"range":5,"cooldown":0.7,"speed":72,"radius":5,"drop":2,"color":Color(0.55,0.30,0.35)},
	"bandit":      {"id":"bandit","name":"Bandit","hp":36,"damage":7,"range":7,"cooldown":1.0,"speed":55,"radius":8,"drop":6,"armor":1,"color":Color(0.80,0.35,0.30)},
	"ram":         {"id":"ram","name":"Ram","hp":58,"damage":12,"range":8,"cooldown":1.3,"speed":85,"radius":10,"drop":9,"armor":2,"color":Color(0.85,0.55,0.30)},
	"knight":      {"id":"knight","name":"Knight","hp":130,"damage":18,"range":9,"cooldown":1.3,"speed":40,"radius":11,"drop":22,"armor":6,"color":Color(0.85,0.25,0.25)},
	"black_death": {"id":"black_death","name":"The Black Death","hp":650,"damage":26,"range":13,"cooldown":1.1,"speed":30,"radius":22,"drop":70,"armor":8,"color":Color(0.50,0.10,0.35)},
}

# Build the enemy wave for battle number n (1-based). Every 4th battle is a boss.
static func generate_wave(n: int) -> Array:
	var w: Array = []
	if n % 4 == 0:
		w.append("black_death")
		for i in 2 + n:
			w.append("rat")
		for i in 3:
			w.append("bandit")
		for i in maxi(0, n / 4 - 1):
			w.append("knight")
		return w
	for i in 2 + n:
		w.append("sheep")
	for i in 1 + n:
		w.append("rat")
	for i in maxi(0, n - 1):
		w.append("bandit")
	for i in maxi(0, n - 2):
		w.append("ram")
	for i in maxi(0, (n - 2) / 2):
		w.append("knight")
	return w
