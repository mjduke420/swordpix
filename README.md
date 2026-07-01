# ⚔️ Sword & Pixel — Godot Port (`godot-rpg`)

A native **Godot 4.6** recreation of the multiplayer turn-based D&D dungeon
crawler originally built as an Electron client + Python WebSocket server
(`../rpg`). Top-down d20 combat, proximity-triggered fights, 5 classes, and
character leveling — all in GDScript with native ENet multiplayer (no Python).

## Status — Phases 1 & 2 complete

### Phase 1 — Vertical slice (core loop)

The core loop is implemented and verified end-to-end:

- **Native ENet multiplayer** — host is an authoritative listen-server (peer 1);
  others join by IP on port `8765`. Clients send action RPCs; the server mutates
  state and broadcasts a full snapshot to all peers (mirrors the original's
  `broadcast` / `get_state_dict` model).
- **5 classes** — Warrior, Mage, Rogue, Cleric, Ranger (stats, damage dice,
  signature abilities).
- **Top-down 15×15 grid** with the original sprite art.
- **Movement** — WASD; 5 moves/turn in combat, free roam in exploration.
- **Proximity combat** — stepping within 1.5 tiles of a monster starts a fight.
- **d20 combat** — stepping into a monster opens an **initiative phase**: every
  player clicks **🎲 Roll Init** to roll their own d20 + DEX (an animated die
  tumbles on screen and lands on the result) while monsters auto-roll; once all
  players have rolled, the order is locked and turns begin. Hit roll vs AC,
  nat-20 crit / nat-1 fumble, per-class damage dice.
- **Class abilities** — Whirlwind, Frost Nova, Shadow Step, Holy Resonance, Volley.
- **Monster AI** — chase + attack, Goblin Pocket Sand (blind), Orc Roar (frighten).
- **Leveling** — XP per kill, +20 HP / +10 MP / +5 ATK per level (cap 10).
- **Potions** — health & mana.
- **HUD** — HP/MP/XP bars, level, action buttons (grouped into Combat / Explore /
  Party clusters, each tinted to its function with a matching shader sheen —
  Attack slashes, Heal pulses, Hide flickers, and so on), turn banner, combat log.

### Phase 2 — World progression

- **6 campaign biomes** — Dreadwood Forest, Charred Wastes, Whispering Caves,
  Abyssal Depths, Crimson Citadel, Frozen Hollow — each with its own palette and
  scenery tile (trees / stalagmites / rocks).
- **15-region / 3-act campaign** with per-chapter story beats and act-transition
  narration; biome is chosen by act + region.
- **Region advance** — clear the area, then everyone presses **🏁 Next Region**
  (`ready`); when all players confirm, the world regenerates for the next region.
- **Region recap** — the moment a wave is cleared, a per-player kills / damage
  dealt / damage taken table pops up automatically, so the party sees how the
  fight went before pressing on.
- **3 bosses** — Goblin King (region 5), Lich of the Abyss (10), Void Herald (15),
  scaled and rendered larger with a tinted boss sprite. Each is a multi-phase
  fight: crossing **75% / 50% / 25% HP** triggers an escalating wave of **themed
  adds** (Goblin King → goblin skirmishers, Lich → skeleton archers, Void Herald →
  void casters) that join the initiative order, plus a one-time enrage (+50%
  damage) at half HP. Live adds are capped so the fight stays winnable.
- **New Game+** — clearing region 15 loops back to region 1 with `ng_plus`
  scaling (+25% monster strength per cycle).

### Phase 3 — Line of sight + loot & gear

- **Fog of war** — per-player vision computed from the local player via Bresenham
  raycast (4-tile radius). Tiles are bright (visible), dim (explored), or hidden
  (never seen). Walls, trees, rocks, and stalagmites block sight; **monsters hide
  in the fog** and only appear when in your sightline.
- **Loot drops** — slain monsters drop loot (80%) with weighted rarity
  (Common→Legendary) and region-scaled atk/def bonuses; high-end gear has stat
  requirements.
- **Ground pickups** — walk over potions, gold, and gear to collect them.
- **Chests** — spawn each region; **📦 Loot** opens an adjacent one.
- **Equipment** — equip/unequip weapons & armor (weapon adds to hit, armor to AC),
  with requirement checks, via the **🎒 Inventory** overlay.
- **Merchant** — a wandering merchant per region; stand next to it and open
  **🛒 Shop** to buy potions and region-scaled gear.

### Phase 4 — Torches, portals & HellPlane

- **Torch light sources** — 1–3 per region, with flickering `CPUParticles2D` fire
  and an additive glow; a torch you can see extends the fog-of-war around it.
- **12 biomes total** — the 6 campaign biomes plus 5 alt-dimension biomes
  (Sky-Reaches, Sunken Oasis, Clockwork Spire, Fey-Wilds, Sunless Sea) reached via
  **Mystic Portals** (a rare loot drop — step on it to warp the whole party), and
  **HellPlane** (a 10% chance when opening a chest pulls the party in; find the
  return portal to escape — the prior world is snapshotted and restored). Each
  biome gets its own ground colour wash.

## Running

Open the project in Godot 4.6+ and press Play, or run from the editor.

