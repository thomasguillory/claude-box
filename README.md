# Claude Box

A Docker-based development environment for running [Claude Code](https://claude.ai) in a persistent, remote container. Connect from anywhere via Tailscale SSH — no SSH keys needed.

## What It Does

Claude Box creates a fully configured Debian container with:

- **Claude Code** pre-installed and ready to use
- **5 MCP servers** for enhanced AI capabilities (documentation lookup, browser automation, code analysis, etc.)
- **Tailscale SSH** for secure, keyless remote access
- **tmux** for session persistence and multi-window workflows
- **zsh** as the default shell with sensible defaults
- **Dev tools**: git, gh CLI, Node.js 22, Python 3, ripgrep, fd, and more
- **Headless Chromium** for browser automation tasks
- **Agent Manager** for running multiple Claude instances in parallel

All data is persisted via Docker volumes, so your workspace, config, and shell history survive container restarts.

## Quick Start

```bash
curl -O https://raw.githubusercontent.com/thomasguillory/claude-box/main/setup-claude-box-v8.1.0.sh
chmod +x setup-claude-box-v8.1.0.sh
./setup-claude-box-v8.1.0.sh
```

After setup, connect with:

```bash
ssh dev@claude-box-<your-instance-name>
```

On first login, run:

```bash
~/first-run.sh
```

## Setup Questions

The setup script and first-run script ask several questions. Here's what each one means and what to provide.

### During `setup-claude-box-v8.1.0.sh`

| Question | What to enter | Why it's asked |
|----------|---------------|----------------|
| **Instance name** (e.g. `work`, `perso`, `client-x`) | A short identifier using letters, numbers, and hyphens. Default: `main`. | Used to name the Docker container and Tailscale hostname (`claude-box-<name>`). Allows running multiple independent instances side by side. |
| **Install Docker automatically?** | `Y` or `N`. | Only asked if Docker is not installed. Installs Docker Desktop (macOS) or Docker Engine (Linux). |
| **Launch Docker?** | `Y` or `N`. | Only asked if Docker is installed but not running. Starts the Docker daemon. |
| **Reconfigure existing instance?** | `y` or `N`. | Only asked if an instance with the same name already exists. Overwrites the previous configuration files. |
| **Tailscale authentication** | Follow the URL shown in the terminal and log in. | Connects the container to your Tailscale network so you can access it via `ssh dev@claude-box-<name>`. |
| **Configure auto-start at boot?** | `Y` or `N`. | Installs a LaunchAgent (macOS) or systemd service (Linux) so the container starts automatically when your machine boots. |

### During `first-run.sh` (inside the container)

| Question | What to enter | Why it's asked |
|----------|---------------|----------------|
| **Your name (for git)** | Your full name, e.g. `Thomas Guillory`. | Configures `git config user.name`. Only asked once. |
| **Your email (for git)** | Your email, e.g. `thomas@example.com`. | Configures `git config user.email`. Only asked once. |
| **Email for SSH key** | Same or different email. | Used as a label when generating an ed25519 SSH key for GitHub access. |
| **Press Enter when done** | Press Enter after adding the displayed public key to GitHub. | The script prints the public key and waits for you to add it at https://github.com/settings/ssh/new. |
| **GitHub CLI login** | Follow the interactive `gh auth login` prompts. | Authenticates the GitHub CLI so you can create PRs, manage issues, etc. |

## Scripts Overview

### `setup-claude-box-v8.1.0.sh` — Main Setup Script

The setup script runs on your **host machine**. It generates all the files needed for the Docker environment and builds/starts the container. Specifically, it creates:

- **Dockerfile** — Debian bookworm-slim image with all dev tools, Node.js 22, gh CLI, Tailscale, Chromium, Claude Code, and pre-cached MCP npm packages.
- **docker-compose.yml** — Container configuration with 12 persistent Docker volumes, resource limits (2 CPU / 8GB RAM), and required capabilities for Tailscale (NET_ADMIN, /dev/net/tun).
- **entrypoint.sh** — Container startup script: fixes permissions, sets up symlinks for persistent data (Claude session, zsh history, SSH keys, git config), starts Tailscale, enables Tailscale SSH, and verifies the MCP environment.
- **first-run.sh** — Interactive first-login setup: configures git, generates SSH keys, authenticates GitHub CLI, installs SuperClaude, configures Claude Code settings, and registers all 5 MCP servers.
- **zshrc / zshrc.local** — Shell configuration with history, completions, useful aliases, and auto-attach to tmux on SSH login.
- **tmux.conf** — tmux configuration with `Ctrl+A` prefix, vim-style pane navigation, and 100k line history.
- **agent.sh** — Agent manager script (see below).
- **start.sh** — Auto-start helper that waits for Docker and runs `docker compose up`.
- **LaunchAgent plist / systemd service** — Auto-start configuration for macOS or Linux.

### `agent.sh` — Agent Manager

A shell utility for running multiple Claude Code instances in parallel, each working on an isolated copy of your code. It works in two modes:

- **Repo mode**: When run inside a git repo, it clones that single repo into a separate directory.
- **Workspace mode**: When run from a workspace directory (a folder containing multiple repos), it clones all repos.

Each agent gets its own tmux window with Claude Code running in `--dangerously-skip-permissions` mode.

**Commands:**

```bash
agent spawn <id> [task]   # Create a new agent (optionally with a task prompt)
agent list                # List all agents and their status
agent kill <id>           # Close an agent's tmux window
agent delete <id>         # Delete an agent's cloned directory
agent delete <id> --force # Delete even if there are unsaved changes
```

**Short aliases:** `s` (spawn), `ls`/`l` (list), `k` (kill), `rm` (delete).

The `delete` command has a safety check: it refuses to remove an agent directory if there are uncommitted changes or unpushed commits, unless you pass `--force`.

## MCP Servers

These MCP (Model Context Protocol) servers are registered during `first-run.sh` and extend Claude Code's capabilities:

| Server | Purpose |
|--------|---------|
| **context7** | Looks up documentation for libraries and frameworks |
| **sequential-thinking** | Enables multi-step reasoning for complex problems |
| **serena** | Semantic code understanding via language servers |
| **playwright** | Browser automation in headless Chromium |
| **chrome-devtools** | Browser debugging via Chrome DevTools Protocol |

All servers run locally inside the container. Check their status with `mcp-list`.

## Useful Aliases

| Alias | Command |
|-------|---------|
| `claude` | `claude --dangerously-skip-permissions` |
| `mcp-list` | `claude mcp list` |
| `chromium-test` | Test headless Chromium |
| `gs` | `git status` |
| `gd` | `git diff` |
| `gl` | `git log --oneline -20` |
| `gp` | `git pull` |

## Docker Volumes

All persistent data is stored in named Docker volumes (prefixed with your instance name):

| Volume | Contents |
|--------|----------|
| `workspace` | Your code / repos |
| `claude-config` | Claude Code configuration |
| `claude-data` | Claude session data (OAuth token) |
| `claude-npm` | Global npm packages |
| `gh-config` | GitHub CLI configuration |
| `ssh-keys` | SSH keys |
| `git-config` | Git configuration |
| `secrets` | Environment variables / API keys |
| `local-bin` | Local binaries (pipx, uv, etc.) |
| `npm-cache` | npm cache |
| `zsh-data` | Zsh history |
| `tailscale-state` | Tailscale connection state |

## Changelog

### v8.1.0 — Migrate to Tailscale SSH

- Replaced traditional SSH key authentication with **Tailscale SSH**. You no longer need to provide an SSH public key during setup — Tailscale handles authentication using your Tailscale identity.
- Removed the `authorized_keys` volume mount from `docker-compose.yml`.
- The entrypoint now runs `tailscale set --ssh` instead of starting sshd.
- Updated connection instructions to reflect keyless SSH via Tailscale.

### v8.0.0-patch2 — MCP Server Scope Fix

- Added `--scope user` flag to all `claude mcp add` commands in `first-run.sh`.
- Without this flag, MCP servers were registered at the project level instead of the user level, meaning they'd only be available in one specific workspace directory.

### v8.0.0-patch1 — Zsh Compatibility Fix

- Fixed glob pattern errors in `agent.sh` when running under zsh.
- Replaced all `[ ... ]` test brackets with `[[ ... ]]` for zsh compatibility.
- Added `setopt NULL_GLOB NO_NOMATCH` to prevent zsh from erroring on empty glob matches.
- Extracted `agent.sh` as a standalone file (previously only embedded in the setup script).

### v8.0.0 — Initial Release

- Full Docker-based Claude Code environment with Debian bookworm-slim.
- Zsh shell with auto-tmux on SSH login.
- 5 local MCP servers: Context7, Sequential-Thinking, Serena, Playwright, Chrome DevTools.
- Agent manager for parallel Claude instances.
- Auto-start support for macOS (LaunchAgent) and Linux (systemd).
- Persistent data via Docker volumes.

## Requirements

- **Docker** (Docker Desktop on macOS, Docker Engine on Linux)
- **Tailscale** account (free) — both on your host and the machine you connect from
- **curl** (for installation)

## Environment Variables

You can set these in your shell before running `docker compose up`, or add them to a `.env` file in the instance directory:

| Variable | Purpose |
|----------|---------|
| `ANTHROPIC_API_KEY` | Anthropic API key (optional — Claude Code can also use OAuth) |
| `TAILSCALE_AUTHKEY` | Pre-auth key for non-interactive Tailscale setup |
| `TZ` | Timezone (default: `UTC`) |
