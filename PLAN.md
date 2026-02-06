# OpenClaw DevBox Node - Implementation Plan

## Overview

Create a container based on the **OpenClaw Docker image** that runs as a **remote node**, with programming languages and dev tools pre-installed. User-installed packages persist across restarts by routing all installations to `/home/node/` (persistent volume).

**Approach:** 方案 B — 以 OpenClaw image 為基底，預裝系統級工具 + 設定讓使用者安裝都落到 persistent volume。

## Architecture

```
┌─────────────────────┐        WebSocket         ┌──────────────────────────┐
│   OpenClaw Gateway  │◄───────────────────────►  │   DevBox Node            │
│   (port 18789)      │                           │                          │
│   AI Agent ─────────┤   node.invoke.request     │   System (in image):     │
│   "run python ..." ─┤   node.invoke.result      │     python3, node, go    │
│                     │                           │     gcc, make, git, jq   │
└─────────────────────┘                           │                          │
                                                  │   User installs (volume):│
                                                  │     ~/.local/  (pip)     │
                                                  │     ~/.npm-global/ (npm) │
                                                  │     ~/go/  (go install)  │
                                                  │     ~/.cargo/ (cargo)    │
                                                  └──────────────────────────┘
```

## Directory Structure

```
openclaw-devbox/
├── Dockerfile                              # Extends OpenClaw image + languages + dev tools
├── zeabur-template-openclaw-devbox.yaml    # Zeabur deployment template
└── deploy.sh                               # Deployment script
```

## Step 1: Create `Dockerfile`

```dockerfile
FROM ghcr.io/openclaw/openclaw:2026.2.2

USER root

# ── System-level packages (baked into image, always available) ──
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Python
    python3 python3-pip python3-venv python3-dev \
    # Build tools
    build-essential gcc g++ make cmake pkg-config \
    # Go
    golang \
    # Rust (system package, rustup can override later)
    rustc cargo \
    # Common dev tools
    git curl wget jq unzip zip \
    # Libraries commonly needed
    libffi-dev libssl-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# ── Configure user-level install paths (all under /home/node/) ──

# pip: install to ~/.local/ by default
ENV PIP_USER=1
ENV PYTHONUSERBASE=/home/node/.local

# npm: global installs to ~/.npm-global/
ENV NPM_CONFIG_PREFIX=/home/node/.npm-global

# Go: GOPATH under home
ENV GOPATH=/home/node/go

# Rust: rustup + cargo under home
ENV RUSTUP_HOME=/home/node/.rustup
ENV CARGO_HOME=/home/node/.cargo

# PATH: include all user-level bin directories
ENV PATH="/home/node/.local/bin:/home/node/.npm-global/bin:/home/node/go/bin:/home/node/.cargo/bin:${PATH}"

# Back to non-root user
USER node
WORKDIR /home/node
```

**Key principle:** System runtimes (python3, go, rustc, gcc) are in the image and always available. User-installed packages (`pip install`, `npm install -g`, `go install`, `cargo install`) go to `$HOME` subdirectories which live on the persistent volume.

## Step 2: Create Zeabur Template YAML

**Separate template** deployed alongside the existing OpenClaw instance.

### Variables:
- `GATEWAY_TOKEN` (STRING) — Gateway authentication token

### Service spec:
- **Image:** `ghcr.io/canyugs/openclaw-devbox:latest`
- **No exposed ports** — outbound WebSocket only
- **Volume:** `/home/node` (persistent, for identity + workspace + user packages)
- **Command:** startup script injected via Zeabur `configs`

### Startup script (injected via configs):
```bash
#!/bin/sh
CONFIG_DIR="$HOME/.openclaw"
CONFIG_FILE="$CONFIG_DIR/openclaw.json"

# Create config with full exec security (no approval needed for server-side container)
if [ ! -f "$CONFIG_FILE" ]; then
  mkdir -p "$CONFIG_DIR"
  cat > "$CONFIG_FILE" << 'CONF'
{
  "tools": {
    "exec": {
      "security": "full"
    }
  }
}
CONF
fi

# Ensure user-level directories exist
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.npm-global"
mkdir -p "$HOME/go/bin"
mkdir -p "$HOME/.cargo/bin"
mkdir -p "$HOME/workspace"

# Start node host — connects to OpenClaw gateway
exec node /app/dist/index.js node run \
  --host "${GATEWAY_HOST:-OpenClaw}" \
  --port "${GATEWAY_PORT:-18789}" \
  --display-name "${NODE_DISPLAY_NAME:-DevBox}"
```

### Environment variables:
| Variable | Default | Notes |
|----------|---------|-------|
| `CLAWDBOT_GATEWAY_TOKEN` | `${GATEWAY_TOKEN}` | Auth token (OpenClaw reads this) |
| `HOME` | `/home/node` | readonly |
| `GATEWAY_HOST` | `OpenClaw` | Zeabur internal DNS name of the gateway |
| `GATEWAY_PORT` | `18789` | readonly |
| `NODE_DISPLAY_NAME` | `DevBox` | Display name shown in node list |

### Resource recommendation:
- CPU: 2 vCPU
- Memory: 2048 MB
- Volume: 10 GB (for user-installed packages)

## Step 3: Create `deploy.sh`

```bash
#!/bin/bash
TEMPLATE_FILE="zeabur-template-openclaw-devbox.yaml"
PROJECT_NAME="${1:-openclaw-devbox-$(date +%Y%m%d%H%M%S)}"
REGION="${2:-hkg1}"
npx zeabur@latest project create -n "$PROJECT_NAME" -r "$REGION"
PROJECT_ID=$(npx zeabur@latest project list | grep "$PROJECT_NAME" | awk '{print $1}')
npx zeabur@latest template deploy -f "$TEMPLATE_FILE" --project-id "$PROJECT_ID"
```

## Step 4: Build & Push Docker Image

```bash
cd openclaw-devbox
docker build -t ghcr.io/canyugs/openclaw-devbox:latest .
docker push ghcr.io/canyugs/openclaw-devbox:latest
```

## Key Design Decisions

1. **`exec.security: "full"`** — Server-side container, no interactive approval needed
2. **System runtimes in image** — python3, go, rustc, gcc always available regardless of volume state
3. **User packages on volume** — pip, npm, go, cargo installs persist across container restarts
4. **No exposed ports** — DevBox initiates outbound WebSocket, no inbound traffic needed

## Verification

1. **Local test:**
   ```bash
   docker build -t openclaw-devbox .
   docker run -e CLAWDBOT_GATEWAY_TOKEN=<token> openclaw-devbox \
     node /app/dist/index.js node run --host host.docker.internal --port 18789
   ```

2. **Check node appears:** `openclaw nodes list` should show "DevBox"

3. **Test language execution:**
   - `python3 -c "print('hello')"`
   - `go version`
   - `rustc --version`
   - `gcc --version`
   - `pip install --user requests && python3 -c "import requests; print(requests.__version__)"`

4. **Test persistence:** Restart the container, verify `pip install`ed packages still exist

5. **Zeabur deployment:** Deploy to same Zeabur project as OpenClaw, verify WebSocket connectivity via internal DNS
