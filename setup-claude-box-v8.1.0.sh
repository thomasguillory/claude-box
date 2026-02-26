#!/bin/bash

echo "🚀 Setup Claude Box v8.1.0 - Tailscale SSH + Local MCP Servers"
echo "=============================================================="
echo ""
echo "📦 MCP Servers inclus:"
echo "   - Context7 (documentation lookup)"
echo "   - Sequential-Thinking (multi-step reasoning)"
echo "   - Serena (semantic code understanding)"
echo "   - Playwright (browser automation - headless)"
echo "   - Chrome DevTools (browser debugging - headless)"
echo ""

# =============================================================================
# NOM DE L'INSTANCE
# =============================================================================
read -p "Nom de l'instance (ex: work, perso, client-x) [main]: " INSTANCE_NAME
INSTANCE_NAME="${INSTANCE_NAME:-main}"

if [[ ! "$INSTANCE_NAME" =~ ^[a-zA-Z0-9-]+$ ]]; then
    echo "❌ Nom invalide. Utilise uniquement lettres, chiffres et tirets."
    exit 1
fi

echo ""
echo "📦 Instance: ${INSTANCE_NAME}"
echo "   Container: claude-box-${INSTANCE_NAME}"
echo "   Hostname Tailscale: claude-box-${INSTANCE_NAME}"
echo "   MCP Servers: local (5 serveurs)"
echo ""

# =============================================================================
# HOST DEPENDENCIES CHECK
# =============================================================================

# Check for curl (needed for various installations)
if ! command -v curl &> /dev/null; then
    echo "❌ curl n'est pas installé."
    case "$(uname -s)" in
        Darwin) echo "   Installe avec: brew install curl" ;;
        Linux)  echo "   Installe avec: sudo apt install curl  (ou yum/dnf)" ;;
    esac
    exit 1
fi

echo "🔐 Connexion via Tailscale SSH (pas besoin de clés SSH !)"

# =============================================================================
# DOCKER CHECK & INSTALL
# =============================================================================
install_docker_macos() {
    echo "🍎 Installation de Docker Desktop pour macOS..."
    if command -v brew &> /dev/null; then
        brew install --cask docker
        echo ""
        echo "✅ Docker Desktop installé."
        echo "⚠️  Lance Docker Desktop depuis Applications, puis relance ce script."
        exit 0
    else
        echo "❌ Homebrew n'est pas installé."
        echo "   Installe Homebrew: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        echo "   Ou installe Docker Desktop manuellement: https://www.docker.com/products/docker-desktop"
        exit 1
    fi
}

install_docker_linux() {
    echo "🐧 Installation de Docker pour Linux..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker "$USER"
    echo ""
    echo "✅ Docker installé."
    echo "⚠️  Déconnecte-toi et reconnecte-toi pour appliquer les permissions, puis relance ce script."
    exit 0
}

# Check if docker command exists
if ! command -v docker &> /dev/null; then
    echo "❌ Docker n'est pas installé."
    echo ""
    read -p "Veux-tu l'installer automatiquement ? [Y/n]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        case "$(uname -s)" in
            Darwin) install_docker_macos ;;
            Linux)  install_docker_linux ;;
            *)      echo "❌ OS non supporté pour l'installation automatique."; exit 1 ;;
        esac
    else
        echo "Installe Docker manuellement puis relance ce script."
        exit 1
    fi
fi

# Docker is installed, check if it's running
if ! docker info > /dev/null 2>&1; then
    echo "⚠️  Docker est installé mais n'est pas lancé."
    case "$(uname -s)" in
        Darwin)
            echo "   Lance Docker Desktop depuis Applications."
            echo ""
            read -p "Veux-tu que j'essaie de le lancer ? [Y/n]: " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                open -a Docker
                echo "⏳ Attente du démarrage de Docker (max 60s)..."
                for i in {1..12}; do
                    sleep 5
                    if docker info > /dev/null 2>&1; then
                        echo "✅ Docker est prêt!"
                        break
                    fi
                    echo "   ...toujours en attente ($((i*5))s)"
                done
                if ! docker info > /dev/null 2>&1; then
                    echo "❌ Docker n'a pas démarré. Lance-le manuellement et relance ce script."
                    exit 1
                fi
            else
                exit 1
            fi
            ;;
        Linux)
            echo "   Lance: sudo systemctl start docker"
            read -p "Veux-tu que j'essaie de le lancer ? [Y/n]: " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                sudo systemctl start docker
                sleep 2
                if docker info > /dev/null 2>&1; then
                    echo "✅ Docker est prêt!"
                else
                    echo "❌ Échec du démarrage. Vérifie avec: sudo systemctl status docker"
                    exit 1
                fi
            else
                exit 1
            fi
            ;;
        *)
            echo "❌ Lance Docker manuellement puis relance ce script."
            exit 1
            ;;
    esac
fi

echo "✅ Docker est prêt"

CLAUDE_DIR="$HOME/.claude-box-${INSTANCE_NAME}"

if [ -d "$CLAUDE_DIR" ]; then
    echo "⚠️  L'instance '${INSTANCE_NAME}' existe déjà dans ${CLAUDE_DIR}"
    read -p "Veux-tu la reconfigurer ? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Annulé."
        exit 0
    fi
fi

mkdir -p "$CLAUDE_DIR"
cd "$CLAUDE_DIR"

echo "📦 Création des fichiers Docker..."

