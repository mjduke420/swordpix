# Hosting godot-rpg in Docker (browser play)

Run the whole game as two containers — a **headless Godot dedicated server** and
**Caddy** serving the **web client** — so players just open a URL in a browser. No
Godot install required for players.

```
Browser (Godot Web export)  ──ws://HOST:PORT/ws──►  Caddy  ──►  Godot server (:8765)
                            ◄── http (web client) ──┘
```

## Quick start

```bash
docker compose up --build
```

First build downloads Godot 4.7 + the web export templates (~1 GB) and exports the
client, so it takes a while; later builds are cached. Then open:

> **http://localhost:8765**

Pick a name + class and hit **Play** — the client auto-connects to
`ws://localhost:8765/ws`. Open a second browser/tab to join as a second player.

`localhost` works because it is a **secure context**. Remote players cannot use a
plain `http://<ip>:port` address — Godot's web export refuses to run outside a
secure context (see **HTTPS** below).

## Choosing the port

The published port defaults to **8765**. Override it with `WEB_PORT`:

```bash
WEB_PORT=9000 docker compose up --build      # -> http://HOST:9000
```

The client derives its WebSocket URL from the page address, so it always targets
the right host + port automatically — nothing else to configure.

## HTTPS (required for remote players)

Godot's web export only runs in a **secure context** — `https://` or `localhost`.
It will not start over a plain `http://<ip>:port` URL (you'll see
*"Secure Context — Check web server configuration (use HTTPS)"*). Exporting
single-threaded removes the COOP/COEP/SharedArrayBuffer requirement, but **not** the
secure-context requirement.

So for anyone other than someone on the host machine, put HTTPS in front of the
published port. The container stays plain HTTP; the proxy/tunnel terminates TLS:

- **Cloudflare Tunnel** (no port-forwarding, trusted cert): point an ingress
  hostname at `http://<host>:8765`. Players open the tunnel's `https://` URL; the
  client auto-connects over `wss://<tunnel-host>/ws`. WebSockets pass through by
  default.
- **Your own reverse proxy** (Caddy/nginx/Traefik with a real domain), or a PaaS
  that terminates TLS — same idea: forward the hostname (path `/`, incl. `/ws`) to
  the container's published port.

In every case the browser sees `https://`, and the client auto-upgrades its socket
to `wss://` to match — no code or rebuild needed.

## How it works

| Piece | Where | Notes |
|-------|-------|-------|
| Dedicated server | `Dockerfile` target `server` | `godot --headless --audio-driver Dummy --path /game -- --server` → `main.gd` calls `Net.start_dedicated_server()`. The server is **not** a player; the first client to join spawns the wave. |
| Web client | `Dockerfile` target `build` → `web` | Exported with the `Web` preset (threads off), served by Caddy from `/srv`. |
| Reverse proxy | `Caddyfile` | Plain HTTP on container `:80`; `/ws` → `server:8765` WebSocket upgrade. |
| Published port | `docker-compose.yml` | `${WEB_PORT:-8765}` → web container `:80`. |

The same authoritative `game_state.gd` / `net.gd` code runs as before — only the
*hosting* changed. Desktop builds can still **Host Game** / **Join Game** natively.

## Troubleshooting

- **"Secure Context — Check web server configuration (use HTTPS)"** — you opened the
  game over a plain `http://<ip>:port` URL. Use `https://` (a tunnel/proxy) or
  `localhost`. See **HTTPS** above.
- **`SSL_ERROR_RX_RECORD_TOO_LONG`** — the opposite: the browser tried `https://`
  against the plain-HTTP port directly. Reach it through your HTTPS tunnel/proxy URL.
- **Can't connect / WebSocket errors** — check `docker compose logs server` for the
  "dedicated server listening on ws port 8765" line and `[server] peer N connected`
  messages; confirm you're hitting the same `WEB_PORT` you published.
- **Server container exits** — if Godot complains about a missing lib, add it to the
  `server` stage in `Dockerfile` (starts with `libfontconfig1`).
- **Port already in use** — pick another with `WEB_PORT=<n>`.
