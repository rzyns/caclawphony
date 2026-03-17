# ─── Stage 1: Builder ────────────────────────────────────────────────────────
# Build the symphony escript on an Erlang/Elixir base.
FROM hexpm/elixir:1.19.5-erlang-28.2-debian-bookworm-20260316-slim AS builder

WORKDIR /app

# Install build deps (git for mix deps.get with git sources)
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends git && \
    rm -rf /var/lib/apt/lists/*

ENV MIX_ENV=prod

# Build context is repo root; Elixir project lives in elixir/
# Fetch deps first (cache layer)
COPY elixir/mix.exs elixir/mix.lock ./
RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get --only prod

# Copy source and build escript
COPY elixir/config/ config/
COPY elixir/lib/ lib/
COPY elixir/priv/ priv/

RUN mix escript.build


# ─── Stage 2: Runtime ────────────────────────────────────────────────────────
# Use the same OTP 28 image as the builder so the escript runtime version matches.
# (Debian apt erlang-base is OTP 25/26, which produces "corrupt atom table" errors.)
FROM hexpm/elixir:1.19.5-erlang-28.2-debian-bookworm-20260316-slim AS runtime

WORKDIR /home/app

# Additional system deps: git, curl, bash, ssh, jq (erlang already present)
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        git \
        curl \
        ca-certificates \
        bash \
        openssh-client \
        jq && \
    rm -rf /var/lib/apt/lists/*

# Node.js LTS (via NodeSource)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list && \
    apt-get update -qq && \
    apt-get install -y --no-install-recommends gh && \
    rm -rf /var/lib/apt/lists/*

# Claude Code CLI + claude-app-server
RUN npm install -g @anthropic-ai/claude-code claude-app-server && \
    # Smoke-test binaries exist
    claude --version && \
    claude-app-server --version

# Non-root user
RUN useradd -m -u 1000 -s /bin/bash app && \
    mkdir -p /home/app/workspaces

# Copy escript and WORKFLOW before chown
COPY --from=builder /app/bin/symphony /home/app/symphony
COPY WORKFLOW.plane.md /home/app/WORKFLOW.plane.md

RUN chmod +x /home/app/symphony && \
    chown -R app:app /home/app

USER app

# Git identity for szponeczek (non-secret; signing key is mounted at runtime)
RUN git config --global user.name "Claw Kowalski" && \
    git config --global user.email "szponeczek@forserial.org" && \
    git config --global commit.gpgsign true && \
    git config --global gpg.format ssh && \
    git config --global user.signingkey "/home/app/.ssh/szponeczek_signing"

WORKDIR /home/app

ENTRYPOINT ["/home/app/symphony", "WORKFLOW.plane.md", "--i-understand-that-this-will-be-running-without-the-usual-guardrails"]
