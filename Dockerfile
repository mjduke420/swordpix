# syntax=docker/dockerfile:1
# Self-contained build: downloads Godot 4.7 + web export templates, exports the
# browser client, and ships a headless dedicated server. See DOCKER.md.

# ---- Base: Godot 4.7 headless binary + Web export templates ------------------
FROM debian:bookworm-slim AS godot
ARG GODOT_VERSION=4.7-stable
ARG GODOT_DOTVER=4.7.stable
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/*
# The standard Linux build also runs as a headless server via --headless.
RUN curl -fL -o /tmp/godot.zip \
      "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip" \
    && unzip /tmp/godot.zip -d /tmp \
    && mv /tmp/Godot_v${GODOT_VERSION}_linux.x86_64 /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm /tmp/godot.zip
# Export templates (needed only to build the Web client).
RUN curl -fL -o /tmp/templates.tpz \
      "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_export_templates.tpz" \
    && mkdir -p "/root/.local/share/godot/export_templates/${GODOT_DOTVER}" \
    && unzip /tmp/templates.tpz -d /tmp \
    && mv /tmp/templates/* "/root/.local/share/godot/export_templates/${GODOT_DOTVER}/" \
    && rm -rf /tmp/templates /tmp/templates.tpz

# ---- Build the Web export ----------------------------------------------------
FROM godot AS build
WORKDIR /game
COPY . /game
# Fully import resources (a headless EDITOR pass actually builds the .ctex texture
# imports — a plain `--import` only scans, leaving blank textures), then export.
RUN godot --headless --editor --quit-after 400 2>&1 | tail -n 20 || true
RUN mkdir -p /out/web \
    && godot --headless --export-release "Web" /out/web/index.html \
    && test -f /out/web/index.html

# ---- Dedicated game server ---------------------------------------------------
FROM debian:bookworm-slim AS server
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates libfontconfig1 \
    && rm -rf /var/lib/apt/lists/*
COPY --from=godot /usr/local/bin/godot /usr/local/bin/godot
WORKDIR /game
COPY . /game
RUN godot --headless --import 2>&1 | tail -n 20 || true
EXPOSE 8765
# `-- --server` passes --server as a user arg; main.gd starts the dedicated server.
CMD ["godot", "--headless", "--audio-driver", "Dummy", "--path", "/game", "--", "--server"]

# ---- Web server (Caddy serves the export, proxies /ws, terminates TLS) -------
FROM caddy:2 AS web
COPY --from=build /out/web /srv
COPY Caddyfile /etc/caddy/Caddyfile