# =============================================================================
# DOCKERFILE
# =============================================================================
cat > Dockerfile << 'DOCKERFILE_START'
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    # Core tools
    openssh-server mosh tmux git curl wget jq htop vim nano \
    ca-certificates gnupg sudo locales \
    # Zsh shell
    zsh \
    # Python
    python3 python3-pip python3-venv pipx \
    # Build tools (required for npm native modules)
    build-essential gcc g++ make \
    # Modern search and file tools
    ripgrep fd-find tree \
    # Archive tools
    unzip zip \
    # Chromium browser (works on both amd64 and arm64)
    chromium \
    chromium-driver \
    # Browser dependencies for Playwright/Chrome DevTools
    libnss3 \
    libnspr4 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libdbus-1-3 \
    libxkbcommon0 \
    libatspi2.0-0 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libasound2 \
    libpango-1.0-0 \
    libcairo2 \
    # Fonts for proper rendering
    fonts-liberation \
    fonts-noto-color-emoji \
    && rm -rf /var/lib/apt/lists/* \
    # Create fd symlink (Debian names it fdfind)
    && ln -s /usr/bin/fdfind /usr/bin/fd

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y gh && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null \
    && curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list \
    && apt-get update && apt-get install -y tailscale && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/zsh -u 1000 dev \
    && echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/dev

RUN mkdir -p /home/dev/.npm-global \
    && chown -R dev:dev /home/dev/.npm-global

ENV NPM_CONFIG_PREFIX=/home/dev/.npm-global
ENV PATH=/home/dev/.npm-global/bin:/home/dev/.local/bin:$PATH

# Headless browser configuration
ENV CHROME_PATH=/usr/bin/chromium
ENV PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
ENV DISPLAY=

# Install uv (for uvx) as dev user
USER dev
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
USER root

# Ensure uv is in PATH
ENV PATH="/home/dev/.local/bin:$PATH"

USER dev
RUN curl -fsSL https://claude.ai/install.sh | bash

# Pre-cache MCP npm packages (speeds up first-run)
RUN npx -y @upstash/context7-mcp --help 2>/dev/null || true
RUN npx -y @modelcontextprotocol/server-sequential-thinking --help 2>/dev/null || true
RUN npx -y @playwright/mcp@latest --help 2>/dev/null || true
RUN npx -y chrome-devtools-mcp@latest --help 2>/dev/null || true
USER root

RUN mkdir /var/run/sshd \
    && sed -i 's/#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config \
    && sed -i 's/#PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config \
    && echo "AllowUsers dev" >> /etc/ssh/sshd_config

RUN mkdir -p /home/dev/.ssh \
    && mkdir -p /home/dev/.claude \
    && mkdir -p /home/dev/.config/gh \
    && mkdir -p /home/dev/workspace \
    && mkdir -p /home/dev/.secrets \
    && mkdir -p /home/dev/.local/bin \
    && mkdir -p /home/dev/.local/pipx \
    && mkdir -p /home/dev/.npm \
    && mkdir -p /home/dev/.cache \
    && mkdir -p /home/dev/.claude-data \
    && mkdir -p /home/dev/.zsh-data \
    && chown -R dev:dev /home/dev

COPY tmux.conf /home/dev/.tmux.conf
RUN chown dev:dev /home/dev/.tmux.conf

COPY agent.sh /home/dev/.local/bin/agent
RUN chmod +x /home/dev/.local/bin/agent && chown dev:dev /home/dev/.local/bin/agent

COPY zshrc.local /home/dev/.zshrc.local
RUN chown dev:dev /home/dev/.zshrc.local

COPY zshrc /home/dev/.zshrc
RUN chown dev:dev /home/dev/.zshrc

COPY first-run.sh /home/dev/first-run.sh
RUN chmod +x /home/dev/first-run.sh && chown dev:dev /home/dev/first-run.sh

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22
EXPOSE 60000-60010/udp

ENTRYPOINT ["/entrypoint.sh"]
DOCKERFILE_START

# =============================================================================
# ZSHRC CONFIG
# =============================================================================
cat > zshrc << 'ZSHRC_END'
# Claude Box Zsh Configuration

# History configuration (persisted via symlink to ~/.zsh-data/)
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS
setopt INC_APPEND_HISTORY

# Zsh options
setopt AUTO_CD
setopt AUTO_PUSHD
setopt PUSHD_IGNORE_DUPS
setopt CORRECT
setopt COMPLETE_IN_WORD
setopt IGNORE_EOF
setopt NO_BEEP

# Completion system
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# Key bindings (emacs style)
bindkey -e
bindkey '^[[A' history-search-backward
bindkey '^[[B' history-search-forward
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
bindkey '^[[3~' delete-char

# Load local config
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
ZSHRC_END

# =============================================================================
# ZSHRC LOCAL (instance-specific)
# =============================================================================
cat > zshrc.local << ZSHRC_LOCAL_END
# Claude Box instance config

# Environment
export NPM_CONFIG_PREFIX=/home/dev/.npm-global
export PATH=/home/dev/.npm-global/bin:/home/dev/.local/bin:\$PATH

# Headless browser configuration (for Playwright & Chrome DevTools MCP)
export CHROME_PATH=/usr/bin/chromium
export PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium
export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
export DISPLAY=

# Timezone (override with TZ env var in docker-compose)
export TZ=\${TZ:-UTC}

# Load secrets if present
[[ -f ~/.secrets/env ]] && source ~/.secrets/env

# Load agent manager
source ~/.local/bin/agent

# Prompt
PROMPT='%F{green}dev@claude-box-${INSTANCE_NAME}%f:%F{blue}%~%f\$ '

# Aliases
alias ll="ls -la"
alias la="ls -A"
alias l="ls -CF"
alias claude="claude --dangerously-skip-permissions"
alias mcp-list="claude mcp list"
alias chromium-test="chromium --headless --no-sandbox --disable-gpu --dump-dom https://example.com 2>/dev/null | head -20"

# Modern tool aliases (if available)
alias grep="grep --color=auto"
command -v rg &>/dev/null && alias rg="rg --smart-case"
command -v fd &>/dev/null && alias find="fd"

# Git aliases
alias gs="git status"
alias gd="git diff"
alias gl="git log --oneline -20"
alias gp="git pull"

# Auto-attach tmux on SSH login
if [[ -n "\$SSH_CONNECTION" ]] && [[ -z "\$TMUX" ]] && [[ -o interactive ]]; then
    exec tmux new-session -A -s main -c ~/workspace
fi
ZSHRC_LOCAL_END

# =============================================================================
# AGENT MANAGER SCRIPT v3
# =============================================================================
cat > agent.sh << 'AGENTSCRIPT'
#!/usr/bin/env bash
# Agent manager for parallel Claude instances v4
# Compatible with both bash and zsh

# Zsh compatibility: prevent glob errors when no matches
if [[ -n "${ZSH_VERSION:-}" ]]; then
    setopt NULL_GLOB 2>/dev/null
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

detect_context() {
    if git rev-parse --show-toplevel > /dev/null 2>&1; then
        AGENT_MODE="repo"
        REPO_ROOT=$(git rev-parse --show-toplevel)
        REPO_NAME=$(basename "$REPO_ROOT")
        WORKSPACE_DIR=$(dirname "$REPO_ROOT")

        REPO_URL=$(git remote get-url origin 2>/dev/null) || {
            echo -e "${RED}Erreur: Pas de remote 'origin' configuré${NC}"
            return 1
        }

        [[ "$REPO_NAME" == *"--agent"* ]] && {
            REPO_NAME="${REPO_NAME%%--agent*}"
            REPO_ROOT="${WORKSPACE_DIR}/${REPO_NAME}"
        }

        local workspace_name=$(basename "$WORKSPACE_DIR")
        [[ "$workspace_name" == *"--agent"* ]] && {
            AGENT_MODE="workspace"
            WORKSPACE_DIR=$(dirname "$WORKSPACE_DIR")
            WORKSPACE_NAME="${workspace_name%%--agent*}"
        }
    else
        local current_dir=$(pwd)
        local dir_name=$(basename "$current_dir")
        local has_repos=0

        for subdir in "$current_dir"/*/; do
            [[ -d "${subdir}.git" ]] && { has_repos=1; break; }
        done

        if [[ "$has_repos" -eq 1 ]]; then
            AGENT_MODE="workspace"
            WORKSPACE_DIR=$(dirname "$current_dir")
            WORKSPACE_NAME="$dir_name"
            [[ "$WORKSPACE_NAME" == *"--agent"* ]] && WORKSPACE_NAME="${WORKSPACE_NAME%%--agent*}"
        else
            echo -e "${RED}Erreur: Pas dans un repo git ni dans un workspace${NC}"
            return 1
        fi
    fi
    return 0
}

