#!/usr/bin/env bash

################################################################################
# install-agent.sh - Install pi-coding-agent agent definitions
#
# Discovers agents from agents/pi/*.md files.
# All installations use symbolic links to the source files.
#
# Usage:
#   ./install-agent.sh --help                        # Show this help message
#   ./install-agent.sh --list                        # List available agents
#   ./install-agent.sh --all                         # Install all agents
#   ./install-agent.sh --interactive                 # Interactive wizard
#   ./install-agent.sh <agent1> [agent2]             # Install specific agent(s)
#   ./install-agent.sh --force --all                 # Skip confirmation prompts
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_DIR="$SCRIPT_DIR/agents/pi"
INSTALL_BASE=""          # resolved in resolve_install_base()
TARGET_DIR=""            # set via --target-dir (defaults to $HOME for global installs)

# Global flags
AGENT_NAMES=()
LIST_MODE=false
INTERACTIVE_MODE=false
FORCE_MODE=false
INSTALL_ALL=false

################################################################################
# Utility Functions
################################################################################

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}" >&2
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

################################################################################
# Usage
################################################################################

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [AGENT...]

Install pi-coding-agent agent definitions.

ARGUMENTS:
    AGENT...              One or more agent names to install (without .md extension)

OPTIONS:
    --all                 Install all available agents
    --list                List available agents without installing
    --interactive         Start interactive installation wizard
    --force               Skip confirmation prompts
    --target-dir DIR      Install into <DIR>/.pi/agent/agents/ instead of ~/.pi/agent/agents/
    --help, -h            Show this help message and exit

EXAMPLES:
    # List available agents
    $(basename "$0") --list

    # Install all agents interactively
    $(basename "$0") --interactive

    # Install a specific agent (defaults to ~/.pi/agent/agents/)
    $(basename "$0") web-researcher

    # Install a specific agent into a custom directory
    $(basename "$0") --target-dir /path/to/project web-researcher

    # Install all agents without prompts
    $(basename "$0") --all --force

INSTALLATION METHOD:
    All agents are installed via symbolic links.
    Default target: ~/.pi/agent/agents/
    Custom target:  <target-dir>/.pi/agent/agents/
    Example: agents/pi/web-researcher.md -> <target>/web-researcher.md

AGENT FORMAT:
    Each agent is a single markdown file (.md) in agents/pi/

EOF
}

