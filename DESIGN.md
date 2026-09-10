# Protect your Plot — Game Design Doc

A **squad-command lane-defense autobattler**. You are a **landowner**: hire peasants
with tax money, position them behind walls, set their behaviour, then watch them
auto-battle waves of beasts, soldiers, and plague. Slight top-down view (like
*How Many Dudes?*). Loot from dead enemies + taxes fund the next round.

- **Working title:** Protect your Plot
- **Engine:** Godot 4.7 (GDScript)
- **Platform:** Android (Google Play) first
- **Art:** placeholder stick figures (grey = your side, red = enemies), drawn in code
- **Monetization (later):** rewarded video + interstitials (AdMob); no paid user acquisition

---

## Core loop

1. **War Council (shop)** — spend gold to hire units / build structures. Set stance.
2. **Battle** — peasants auto-fight an incoming wave. You watch + use landowner powers.
3. **Loot** — each dead enemy drops gold; surviving peasants earn tax income.
4. Every **4th battle** is a **boss season**. Repeat, escalating.

Survivors persist between battles (healed to full). Dead peasants are gone.
Death spiral guard: if your roster empties, free serfs volunteer.

---

## The player = the Landowner

You command from above; you don't fight. Framing turns "protect your plot" literal —
peasants are hired help *and* your income source, so protecting them protects your economy.

**Landowner powers (active, on cooldown):**
- **Rally!** — temporary army-wide damage buff. *(in MVP)*
- *(later)* Levy — spend gold for an instant unit; Decree — rally/heal.

**Economy pillars:**
- One **gold** currency. Sources: **tax** (steady, scales with surviving peasants/buildings)
  + **loot** drops (bursty).
- *(later)* **Tax-rate slider:** high tax = more gold but grumpier/weaker peasants;
  low tax = loyal, stronger peasants, less gold.
- *(later)* **Plot upgrades:** permanent estate buildings (manor, stone walls, watchtower, chapel).

---

## Battlefield + command system (the unique hook)

- **Right:** enemies spawn and advance left.
- **Left:** your camp + **structures** units fight behind (archers shoot over barricades).
- **Per-unit stances:**
  - **Aggressive** — charge out, seek nearest enemy.
  - **Hold** — stand ground, attack only what comes into range (great behind walls).
  - *(later)* **Defend** — guard a structure/ally, chase only within a leash.
  - *(later)* **Follow** — escort another unit (e.g. serfs screen an archer).

---

## Army — peasant classes

| Class | Role | Notes |
|---|---|---|
| **Farmer** | Swarm anchor | Cheap; your crowd. Many effects scale off farmers. |
| **Serf** | Meat shield | Near-free cannon fodder / body-block. |
| **Pitchfork Militia** | Front-line melee | "Mob mentality": damage scales with adjacent peasants. |
| **Archer** | Ranged DPS | Fragile; wants a front line to hide behind. |
| **Blacksmith** | Support (armor) | Buffs nearby armor/damage. |
| **Hunter** | Anti-beast | Bonus vs sheep/rams/rats/wolves. |
| **Woodcutter** | Anti-armor | Slow heavy hits; shreds soldiers/knights. |
| **Baker** | Heal aura | Passive regen for nearby peasants. |
| **Fisherman** | Control | Net slows chargers (Ram/Cavalry). |
| **Monk** | Morale aura | +attack speed to surrounding peasants. |
| **Herbalist** | Anti-plague | Cleanses disease; hard-counters plague rats. |
| **Bell-Ringer** | Burst rally | Periodic army-wide surge. |
| **Mason** | Zone control | Builds a temporary barricade. |
| **Torchbearer** | AoE burn | Extra vs swarms/beasts. |
| **Plague Doctor** | Plague flip | Immune; damages infected enemies. |
| **Priest** | Revive / holy | Occasionally resurrects; bonus vs undead. |
| **Witch** | Debuff/hex | Curses a tough enemy. |
| **Fallen Knight** | Elite anchor | Rare armored front-liner. |
| **Lord (Noble)** | Capstone aura | Buffs the whole army. |

*MVP subset:* Farmer, Militia, Archer, Woodcutter (+ Barricade structure).

## Enemies

**Beasts:** Sheep (filler), Ram (charger + knockback), Wolf (backline diver), Boar (tanky),
**Plague Rats** (disease swarm), Crows (aerial), Bear (mini-boss).
**Soldiers:** Bandit, Crossbowman (punishes clumping), Man-at-Arms (armored), Knight (elite),
Cavalry (backline charge), Mercenary Captain (buffs allies).
**Supernatural:** Skeleton, Plague-Risen, Wraith (armor-ignore).
**Bosses:** **The Black Death** (plague avatar), The Baron (armored tyrant), The Great Beast, The Reaper.

*MVP subset:* Sheep, Plague Rat, Bandit, Ram, Knight (+ Black Death boss).

## Items

**Structures:** Barricade, Palisade, Stone Wall, Gate, Spike Barricade, Watchtower,
Oil Cauldron, Tar Pit, Granary, Bell Tower, Hay Bales, Bear Trap.
**Equipment:** Pitchfork, Rusty Sword, Short/Longbow, Shield, Wood Axe, Torch, Plague Mask,
Whetstone, Chainmail Scraps, Boots, Holy Symbol, Lucky Horseshoe.
**Relics (run-wide):** Village Bell, Full Granary, War Drums, Guerrilla Tactics, Martyrdom,
Fortifier, Blacksmith's Forge, Rat Catcher's Charm, Peasant Uprising, Conscription.
**Consumables:** Thrown Rock, Firepot, Holy Water, Rallying Horn, Bag of Grain, Plague Cure, Smoke Bomb.

*MVP subset:* Barricade (structure). The rest layer in after the loop is fun.

---

## MVP build order (what's in this repo now)

1. ✅ One battle: stick-figure auto-combat, targeting, attack, HP, death.
2. ✅ Stances (Aggressive / Hold) toggled globally.
3. ✅ Barricade structure to fight behind.
4. ✅ Gold + shop (hire Farmer/Militia/Archer/Woodcutter, build Barricade).
5. ✅ Loop of escalating battles + a boss every 4th, win/lose/restart.
6. ✅ Landowner "Rally!" power.

**Layer two (next):** tax-rate slider, plot upgrades, more classes/enemies/items,
per-unit stances (Defend/Follow), synergies (auras), then AdMob + Play export.

## Project layout

- `project.godot` — main scene = `Main.tscn`, 1152×648 window.
- `Main.tscn` — root Node2D running `scripts/Main.gd`.
- `scripts/Main.gd` — game state, economy, shop/battle UI, spawning, win/lose loop.
- `scripts/Unit.gd` — one combatant (`class_name Unit`): stats, targeting, movement, `_draw` stick figure.
- `scripts/GameData.gd` — unit/enemy stat tables + wave generator (`class_name GameData`).

## How to run

Open the folder in Godot 4.7 and press **F5** (Play). No art or extra setup needed.