agent_spawn() {
    local agent_id="$1"
    local task="$2"

    [[ -z "$agent_id" ]] && {
        echo -e "${YELLOW}Usage: agent spawn <id> [task]${NC}"
        echo "  Depuis un repo: clone ce repo"
        echo "  Depuis ~/workspace: clone tous les repos"
        return 1
    }
    
    detect_context || return 1

    [[ "$AGENT_MODE" == "repo" ]] && _spawn_repo_agent "$agent_id" "$task" || _spawn_workspace_agent "$agent_id" "$task"
}

_spawn_repo_agent() {
    local agent_id="$1" task="$2"
    local agent_dir="${WORKSPACE_DIR}/${REPO_NAME}--agent${agent_id}"
    local window_name="${REPO_NAME}:agent${agent_id}"

    [[ -n "$TMUX" ]] && tmux list-windows -F '#W' 2>/dev/null | grep -q "^${window_name}$" && {
        echo -e "${YELLOW}Agent ${agent_id} existe, switching...${NC}"
        tmux select-window -t "$window_name" 2>/dev/null || true
        return 0
    }

    [[ ! -d "$agent_dir" ]] && {
        echo -e "${BLUE}🤖 Création agent ${agent_id} (repo: ${REPO_NAME})...${NC}"
        git clone "$REPO_URL" "$agent_dir"
        echo -e "${GREEN}✅ Clone créé${NC}"
    }

    _open_agent_tmux "$window_name" "$agent_dir" "$task"
}

