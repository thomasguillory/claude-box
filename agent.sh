#!/usr/bin/env bash
# Agent manager for parallel Claude instances v4
# Compatible with both bash and zsh

# Zsh compatibility: prevent glob errors when no matches
if [[ -n "${ZSH_VERSION:-}" ]]; then
    setopt NULL_GLOB NO_NOMATCH 2>/dev/null || true
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

        local subdirs=()
        if [[ -n "${ZSH_VERSION:-}" ]]; then
            subdirs=( "$current_dir"/*/(N) )
        else
            shopt -s nullglob 2>/dev/null
            subdirs=( "$current_dir"/*/ )
            shopt -u nullglob 2>/dev/null
        fi
        for subdir in "${subdirs[@]}"; do
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

    if [[ "$AGENT_MODE" == "repo" ]]; then
        _spawn_repo_agent "$agent_id" "$task"
    else
        _spawn_workspace_agent "$agent_id" "$task"
    fi
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

        local repo_paths=()
        if [[ -n "${ZSH_VERSION:-}" ]]; then
            repo_paths=( "$source_workspace"/*/(N) )
        else
            shopt -s nullglob 2>/dev/null
            repo_paths=( "$source_workspace"/*/ )
            shopt -u nullglob 2>/dev/null
        fi
        for repo_path in "${repo_paths[@]}"; do
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

    # Handle glob that may have no matches (zsh compatibility)
    local dirs=()
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        dirs=( "$search_dir"/*--agent*/(N) )
    else
        shopt -s nullglob 2>/dev/null
        dirs=( "$search_dir"/*--agent*/ )
        shopt -u nullglob 2>/dev/null
    fi

    for dir in "${dirs[@]}"; do
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
        local search_dirs=()
        if [[ -n "${ZSH_VERSION:-}" ]]; then
            search_dirs=( ~/workspace/*--agent${agent_id}/(N) )
        else
            shopt -s nullglob 2>/dev/null
            search_dirs=( ~/workspace/*--agent${agent_id}/ )
            shopt -u nullglob 2>/dev/null
        fi
        for d in "${search_dirs[@]}"; do
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
            local repos=()
            if [[ -n "${ZSH_VERSION:-}" ]]; then
                repos=( "$agent_dir"/*/(N) )
            else
                shopt -s nullglob 2>/dev/null
                repos=( "$agent_dir"/*/ )
                shopt -u nullglob 2>/dev/null
            fi
            for repo in "${repos[@]}"; do
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