################################################################################
# Argument Parsing
################################################################################

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                usage
                exit 0
                ;;
            --list)
                LIST_MODE=true
                shift
                ;;
            --interactive)
                INTERACTIVE_MODE=true
                shift
                ;;
            --force)
                FORCE_MODE=true
                shift
                ;;
            --all)
                INSTALL_ALL=true
                shift
                ;;
            --target-dir|-t)
                if [[ -z "$2" || "$2" == --* ]]; then
                    print_error "Missing value for --target-dir"
                    exit 1
                fi
                TARGET_DIR="$2"
                shift 2
                ;;
            --*)
                print_error "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                AGENT_NAMES+=("$1")
                shift
                ;;
        esac
    done

    # Validate --target-dir if provided
    if [[ -n "$TARGET_DIR" ]]; then
        if [[ ! -d "$TARGET_DIR" ]]; then
            print_error "Target directory does not exist: $TARGET_DIR"
            exit 1
        fi
        TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"
    fi

    # Need at least one action
    if [[ "$LIST_MODE" == false && "$INTERACTIVE_MODE" == false && "$INSTALL_ALL" == false && ${#AGENT_NAMES[@]} -eq 0 ]]; then
        print_error "No action specified. Use --all, --list, --interactive, or provide agent name(s)."
        echo ""
        usage
        exit 1
    fi
}

resolve_install_base() {
    if [[ -n "$TARGET_DIR" ]]; then
        INSTALL_BASE="$TARGET_DIR/.pi/agent/agents"
    else
        INSTALL_BASE="$HOME/.pi/agent/agents"
    fi
}

################################################################################
# Agent Discovery
################################################################################

get_available_agents() {
    local agents=()

    if [[ ! -d "$AGENTS_DIR" ]]; then
        print_error "Agents directory not found: $AGENTS_DIR"
        exit 1
    fi

    for agent_path in "$AGENTS_DIR"/*.md; do
        [[ -f "$agent_path" ]] || continue
        [[ "$agent_path" == *.chain.md ]] && continue  # legacy chain definitions, not agents
        agents+=("$(basename "$agent_path" .md)")
    done

    # Output each agent on its own line (newline-separated)
    printf '%s\n' "${agents[@]}"
}

get_agent_description() {
    local agent_name="$1"
    local agent_file="$AGENTS_DIR/$agent_name.md"
    local description=""

    if [[ -f "$agent_file" ]]; then
        # Try to get description from frontmatter
        description=$(grep -E "^description:" "$agent_file" | head -1 | sed 's/^description:[[:space:]]*//' | cut -c1-60)
        # Fall back to first non-empty, non-heading line
        if [[ -z "$description" ]]; then
            description=$(grep -v '^#' "$agent_file" | grep -v '^[[:space:]]*$' | grep -v '^---' | head -1 | cut -c1-60)
        fi
    fi

    echo "${description:-No description available}"
}

################################################################################
# List Agents
################################################################################

list_agents() {
    print_header "Available Pi Agents"
    echo ""

    local agents_arr=()
    while IFS= read -r agent; do
        agents_arr+=("$agent")
    done < <(get_available_agents)
    local count=${#agents_arr[@]}

    if [[ $count -eq 0 ]]; then
        print_warning "No agents found in $AGENTS_DIR"
        exit 1
    fi

    printf "%-35s %-20s %s\n" "AGENT NAME" "STATUS" "DESCRIPTION"
    echo "--------------------------------------------------------------------"

    for agent_name in "${agents_arr[@]}"; do
        local target="$INSTALL_BASE/$agent_name.md"
        local installed=""

        if [[ -L "$target" ]]; then
            local link_target
            link_target=$(readlink "$target")
            installed="${GREEN}[symlink]${NC} -> $link_target"
        elif [[ -f "$target" ]]; then
            installed="${YELLOW}[installed]${NC}"
        fi

        local desc
        desc=$(get_agent_description "$agent_name")

        printf "%-35s " "$agent_name"
        echo -e "${installed:-not installed}  ${desc}"
    done

    echo ""
    echo "Total agents available: $count"
    echo "Installation target: $INSTALL_BASE (via symlinks)"
}

################################################################################
# Installation Core
################################################################################

create_install_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        print_success "Created directory: $dir"
    fi
}

validate_agent() {
    local agent_name="$1"
    local agent_file="$AGENTS_DIR/$agent_name.md"

    if [[ ! -f "$agent_file" ]]; then
        print_error "Agent not found: $agent_file"
        return 1
    fi

    return 0
}

install_single_agent() {
    local agent_name="$1"
    local source_path="$AGENTS_DIR/$agent_name.md"
    local target_path="$INSTALL_BASE/$agent_name.md"

    # Validate
    if ! validate_agent "$agent_name"; then
        return 1
    fi

    # Handle existing installation
    if [[ -L "$target_path" ]]; then
        local current_target
        current_target=$(readlink "$target_path")
        if [[ "$current_target" == "$source_path" ]]; then
            print_success "Already installed (symlink correct): $agent_name -> $target_path"
            return 0
        fi
        print_warning "Existing symlink points elsewhere: $target_path -> $current_target"
        rm -f "$target_path"
    elif [[ -f "$target_path" ]]; then
        print_warning "Existing file (not a symlink): $target_path"
        rm -f "$target_path"
    fi

    ln -s "$source_path" "$target_path"
    print_success "Installed (symlink): $agent_name.md -> $target_path"

    return 0
}

install_agents() {
    local agents=("$@")
    local success_count=0
    local fail_count=0

    create_install_dir "$INSTALL_BASE"

    for agent in "${agents[@]}"; do
        echo ""
        print_info "Processing: $agent"
        if install_single_agent "$agent"; then
            ((success_count++)) || true
        else
            ((fail_count++)) || true
        fi
    done

    echo ""
    print_header "Installation Summary"
    echo -e "  Success: ${GREEN}$success_count${NC}"
    [[ $fail_count -gt 0 ]] && echo -e "  Failed:  ${RED}$fail_count${NC}"

    if [[ $fail_count -gt 0 ]]; then
        return 1
    fi
    return 0
}

################################################################################
# Interactive Mode
################################################################################

interactive_installation() {
    print_header "Pi Agent Installation Wizard"
    echo ""

    # Step 1: Target directory
    echo -e "${BLUE}Step 1: Select target directory${NC}"
    echo ""
    echo "  Agents will be installed into <target-dir>/.pi/agent/agents/"
    echo ""
    read -r -p "  Enter target directory [${HOME}]: " target_dir_input
    target_dir_input="${target_dir_input:-$HOME}"
    target_dir_input="${target_dir_input/#\~/$HOME}"

    if [[ ! -d "$target_dir_input" ]]; then
        print_error "Directory does not exist: $target_dir_input"
        exit 1
    fi

    TARGET_DIR="$(cd "$target_dir_input" && pwd)"
    resolve_install_base
    print_success "Install target: $INSTALL_BASE"
    echo ""

    local all_agents_arr=()
    while IFS= read -r agent; do
        all_agents_arr+=("$agent")
    done < <(get_available_agents)

    if [[ ${#all_agents_arr[@]} -eq 0 ]]; then
        print_warning "No agents found in $AGENTS_DIR"
        exit 1
    fi

    echo -e "${BLUE}Step 2: Select agents to install${NC}"
    echo ""

    local i=1
    declare -A agent_map=()

    for agent in "${all_agents_arr[@]}"; do
        local target="$INSTALL_BASE/$agent.md"
        local installed=""

        if [[ -L "$target" ]]; then
            installed=" ${GREEN}[symlink installed]${NC}"
        elif [[ -f "$target" ]]; then
            installed=" ${YELLOW}[installed]${NC}"
        fi

        printf "  %2d) %s" "$i" "$agent"
        echo -e "${installed}"
        agent_map["$i"]="$agent"
        ((i++))
    done

    echo ""
    echo "  a) Install ALL agents"
    echo "  q) Quit"
    echo ""

    read -r -p "Enter choice(s) - number(s) comma-separated, 'a' for all, 'q' to quit: [a] " selection
    selection=${selection:-a}

    local selected_agents=()

    if [[ "$selection" == "q" ]]; then
        print_warning "Installation cancelled"
        exit 0
    elif [[ "$selection" == "a" ]]; then
        selected_agents=("${all_agents_arr[@]}")
        print_success "Selected all ${#all_agents_arr[@]} agents"
    else
        IFS=',' read -ra indices <<< "$selection"
        for idx in "${indices[@]}"; do
            idx=$(echo "$idx" | tr -d ' ')
            if [[ -n "${agent_map[$idx]}" ]]; then
                selected_agents+=("${agent_map[$idx]}")
                print_success "Selected: ${agent_map[$idx]}"
            else
                print_warning "Invalid number: $idx"
            fi
        done

        if [[ ${#selected_agents[@]} -eq 0 ]]; then
            print_error "No valid agents selected"
            exit 1
        fi
    fi

    echo ""
    print_header "Installation Plan"
    echo ""
    echo "  Target: $INSTALL_BASE"
    echo ""
    echo "  Agents (${#selected_agents[@]}):"
    for agent in "${selected_agents[@]}"; do
        echo "    - $agent.md  ->  ~/.pi/agent/agents/$agent.md"
    done
    echo ""

    read -r -p "Proceed with installation? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_warning "Installation cancelled"
        exit 0
    fi

    echo ""
    install_agents "${selected_agents[@]}"

    post_install_info
}

################################################################################
# Post-install Info
################################################################################

post_install_info() {
    echo ""
    print_header "Post-Installation Notes"
    echo ""
    echo -e "  Agents installed to: ${GREEN}$INSTALL_BASE${NC}"
    echo ""
    echo "  Installed agents:"
    for f in "$INSTALL_BASE"/*.md; do
        [[ -f "$f" ]] || continue
        local name
        name=$(basename "$f")
        if [[ -L "$f" ]]; then
            echo -e "    ${GREEN}✓${NC} $name  ${BLUE}(symlink -> $(readlink "$f"))${NC}"
        else
            echo -e "    ${GREEN}✓${NC} $name"
        fi
    done
    echo ""
}

################################################################################
# Main
################################################################################

main() {
    parse_arguments "$@"
    resolve_install_base

    if [[ "$LIST_MODE" == true ]]; then
        list_agents
        exit 0
    fi

    if [[ "$INTERACTIVE_MODE" == true ]]; then
        interactive_installation
        exit $?
    fi

    # Determine agents to install
    local to_install_arr=()

    if [[ "$INSTALL_ALL" == true ]]; then
        while IFS= read -r agent; do
            to_install_arr+=("$agent")
        done < <(get_available_agents)
        if [[ ${#to_install_arr[@]} -eq 0 ]]; then
            print_error "No agents found in $AGENTS_DIR"
            exit 1
        fi
    else
        to_install_arr=("${AGENT_NAMES[@]}")
    fi

    # Validate all named agents up front
    local valid=true
    for agent in "${to_install_arr[@]}"; do
        if ! validate_agent "$agent"; then
            valid=false
        fi
    done
    [[ "$valid" == false ]] && exit 1

    # Print plan
    print_header "Installing Pi Agents"
    echo ""
    echo "  Target: $INSTALL_BASE"
    echo "  Count:  ${#to_install_arr[@]}"

    if [[ "$FORCE_MODE" != true ]]; then
        echo ""
        read -r -p "Proceed with installation? [y/N] " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            print_warning "Installation cancelled"
            exit 0
        fi
    fi

    install_agents "${to_install_arr[@]}"

    echo ""
    print_success "Done!"
    post_install_info
}

main "$@"