_spawn_workspace_agent() {
    local agent_id="$1" task="$2"
    local source_workspace="${WORKSPACE_DIR}/${WORKSPACE_NAME}"
    local agent_dir="${WORKSPACE_DIR}/${WORKSPACE_NAME}--agent${agent_id}"
    local window_name="${WORKSPACE_NAME}:agent${agent_id}"

    [[ -n "$TMUX" ]] && tmux list-windows -F '#W' 2>/dev/null | grep -q "^${window_name}$" && {
        echo -e "${YELLOW}Agent workspace ${agent_id} existe, switching...${NC}"
        tmux select-window -t "$window_name" 2>/dev/null || true
        return 0
    }

    [[ ! -d "$agent_dir" ]] && {
        echo -e "${BLUE}🤖 Création agent workspace ${agent_id}...${NC}"
        mkdir -p "$agent_dir"
        local cloned=0 skipped=0

        for repo_path in "$source_workspace"/*/; do
            [[ -d "${repo_path}.git" ]] || continue
            local repo_name=$(basename "$repo_path")
            [[ "$repo_name" == *"--agent"* ]] && continue

            local repo_url=$(cd "$repo_path" && git remote get-url origin 2>/dev/null)
            [[ -n "$repo_url" ]] && {
                echo -e "   📦 Clone: ${repo_name}"
                git clone "$repo_url" "${agent_dir}/${repo_name}" 2>/dev/null
                ((cloned++))
            } || ((skipped++))
        done
        echo -e "${GREEN}✅ ${cloned} repo(s) cloné(s)${NC}"
    }

    _open_agent_tmux "$window_name" "$agent_dir" "$task"
}

_open_agent_tmux() {
    local window_name="$1" agent_dir="$2" task="$3"

    [[ -n "$TMUX" ]] && {
        [[ -n "$task" ]] && \
            tmux new-window -n "$window_name" -c "$agent_dir" "claude --dangerously-skip-permissions -p \"$task\"; zsh" || \
            tmux new-window -n "$window_name" -c "$agent_dir" "claude --dangerously-skip-permissions; zsh"
        echo -e "${GREEN}✅ Agent lancé: $window_name${NC}"
    } || echo -e "${YELLOW}Lance dans tmux ou: cd $agent_dir && claude${NC}"
}

agent_list() {
    echo -e "${BLUE}🤖 Agents${NC}"
    local found=0 search_dir="$HOME/workspace"
    detect_context 2>/dev/null && search_dir="$WORKSPACE_DIR"

    for dir in "$search_dir"/*--agent*/; do
        [[ -d "$dir" ]] || continue
        found=1
        local name=$(basename "$dir")
        local agent_id="${name##*--agent}"
        local base_name="${name%--agent*}"
        local is_workspace=0
        [[ -d "${dir}"/*/.git ]] 2>/dev/null && is_workspace=1

        local info="—"
        [[ "$is_workspace" -eq 0 ]] && [[ -d "${dir}/.git" ]] && \
            info=$(cd "$dir" && echo "$(git branch --show-current) - $(git status --porcelain | wc -l | tr -d ' ') modif")
        [[ "$is_workspace" -eq 1 ]] && \
            info="$(find "$dir" -maxdepth 2 -name ".git" -type d 2>/dev/null | wc -l | tr -d ' ') repos"

        local tmux_status=""
        [[ -n "$TMUX" ]] && tmux list-windows -F '#W' 2>/dev/null | grep -q "^${base_name}:agent${agent_id}$" && \
            tmux_status=" ${GREEN}[actif]${NC}"

        local prefix=""
        [[ "$is_workspace" -eq 1 ]] && prefix="${CYAN}[ws]${NC} "
        echo -e "  ${prefix}agent${agent_id} (${info})${tmux_status}"
    done

    [[ "$found" -eq 0 ]] && echo -e "  ${CYAN}Aucun agent. Utilise: agent spawn <id>${NC}"
}

agent_kill() {
    local agent_id="$1"
    [[ -z "$agent_id" ]] && { echo "Usage: agent kill <id>"; return 1; }
    detect_context 2>/dev/null
    local window_name=""
    [[ "$AGENT_MODE" == "repo" ]] && window_name="${REPO_NAME}:agent${agent_id}"
    [[ "$AGENT_MODE" == "workspace" ]] && window_name="${WORKSPACE_NAME}:agent${agent_id}"
    [[ -n "$TMUX" ]] && [[ -n "$window_name" ]] && tmux kill-window -t "$window_name" 2>/dev/null && \
        echo -e "${GREEN}✅ Agent ${agent_id} fermé${NC}"
}

agent_delete() {
    local agent_id="$1" force="$2"
    [[ -z "$agent_id" ]] && { echo "Usage: agent delete <id> [--force]"; return 1; }
    detect_context 2>/dev/null

    local agent_dir=""
    [[ "$AGENT_MODE" == "repo" ]] && agent_dir="${WORKSPACE_DIR}/${REPO_NAME}--agent${agent_id}"
    [[ "$AGENT_MODE" == "workspace" ]] && agent_dir="${WORKSPACE_DIR}/${WORKSPACE_NAME}--agent${agent_id}"
    if [[ -z "$agent_dir" ]]; then
        for d in ~/workspace/*--agent${agent_id}/; do
            [[ -d "$d" ]] && agent_dir="$d" && break
        done
    fi

    [[ ! -d "$agent_dir" ]] && { echo -e "${RED}Agent ${agent_id} n'existe pas${NC}"; return 1; }

    [[ "$force" != "--force" ]] && {
        local dirty=0
        [[ -d "${agent_dir}/.git" ]] && {
            [[ $(cd "$agent_dir" && git status --porcelain | wc -l) -gt 0 ]] && dirty=1
            [[ $(cd "$agent_dir" && git log @{u}..HEAD --oneline 2>/dev/null | wc -l) -gt 0 ]] && dirty=1
        } || {
            for repo in "$agent_dir"/*/; do
                [[ -d "${repo}.git" ]] && {
                    [[ $(cd "$repo" && git status --porcelain | wc -l) -gt 0 ]] && dirty=1
                    [[ $(cd "$repo" && git log @{u}..HEAD --oneline 2>/dev/null | wc -l) -gt 0 ]] && dirty=1
                }
            done
        }
        [[ "$dirty" -eq 1 ]] && {
            echo -e "${RED}⚠️ Changements non sauvegardés! Utilise --force${NC}"
            return 1
        }
    }

    rm -rf "$agent_dir"
    echo -e "${GREEN}✅ Agent ${agent_id} supprimé${NC}"
}

agent() {
    case "$1" in
        spawn|s) shift; agent_spawn "$@" ;;
        list|ls|l) agent_list ;;
        kill|k) shift; agent_kill "$@" ;;
        delete|rm) shift; agent_delete "$@" ;;
        help|h|"")
            echo -e "${BLUE}🤖 Agent Manager v3${NC}"
            echo "  agent spawn <id> [task]  Créer un agent"
            echo "  agent list               Lister"
            echo "  agent kill <id>          Fermer tmux"
            echo "  agent delete <id>        Supprimer"
            echo ""
            echo "Depuis un repo: clone ce repo"
            echo "Depuis ~/workspace: clone tous les repos"
            ;;
        *) echo "Commande inconnue: $1" ;;
    esac
}

