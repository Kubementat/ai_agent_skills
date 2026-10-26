#!/usr/bin/env bash

################################################################################
# install-extension.sh - Install pi-coding-agent extensions
#
# Discovers extensions from extensions/pi/*/ directories.
# Each extension must contain index.ts (required).
# All installations use symbolic links to the source directory.
#
# Usage:
#   ./install-extension.sh --help                        # Show this help message
#   ./install-extension.sh --list                        # List available extensions
#   ./install-extension.sh --all                         # Install all extensions
#   ./install-extension.sh --interactive                 # Interactive wizard
#   ./install-extension.sh <ext1> [ext2]                 # Install specific extension(s)
#   ./install-extension.sh --force --all                 # Skip confirmation prompts
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
EXTENSIONS_DIR="$SCRIPT_DIR/extensions/pi"
INSTALL_BASE=""          # resolved in resolve_install_base()
TARGET_DIR=""            # set via --target-dir (defaults to $HOME)

# Global flags
EXTENSION_NAMES=()
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
Usage: $(basename "$0") [OPTIONS] [EXTENSION...]

Install pi-coding-agent extensions.

ARGUMENTS:
    EXTENSION...          One or more extension names to install (optional)

OPTIONS:
    --all                 Install all available extensions
    --list                List available extensions without installing
    --interactive         Start interactive installation wizard
    --force               Skip confirmation prompts
    --target-dir DIR      Install into <DIR>/.pi/agent/extensions/ instead of ~/.pi/agent/extensions/
    --help, -h            Show this help message and exit

EXAMPLES:
    # List available extensions
    $(basename "$0") --list

    # Install all extensions interactively
    $(basename "$0") --interactive

    # Install a specific extension (defaults to ~/.pi/agent/extensions/)
    $(basename "$0") fetch-tool

    # Install a specific extension into a custom directory
    $(basename "$0") --target-dir /path/to/project fetch-tool

    # Install all extensions without prompts
    $(basename "$0") --all --force

INSTALLATION METHOD:
    All extensions are installed via symbolic links.
    Default target: ~/.pi/agent/extensions/
    Custom target:  <target-dir>/.pi/agent/extensions/
    Example: fetch-tool -> <target>/fetch-tool

