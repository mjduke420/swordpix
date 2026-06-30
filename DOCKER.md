# Hosting godot-rpg in Docker (browser play)

Run the whole game as two containers — a **headless Godot dedicated server** and
**Caddy** serving the **web client** — so players just open a URL in a browser. No
Godot install required for players.

```
Browser (Godot Web export)  ──wss://HOST/ws──►  Caddy  ──ws──►  Godot server (:8765)
                            ◄── https (web client + COOP/COEP headers) ──┘
```

## Quick start (local)

```bash
docker compose up --build
```

First build downloads Godot 4.7 + the web export templates (~1 GB) and exports the
client, so it takes a while; later builds are cached. Then open:

> **https://localhost**

Caddy serves `localhost` over HTTPS via its built-in CA (your browser may warn the
first time — accept it). HTTPS matters: Godot's web export uses threads, which need
a secure context (`https` or `localhost`) plus the COOP/COEP headers Caddy sets.

Pick a name + class and hit **Play** — the client auto-connects to `wss://localhost/ws`.
Open a second browser/tab to join as a second player.

## Public deployment

Point a domain's DNS at the host, open ports 80/443, then:

```bash
SITE_ADDRESS=rpg.example.com docker compose up --build -d
```

Caddy obtains a Let's Encrypt certificate automatically and serves
`https://rpg.example.com`; the client connects over `wss://rpg.example.com/ws`.

## How it works

| Piece | Where | Notes |
|-------|-------|-------|
| Dedicated server | `Dockerfile` target `server` | `godot --headless --audio-driver Dummy --path /game -- --server` → `main.gd` calls `Net.start_dedicated_server()`. The server is **not** a player; the first client to join spawns the wave. |
| Web client | `Dockerfile` target `build` → `web` | Exported with the `Web` preset (threads on), served by Caddy from `/srv`. |
| Reverse proxy / TLS | `Caddyfile` | Auto-HTTPS, COOP/COEP headers, `/ws` → `server:8765` WebSocket upgrade. |

The same authoritative `game_state.gd` / `net.gd` code runs as before — only the
*hosting* changed. Desktop builds can still **Host Game** / **Join Game** natively.

## Configuration

- `SITE_ADDRESS` (compose env) — domain for Caddy + automatic HTTPS. Defaults to
  `localhost`.
- Game port `8765` is internal only (reached via Caddy's `/ws`); change it in
  `scripts/net.gd` (`PORT`) and `Caddyfile` together if needed.

## Troubleshooting

- **"SharedArrayBuffer is not defined" / blank canvas** — you opened the client over
  plain `http://<ip>`. Use the HTTPS URL (or `localhost`); threads need a secure
  context. (Alternatively re-export the `Web` preset with Thread Support off.)
- **Can't connect / WebSocket errors** — check `docker compose logs server` for the
  "dedicated server listening on ws port 8765" line and the `[server] peer N
  connected` messages; confirm the page is same-origin with `/ws`.
- **Server container exits** — if Godot complains about missing libs, add them to the
  `server` stage in `Dockerfile` (start with `libfontconfig1`, already included).
