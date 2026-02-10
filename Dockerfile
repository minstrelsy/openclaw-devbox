FROM ghcr.io/openclaw/openclaw:2026.2.9

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