EXTENSION FORMAT:
    Each extension directory must contain:
      - index.ts          (required) - Main extension entry point

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
            # Dry-run mode removed - all actions are executed directly
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
                EXTENSION_NAMES+=("$1")
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
    if [[ "$LIST_MODE" == false && "$INTERACTIVE_MODE" == false && "$INSTALL_ALL" == false && ${#EXTENSION_NAMES[@]} -eq 0 ]]; then
        print_error "No action specified. Use --all, --list, --interactive, or provide extension name(s)."
        echo ""
        usage
        exit 1
    fi
}

resolve_install_base() {
    if [[ -n "$TARGET_DIR" ]]; then
        INSTALL_BASE="$TARGET_DIR/.pi/agent/extensions"
    else
        INSTALL_BASE="$HOME/.pi/agent/extensions"
    fi
}

################################################################################
# Extension Discovery
################################################################################

get_available_extensions() {
    local extensions=()

    if [[ ! -d "$EXTENSIONS_DIR" ]]; then
        print_error "Extensions directory not found: $EXTENSIONS_DIR"
        exit 1
    fi

    for ext_path in "$EXTENSIONS_DIR"/*/; do
        if [[ -f "${ext_path}index.ts" || -f "${ext_path}auth.js" ]]; then
            extensions+=("$(basename "$ext_path")")
        fi
    done

    printf '%s\n' "${extensions[@]}"
}

get_extension_description() {
    local ext_name="$1"
    local readme="$EXTENSIONS_DIR/$ext_name/README.md"
    local description=""

    if [[ -f "$readme" ]]; then
        # Try to get first non-empty, non-heading line as description
        description=$(grep -v '^#' "$readme" | grep -v '^[[:space:]]*$' | head -1 | cut -c1-60)
    fi

    echo "${description:-No description available}"
}

################################################################################
# List Extensions
################################################################################

list_extensions() {
    print_header "Available Pi Extensions"
    echo ""

    local extensions_arr=()
    while IFS= read -r ext; do
        extensions_arr+=("$ext")
    done < <(get_available_extensions)
    local count=${#extensions_arr[@]}

    if [[ $count -eq 0 ]]; then
        print_warning "No extensions found in $EXTENSIONS_DIR"
        exit 1
    fi

    printf "%-35s %-20s %s\n" "EXTENSION NAME" "STATUS" "DESCRIPTION"
    echo "--------------------------------------------------------------------"

    for ext_name in "${extensions_arr[@]}"; do
        local installed=""
        local target="$INSTALL_BASE/$ext_name"
        
        if [[ -L "$target" ]]; then
            local link_target
            link_target=$(readlink "$target")
            installed=" ${GREEN}[symlink]${NC} -> $link_target"
        elif [[ -d "$target" ]]; then
            installed=" ${YELLOW}[installed]${NC}"
        fi

        local desc
        desc=$(get_extension_description "$ext_name")

        printf "%-35s %-20s " "$ext_name" "$installed"
        echo -e "${desc}"
    done

    echo ""
    echo "Total extensions available: $count"
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

validate_extension() {
    local ext_name="$1"
    local ext_path="$EXTENSIONS_DIR/$ext_name"

    if [[ ! -d "$ext_path" ]]; then
        print_error "Extension directory not found: $ext_path"
        return 1
    fi

    return 0
}

install_single_extension() {
    local ext_name="$1"
    local source_path="$EXTENSIONS_DIR/$ext_name"
    local target_path="$INSTALL_BASE/$ext_name"

    # Validate
    if ! validate_extension "$ext_name"; then
        return 1
    fi

    # Handle existing installation
    if [[ -L "$target_path" ]]; then
        local current_target
        current_target=$(readlink "$target_path")
        if [[ "$current_target" == "$source_path" ]]; then
            print_success "Already installed (symlink correct): $ext_name -> $target_path"
            return 0
        fi
        print_warning "Existing symlink points elsewhere: $target_path -> $current_target"
        rm -f "$target_path"
    elif [[ -d "$target_path" ]]; then
        print_warning "Existing directory (not a symlink): $target_path"
        rm -rf "$target_path"
    fi

    ln -s "$source_path" "$target_path"
    print_success "Installed (symlink): $ext_name -> $target_path"

    return 0
}

install_extensions() {
    local extensions=("$@")
    local success_count=0
    local fail_count=0

    create_install_dir "$INSTALL_BASE"

    for ext in "${extensions[@]}"; do
        echo ""
        print_info "Processing: $ext"
        if install_single_extension "$ext"; then
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
    print_header "Pi Extension Installation Wizard"
    echo ""

    # Step 1: Target directory
    echo -e "${BLUE}Step 1: Select target directory${NC}"
    echo ""
    echo "  Extensions will be installed into <target-dir>/.pi/agent/extensions/"
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

    local all_extensions_arr=()
    while IFS= read -r ext; do
        all_extensions_arr+=("$ext")
    done < <(get_available_extensions)

    if [[ ${#all_extensions_arr[@]} -eq 0 ]]; then
        print_warning "No extensions found in $EXTENSIONS_DIR"
        exit 1
    fi

    # Step 2: Installation type (always symlink)
    echo -e "${BLUE}Step 2: Installation method${NC}"
    echo ""
    echo "  All extensions are installed using symbolic links:"
    echo ""
    echo "  - Symlink installation"
    echo "    - Creates symbolic link to source directory"
    echo "    - Changes in source are reflected immediately"
    echo "    - Recommended for development and testing"
    echo ""

    # Step 3: Select extensions
    echo -e "${BLUE}Step 3: Select extensions to install${NC}"
    echo ""

    local i=1
    declare -A ext_map=()

    for ext in "${all_extensions_arr[@]}"; do
        local installed=""
        local target="$INSTALL_BASE/$ext"
        
        if [[ -L "$target" ]]; then
            local link_target
            link_target=$(readlink "$target")
            installed=" ${GREEN}[symlink installed]${NC}"
        elif [[ -d "$target" ]]; then
            installed=" ${YELLOW}[installed]${NC}"
        fi

        printf "  %2d) %s" "$i" "$ext"
        echo -e "${installed}"
        ext_map["$i"]="$ext"
        ((i++))
    done

    echo ""
    echo "  a) Install ALL extensions"
    echo "  q) Quit"
    echo ""

    read -r -p "Enter choice(s) - number(s) comma-separated, 'a' for all, 'q' to quit: [a] " selection
    selection=${selection:-a}

    local selected_extensions=()

    if [[ "$selection" == "q" ]]; then
        print_warning "Installation cancelled"
        exit 0
    elif [[ "$selection" == "a" ]]; then
        selected_extensions=("${all_extensions_arr[@]}")
        print_success "Selected all ${#all_extensions_arr[@]} extensions"
    else
        IFS=',' read -ra indices <<< "$selection"
        for idx in "${indices[@]}"; do
            idx=$(echo "$idx" | tr -d ' ')
            if [[ -n "${ext_map[$idx]}" ]]; then
                selected_extensions+=("${ext_map[$idx]}")
                print_success "Selected: ${ext_map[$idx]}"
            else
                print_warning "Invalid number: $idx"
            fi
        done

        if [[ ${#selected_extensions[@]} -eq 0 ]]; then
            print_error "No valid extensions selected"
            exit 1
        fi
    fi

    # Step 3: Confirm
    echo ""
    print_header "Installation Plan"
    echo ""
    echo "  Target:  $INSTALL_BASE"
    echo "  Method:  Symlink (all extensions)"
    echo ""
    echo "  Extensions (${#selected_extensions[@]}):"
    for ext in "${selected_extensions[@]}"; do
        local source_path="$EXTENSIONS_DIR/$ext"
        echo "    - $ext  -> ~/.pi/agent/extensions/$ext"
    done
    echo ""

    read -r -p "Proceed with installation? [y/N] " confirm || confirm=""
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_warning "Installation cancelled"
        exit 0
    fi

    echo ""
    install_extensions "${selected_extensions[@]}"

    post_install_info
}

################################################################################
# Post-install Info
################################################################################

post_install_info() {
    echo ""
    print_header "Post-Installation Notes"
    echo ""
    echo -e "  Extensions installed to: ${GREEN}$INSTALL_BASE${NC}"
    echo ""
    echo "  To activate extensions in pi, ensure your pi configuration"
    echo "  loads extensions from: ~/.pi/agent/extensions/"
    echo ""
    echo "  Installed extensions:"
    for d in "$INSTALL_BASE"/*/; do
        d="${d%/}"
        if [[ -d "$d" ]]; then
            local name
            name=$(basename "$d")
            if [[ -L "$d" ]]; then
                echo -e "    ${GREEN}✓${NC} $name  ${BLUE}(symlink -> $(readlink "$d"))${NC}"
            else
                echo -e "    ${GREEN}✓${NC} $name  ${BLUE}(copy)${NC}"
            fi
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
        list_extensions
        exit 0
    fi

    if [[ "$INTERACTIVE_MODE" == true ]]; then
        interactive_installation
        exit $?
    fi

    # Determine extensions to install
    local to_install_arr=()

    if [[ "$INSTALL_ALL" == true ]]; then
        while IFS= read -r ext; do
            to_install_arr+=("$ext")
        done < <(get_available_extensions)
        if [[ ${#to_install_arr[@]} -eq 0 ]]; then
            print_error "No extensions found in $EXTENSIONS_DIR"
            exit 1
        fi
    else
        to_install_arr=("${EXTENSION_NAMES[@]}")
    fi

    # Validate all named extensions up front
    local valid=true
    for ext in "${to_install_arr[@]}"; do
        if ! validate_extension "$ext"; then
            valid=false
        fi
    done
    [[ "$valid" == false ]] && exit 1

    # Print plan
    print_header "Installing Pi Extensions"
    echo ""
    echo "  Target: $INSTALL_BASE"
    echo "  Method: Symlink (all extensions)"
    echo "  Count:  ${#to_install_arr[@]}"

    if [[ "$FORCE_MODE" != true ]]; then
        echo ""
        read -r -p "Proceed with installation? [y/N] " confirm || confirm=""
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            print_warning "Installation cancelled"
            exit 0
        fi
    fi

    install_extensions "${to_install_arr[@]}"

    echo ""
    print_success "Done!"
    post_install_info
}

main "$@"