# If run directly (not sourced), execute agent command
# Works in both bash and zsh
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    # Bash: check if sourced
    [[ "${BASH_SOURCE[0]}" == "${0}" ]] && agent "$@"
elif [[ -n "${ZSH_VERSION:-}" ]]; then
    # Zsh: check if sourced (when sourced, $ZSH_EVAL_CONTEXT contains 'file')
    [[ ! "${ZSH_EVAL_CONTEXT:-}" =~ :file$ ]] && agent "$@"
fi
AGENTSCRIPT

# =============================================================================
# ENTRYPOINT
# =============================================================================
cat > entrypoint.sh << ENTRYPOINT_END
#!/bin/bash
set -e

echo "🚀 Démarrage Claude Box [${INSTANCE_NAME}]..."

echo "🔧 Permissions..."
chown -R dev:dev /home/dev/workspace 2>/dev/null || true
chown -R dev:dev /home/dev/.claude 2>/dev/null || true
chown -R dev:dev /home/dev/.claude-data 2>/dev/null || true
chown -R dev:dev /home/dev/.config 2>/dev/null || true
chown -R dev:dev /home/dev/.npm-global 2>/dev/null || true
chown -R dev:dev /home/dev/.npm 2>/dev/null || true
chown -R dev:dev /home/dev/.secrets 2>/dev/null || true
chown -R dev:dev /home/dev/.gitconfig-dir 2>/dev/null || true
chown -R dev:dev /home/dev/.local 2>/dev/null || true
chown dev:dev /home/dev/.ssh 2>/dev/null || true
chmod 700 /home/dev/.ssh 2>/dev/null || true
chown -R dev:dev /home/dev/.ssh-keys 2>/dev/null || true
chmod 700 /home/dev/.ssh-keys 2>/dev/null || true

# Symlink .claude.json to persistent volume (stores OAuth session)
if [ ! -L /home/dev/.claude.json ]; then
    [ -f /home/dev/.claude.json ] && mv /home/dev/.claude.json /home/dev/.claude-data/claude.json 2>/dev/null || true
    [ ! -f /home/dev/.claude-data/claude.json ] && echo '{}' > /home/dev/.claude-data/claude.json
    ln -sf /home/dev/.claude-data/claude.json /home/dev/.claude.json
    chown dev:dev /home/dev/.claude-data/claude.json /home/dev/.claude.json 2>/dev/null || true
fi

# Symlink zsh_history to persistent volume
chown -R dev:dev /home/dev/.zsh-data 2>/dev/null || true
if [ ! -L /home/dev/.zsh_history ]; then
    [ -f /home/dev/.zsh_history ] && mv /home/dev/.zsh_history /home/dev/.zsh-data/zsh_history 2>/dev/null || true
    [ ! -f /home/dev/.zsh-data/zsh_history ] && touch /home/dev/.zsh-data/zsh_history
    ln -sf /home/dev/.zsh-data/zsh_history /home/dev/.zsh_history
    chown dev:dev /home/dev/.zsh-data/zsh_history /home/dev/.zsh_history 2>/dev/null || true
fi

# Symlink known_hosts to persistent volume (inside ssh-keys)
if [ ! -L /home/dev/.ssh/known_hosts ]; then
    [ -f /home/dev/.ssh/known_hosts ] && mv /home/dev/.ssh/known_hosts /home/dev/.ssh-keys/known_hosts 2>/dev/null || true
    [ ! -f /home/dev/.ssh-keys/known_hosts ] && touch /home/dev/.ssh-keys/known_hosts
    ln -sf /home/dev/.ssh-keys/known_hosts /home/dev/.ssh/known_hosts
    chown dev:dev /home/dev/.ssh-keys/known_hosts /home/dev/.ssh/known_hosts 2>/dev/null || true
fi