1. Enter a name, pick a class.
2. **Host Game** — you become the server and a player.
3. On another machine/instance: enter the host's IP and **Join Game**.
4. Everyone lands in the **Lobby** — a roster of who's connected plus a Start
   button. Hit **Start Solo** to begin alone, or wait for friends and hit
   **Start Adventure** once the group's ready; either way it's the same action.
5. **Joining mid-fight is supported** — if someone connects while combat is
   already underway, they're pulled into the running round: a Roll Init button
   appears, and rolling slots them into the current initiative order without
   disturbing whoever's turn it already is.

### Play in a browser (Docker)

You can also host the game in Docker and let players join from a **web browser**
with no Godot install — a headless dedicated server plus a Caddy-served web export:

```bash
docker compose up --build               # then open http://localhost:8765
WEB_PORT=9000 docker compose up --build  # or pick any port -> http://localhost:9000
```

The transport is WebSocket, so the same authoritative server code runs unchanged;
the browser client auto-connects to `ws(s)://<host>/ws`. The container serves plain
HTTP on a configurable port (`WEB_PORT`, default 8765), but **Godot web requires a
secure context** — so remote players need HTTPS in front (a Cloudflare Tunnel or your
own TLS proxy); `localhost` works directly for local testing. See **[DOCKER.md](DOCKER.md)**.

## Architecture

```
scripts/
  dice.gd         # autoload — roll_dice / d20 / saving throws  (<- roll_dice in game_state.py)
  classes.gd      # autoload — 5 class definitions              (<- classes.py)
  game_state.gd   # authoritative game logic, server-only       (<- game_state.py)
  net.gd          # autoload — ENet host/join, action routing,
                  #   initiative-cycle driver                   (<- server.py)
  main.gd         # menu (name / class / host / join)
  game.gd         # grid renderer + HUD + input                 (<- client/game.js)
scenes/
  main.tscn, game.tscn
  test.tscn/test.gd  # headless GameState logic test (16 checks)
assets/           # sprite PNGs copied from ../rpg/client/assets
```

**Data flow:** client action -> `net.gd` (server) -> `game_state.gd` method ->
mutated state -> `apply_state.rpc` snapshot to all clients -> `game.gd` rebuilds
the board.

## Verification

`scenes/test.tscn` runs 141 headless assertions over the ported `GameState`
(map gen, players/stats, monster waves, proximity combat, initiative, leveling,
attack, ability, serialization, biome/region progression, bosses, NG+, chapter
story, mixed-type id safety, line-of-sight, loot/equipment/chests/merchant,
torch spawning + fire-particle API, portals + HellPlane snapshot/restore) — all
passing. Run it from the editor or via the Godot MCP with
`scene = res://scenes/test.tscn`.

**Audio** — `scripts/audio.gd` (autoload `Audio`) synthesizes all SFX in-memory
as 16-bit PCM (`AudioStreamWAV`), so there are no sound asset files: per-class
attack/ability sounds keyed to the combat VFX type (slash, fireball, frost, …)
plus a turn chime when it becomes the local player's turn.

**Music** — `scripts/music.gd` (autoload `Music`) plays looping background music
that crossfades between game states (menu / explore / combat / boss). Tracks are
**drop-in and swappable with zero code changes**: put an audio file in
`assets/music/` named after the state (`explore.ogg`, `combat.ogg`, `boss.ogg`,
`menu.ogg` — `.ogg`/`.mp3`/`.wav` all work) and it plays automatically; a missing
file just means that state is silent. Re-map or add states by editing the
`TRACKS` dict in `music.gd`. See [assets/music/README.md](assets/music/README.md).

**Audio settings** — separate **Music** and **SFX** audio buses
(`default_bus_layout.tres`) let the two be balanced independently. `scripts/settings.gd`
(autoload `Settings`) owns the volume/mute preferences, applies them to the buses, and
persists them to `user://settings.cfg` (these are user prefs, so unlike the game they
survive across runs). A shared `Settings.build_panel()` widget — Music slider, SFX
slider, Mute toggle — appears both on the **main menu** and behind the in-game
**⚙ Settings** button.

### Guilds & the interactive map layer

- **Guilds** (🛡️ Guild overlay) — found a guild, invite unguilded players (leader
  only), and leave. Guildmates **share XP** and gain **+5% damage per member**.
  Membership shows as a tag in the party roster.
- **Interactive tiles** — maps now scatter **altars**, **locked hatches**, and
  **pitfalls**, plus each biome's **hazard tile** (ice slides you, lava burns, sky
  edges, …). **🔨 Bash** (STR) / **🗝️ Pick** (DEX) force an adjacent hatch open to
  reveal loot or an ambush; **🙏 Pray** spends an adjacent altar for a full heal or
  a permanent +2 stat.
- **Traps** — hidden spike traps spring a DEX save when stepped on; Rangers
  passively spot nearby traps (only revealed traps are sent to clients).

## Deferred to later phases

**Save persistence is intentionally omitted** — every run starts fresh from the
beginning by design.

Done since: Rogue **Hide** (🥷, sets `is_hidden`; bonus action in combat, free in
exploration) and **Examine** (🔍, reports a nearby creature's HP/AC/ATK) are now
implemented and tested.
