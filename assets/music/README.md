# Background music — drop your tracks here

Swapping the game's music is meant to be **as easy as replacing a file**. The
`Music` autoload (`scripts/music.gd`) looks in this folder for a track named
after each game state and plays it on loop, crossfading when the state changes.

## How to add / swap a track

Drop an audio file into this folder named after the state you want to score:

| State     | Filename (any one extension) | Plays during |
|-----------|------------------------------|--------------|
| `menu`    | `menu.ogg`                   | Main menu |
| `explore` | `explore.ogg`                | Exploration (between fights) |
| `combat`  | `combat.ogg`                 | Combat (initiative + player turns) |
| `boss`    | `boss.ogg`                   | Any fight with a boss on the field |
| `victory` | `victory.ogg`                | (reserved — call `Music.play_state("victory")`) |

- **Preferred format:** `.ogg` (Vorbis). `.mp3` and `.wav` also work; if more
  than one exists for a state the first match wins in this order: `.ogg`, `.mp3`,
  `.wav`.
- To **swap** a track, just overwrite the file (e.g. replace `combat.ogg`). In
  the editor Godot re-imports it automatically; no code changes.
- A **missing** file means that state is simply silent — the game runs fine with
  no music files at all (this folder can stay empty).

## Re-mapping or adding states

Open `scripts/music.gd` and edit the `TRACKS` dictionary (state → base filename).
Add a new entry there and trigger it anywhere with `Music.play_state("my_state")`.

## Volume

`Music.volume_db` (default `-6.0`) sets the loop loudness; `Music.set_muted(true)`
mutes. If you add a dedicated **"Music"** audio bus to the project, the players
route to it automatically (otherwise they use Master).

> This file is just documentation — it does not affect the build.