if [ "\$(ls -A /home/dev/.ssh-keys 2>/dev/null)" ]; then
    chmod 600 /home/dev/.ssh-keys/* 2>/dev/null || true
    for key in /home/dev/.ssh-keys/id_*; do
        [ -f "\$key" ] && ln -sf "\$key" "/home/dev/.ssh/\$(basename "\$key")" 2>/dev/null || true
    done
fi

[ -f /home/dev/.gitconfig-dir/config ] && ln -sf /home/dev/.gitconfig-dir/config /home/dev/.gitconfig 2>/dev/null || true

echo "🌐 Tailscale..."
mkdir -p /var/run/tailscale
tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock &
sleep 2

if tailscale status > /dev/null 2>&1; then
    echo "✅ Tailscale connecté"
else
    [ -n "\$TAILSCALE_AUTHKEY" ] && tailscale up --authkey="\$TAILSCALE_AUTHKEY" --hostname="claude-box-${INSTANCE_NAME}" || \
        echo "⚠️  tailscale up --hostname=claude-box-${INSTANCE_NAME}"
fi

tailscale status > /dev/null 2>&1 && echo "📍 IP: \$(tailscale ip -4)"

echo "🔐 Activation Tailscale SSH..."
tailscale set --ssh
echo "✅ Tailscale SSH activé (connexion sans clé SSH)"

# Vérification environnement MCP
echo "🔌 Vérification environnement MCP..."
echo "   Chromium: \$(chromium --version 2>/dev/null || echo 'non trouvé')"
echo "   Node.js: \$(node --version)"
echo "   uvx: \$(uvx --version 2>/dev/null || echo 'non trouvé')"

# Quick headless test
if chromium --headless --no-sandbox --disable-gpu --dump-dom about:blank >/dev/null 2>&1; then
    echo "   ✅ Chromium headless: OK"
else
    echo "   ⚠️  Chromium headless: échec"
fi

echo "✅ Container prêt!"
echo "   💡 Première connexion: lance ~/first-run.sh"
exec tail -f /dev/null
ENTRYPOINT_END

# =============================================================================
# FIRST RUN SCRIPT
# =============================================================================
cat > first-run.sh << 'FIRSTRUN'
#!/bin/bash
set -e

echo "🔧 Configuration initiale de Claude Box"
echo "========================================"

# Git config
if [ ! -f ~/.gitconfig-dir/config ]; then
    read -p "Ton nom (pour git): " GIT_NAME
    read -p "Ton email (pour git): " GIT_EMAIL
    mkdir -p ~/.gitconfig-dir
    cat > ~/.gitconfig-dir/config << EOF
[user]
    name = $GIT_NAME
    email = $GIT_EMAIL
[init]
    defaultBranch = main
[pull]
    rebase = false
EOF
    ln -sf ~/.gitconfig-dir/config ~/.gitconfig
    echo "✅ Git configuré"
fi

# SSH key
if [ ! -f ~/.ssh-keys/id_ed25519 ]; then
    read -p "Email pour la clé SSH: " SSH_EMAIL
    mkdir -p ~/.ssh-keys
    ssh-keygen -t ed25519 -C "$SSH_EMAIL" -f ~/.ssh-keys/id_ed25519 -N ""
    ln -sf ~/.ssh-keys/id_ed25519 ~/.ssh/id_ed25519
    ln -sf ~/.ssh-keys/id_ed25519.pub ~/.ssh/id_ed25519.pub
    cat > ~/.ssh/config << EOF
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
EOF
    echo ""
    echo "✅ Clé SSH générée. Ajoute-la à GitHub:"
    echo "   https://github.com/settings/ssh/new"
    echo ""
    cat ~/.ssh-keys/id_ed25519.pub
    echo ""
    read -p "Appuie sur Entrée quand c'est fait..."
    ssh -T git@github.com 2>&1 || true
fi

# GitHub CLI
if ! gh auth status > /dev/null 2>&1; then
    echo ""
    echo "🐙 GitHub CLI"
    gh auth login
fi

# SuperClaude
if ! command -v superclaude &> /dev/null; then
    echo ""
    echo "🦸 Installation SuperClaude..."
    pipx install superclaude
    superclaude install
fi

# =============================================================================
# CLAUDE CODE SETTINGS
# =============================================================================
echo ""
echo "⚙️  Configuration Claude Code settings..."

mkdir -p ~/.claude
if [ ! -f ~/.claude/settings.json ]; then
    cat > ~/.claude/settings.json << 'SETTINGS_EOF'
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "includeCoAuthoredBy": false
}
SETTINGS_EOF
    echo "   ✅ settings.json créé"
else
    # Ensure required settings exist (merge with existing)
    if command -v jq &> /dev/null; then
        TMP_SETTINGS=$(mktemp)
        jq '. + {"env": (.env // {} | . + {"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"}), "includeCoAuthoredBy": false}' ~/.claude/settings.json > "$TMP_SETTINGS" 2>/dev/null && mv "$TMP_SETTINGS" ~/.claude/settings.json
        echo "   ✅ settings.json mis à jour"
    else
        echo "   ⚠️  settings.json existe, vérification manuelle recommandée"
    fi
fi

# =============================================================================
# MCP SERVERS CONFIGURATION (SuperClaude Recommended)
# =============================================================================
echo ""
echo "🔌 Configuration MCP Servers..."

# --- Vérifier que uvx est disponible ---
echo ""
echo "   Vérification de uv/uvx..."
if command -v uvx &> /dev/null; then
    echo "   ✅ uvx disponible"
else
    echo "   ⚠️  uvx non trouvé, installation..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
    echo "   ✅ uv installé"
fi

# --- 1. Context7 ---
echo ""
echo "   [1/5] Context7 (documentation lookup)..."
if ! claude mcp list 2>/dev/null | grep -q "context7"; then
    claude mcp add --scope user context7 -- npx -y @upstash/context7-mcp
    echo "   ✅ Context7 enregistré"
else
    echo "   ✅ Context7 déjà enregistré"
fi

# --- 2. Sequential-Thinking ---
echo ""
echo "   [2/5] Sequential-Thinking (multi-step reasoning)..."
if ! claude mcp list 2>/dev/null | grep -q "sequential-thinking"; then
    claude mcp add --scope user sequential-thinking -- npx -y @modelcontextprotocol/server-sequential-thinking
    echo "   ✅ Sequential-Thinking enregistré"
else
    echo "   ✅ Sequential-Thinking déjà enregistré"
fi

# --- 3. Serena ---
echo ""
echo "   [3/5] Serena (semantic code understanding)..."
if ! claude mcp list 2>/dev/null | grep -q "serena"; then
    claude mcp add --scope user serena -- uvx --from git+https://github.com/oraios/serena serena start-mcp-server --project /home/dev/workspace
    echo "   ✅ Serena enregistré"
else
    echo "   ✅ Serena déjà enregistré"
fi

# --- 4. Playwright ---
echo ""
echo "   [4/5] Playwright MCP (browser automation - headless)..."
if ! claude mcp list 2>/dev/null | grep -q "playwright"; then
    claude mcp add --scope user playwright -- npx @playwright/mcp@latest --headless --browser chromium
    echo "   ✅ Playwright enregistré (headless mode)"
else
    echo "   ✅ Playwright déjà enregistré"
fi

# --- 5. Chrome DevTools ---
echo ""
echo "   [5/5] Chrome DevTools MCP (browser debugging - headless)..."
if ! claude mcp list 2>/dev/null | grep -q "chrome-devtools"; then
    claude mcp add --scope user chrome-devtools -- npx chrome-devtools-mcp@latest --headless --executablePath /usr/bin/chromium --no-sandbox
    echo "   ✅ Chrome DevTools enregistré (headless mode)"
else
    echo "   ✅ Chrome DevTools déjà enregistré"
fi

echo ""
echo "   📊 MCP Servers configurés:"
echo "   - context7           : Documentation lookup"
echo "   - sequential-thinking: Multi-step reasoning"
echo "   - serena             : Semantic code understanding"
echo "   - playwright         : Browser automation (headless)"
echo "   - chrome-devtools    : Browser debugging (headless)"

# Secrets
[ ! -f ~/.secrets/env ] && { mkdir -p ~/.secrets; echo "# Secrets" > ~/.secrets/env; }

echo ""
echo "========================================"
echo "✅ Configuration terminée!"
echo ""
echo "Commandes utiles:"
echo "  claude              Lancer Claude Code"
echo "  agent help          Gérer les agents parallèles"
echo "  mcp-list            Lister les MCP servers"
echo "  chromium-test       Tester Chromium headless"
echo ""
echo "MCP Servers configurés (tous locaux):"
echo "  - context7           : Documentation lookup"
echo "  - sequential-thinking: Multi-step reasoning"
echo "  - serena             : Semantic code understanding"
echo "  - playwright         : Browser automation (headless)"
echo "  - chrome-devtools    : Browser debugging (headless)"
echo ""
FIRSTRUN

# =============================================================================
# TMUX CONFIG
# =============================================================================
cat > tmux.conf << TMUX_END
set -g prefix C-a
unbind C-b
bind C-a send-prefix
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R
set -g mouse off
set -g history-limit 100000
set -g status-style bg=colour235,fg=colour136
set -g status-left '#[fg=green]🐳 ${INSTANCE_NAME} #[fg=white]| '
set -g status-right '#[fg=cyan]MCP #[fg=yellow]%H:%M'
set -g base-index 1
setw -g pane-base-index 1
bind r source-file ~/.tmux.conf \; display "Reloaded!"
set -sg escape-time 10
set -g default-terminal "screen-256color"
set -g default-shell /bin/zsh
set -g default-command /bin/zsh
TMUX_END

# =============================================================================
# DOCKER COMPOSE
# =============================================================================
cat > docker-compose.yml << COMPOSE_END
services:
  claude-box-${INSTANCE_NAME}:
    build: .
    image: claude-box-${INSTANCE_NAME}
    container_name: claude-box-${INSTANCE_NAME}
    hostname: claude-box-${INSTANCE_NAME}
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    devices:
      - /dev/net/tun:/dev/net/tun
    shm_size: '2gb'
    volumes:
      - ${INSTANCE_NAME}_workspace:/home/dev/workspace
      - ${INSTANCE_NAME}_claude-config:/home/dev/.claude
      - ${INSTANCE_NAME}_claude-data:/home/dev/.claude-data
      - ${INSTANCE_NAME}_claude-npm:/home/dev/.npm-global
      - ${INSTANCE_NAME}_gh-config:/home/dev/.config/gh
      - ${INSTANCE_NAME}_ssh-keys:/home/dev/.ssh-keys
      - ${INSTANCE_NAME}_git-config:/home/dev/.gitconfig-dir
      - ${INSTANCE_NAME}_secrets:/home/dev/.secrets
      - ${INSTANCE_NAME}_local-bin:/home/dev/.local
      - ${INSTANCE_NAME}_npm-cache:/home/dev/.npm
      - ${INSTANCE_NAME}_zsh-data:/home/dev/.zsh-data
      - ${INSTANCE_NAME}_tailscale-state:/var/lib/tailscale
    environment:
      - ANTHROPIC_API_KEY=\${ANTHROPIC_API_KEY:-}
      - TAILSCALE_AUTHKEY=\${TAILSCALE_AUTHKEY:-}
      - TZ=\${TZ:-UTC}
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 8G
        reservations:
          cpus: '0.5'
          memory: 2G

volumes:
  ${INSTANCE_NAME}_workspace:
  ${INSTANCE_NAME}_claude-config:
  ${INSTANCE_NAME}_claude-data:
  ${INSTANCE_NAME}_claude-npm:
  ${INSTANCE_NAME}_gh-config:
  ${INSTANCE_NAME}_ssh-keys:
  ${INSTANCE_NAME}_git-config:
  ${INSTANCE_NAME}_secrets:
  ${INSTANCE_NAME}_local-bin:
  ${INSTANCE_NAME}_npm-cache:
  ${INSTANCE_NAME}_zsh-data:
  ${INSTANCE_NAME}_tailscale-state:
COMPOSE_END

# =============================================================================
# START SCRIPT
# =============================================================================
cat > start.sh << START_END
#!/bin/bash
LOGFILE="${CLAUDE_DIR}/start.log"
exec > "\$LOGFILE" 2>&1
echo "\$(date): Démarrage claude-box-${INSTANCE_NAME}..."

MAX_WAIT=120
WAITED=0
while ! /usr/local/bin/docker info > /dev/null 2>&1; do
    [ \$WAITED -ge \$MAX_WAIT ] && { echo "\$(date): Docker timeout"; exit 1; }
    sleep 5
    WAITED=\$((WAITED + 5))
done
echo "\$(date): Docker prêt (\${WAITED}s)"

cd "${CLAUDE_DIR}"
/usr/local/bin/docker compose up -d
echo "\$(date): Container démarré"
START_END
chmod +x start.sh

# =============================================================================
# AUTO-START SERVICE (macOS LaunchAgent / Linux systemd)
# =============================================================================
case "$(uname -s)" in
    Darwin)
        PLIST_NAME="com.claude-box.${INSTANCE_NAME}.plist"
        cat > "$PLIST_NAME" << PLIST_END
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claude-box.${INSTANCE_NAME}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${CLAUDE_DIR}/start.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${CLAUDE_DIR}/launchagent.log</string>
    <key>StandardErrorPath</key>
    <string>${CLAUDE_DIR}/launchagent.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
</dict>
</plist>
PLIST_END
        AUTOSTART_FILE="$PLIST_NAME"
        ;;
    Linux)
        SYSTEMD_NAME="claude-box-${INSTANCE_NAME}.service"
        cat > "$SYSTEMD_NAME" << SYSTEMD_END
[Unit]
Description=Claude Box ${INSTANCE_NAME}
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${CLAUDE_DIR}
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
User=$(whoami)
Group=$(id -gn)

[Install]
WantedBy=multi-user.target
SYSTEMD_END
        AUTOSTART_FILE="$SYSTEMD_NAME"
        ;;
esac

# =============================================================================
# BUILD & LAUNCH
# =============================================================================
echo ""
echo "📦 Build de l'image Docker..."
docker compose build

echo ""
echo "🚀 Démarrage du container..."
docker compose up -d

echo ""
echo "⏳ Attente du démarrage du container..."
sleep 5

# Check if container is running
if docker ps --format '{{.Names}}' | grep -q "claude-box-${INSTANCE_NAME}"; then
    echo "✅ Container démarré"

    echo ""
    echo "🌐 Configuration Tailscale..."
    echo "   (Suis le lien pour authentifier si nécessaire)"
    docker exec -it claude-box-${INSTANCE_NAME} tailscale up --hostname=claude-box-${INSTANCE_NAME}

    # Get Tailscale IP
    TAILSCALE_IP=$(docker exec claude-box-${INSTANCE_NAME} tailscale ip -4 2>/dev/null)
    if [ -n "$TAILSCALE_IP" ]; then
        echo ""
        echo "✅ Tailscale connecté: $TAILSCALE_IP"
    fi
else
    echo "⚠️  Container non démarré. Vérifie avec: docker compose logs"
fi

# =============================================================================
# AUTO-START SETUP
# =============================================================================
echo ""
read -p "🔄 Configurer le démarrage automatique au boot ? [Y/n]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    case "$(uname -s)" in
        Darwin)
            mkdir -p ~/Library/LaunchAgents
            cp "${CLAUDE_DIR}/${PLIST_NAME}" ~/Library/LaunchAgents/
            launchctl load ~/Library/LaunchAgents/${PLIST_NAME}
            echo "✅ LaunchAgent installé (macOS)"
            ;;
        Linux)
            sudo cp "${CLAUDE_DIR}/${SYSTEMD_NAME}" /etc/systemd/system/
            sudo systemctl daemon-reload
            sudo systemctl enable "claude-box-${INSTANCE_NAME}"
            echo "✅ Service systemd installé (Linux)"
            ;;
    esac
fi

echo ""
echo "============================================"
echo "✅ Installation terminée!"
echo "============================================"
echo ""
echo "📦 Instance: ${INSTANCE_NAME}"
echo "📁 Répertoire: ${CLAUDE_DIR}"
if [ -n "$TAILSCALE_IP" ]; then
echo "🌐 Tailscale IP: $TAILSCALE_IP"
fi
echo ""
echo "🔐 Connexion (Tailscale SSH - pas besoin de clés SSH !):"
echo "  ssh dev@claude-box-${INSTANCE_NAME}"
echo ""
echo "  Tailscale SSH utilise ton identité Tailscale."
echo "  Assure-toi d'être connecté au même tailnet."
echo ""
echo "Première connexion:"
echo "  ~/first-run.sh"
echo ""
echo "🔌 MCP Servers (tous locaux):"
echo "  - context7           : Documentation lookup"
echo "  - sequential-thinking: Multi-step reasoning"
echo "  - serena             : Semantic code understanding"
echo "  - playwright         : Browser automation (headless)"
echo "  - chrome-devtools    : Browser debugging (headless)"
echo ""
echo "📝 Dans le container:"
echo "  mcp-list       - Lister les MCP servers"
echo "  chromium-test  - Tester Chromium headless"
echo "  agent help     - Gérer les agents"
echo "============================================"
