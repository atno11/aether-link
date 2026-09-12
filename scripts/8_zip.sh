#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

ARCHIVE_DIR="$WORKSPACE_DIR/dist/archives"

if [[ -z "${NO_COLOR:-}" ]]; then
    RESET=$'\033[0m'
    BOLD=$'\033[1m'
    RED=$'\033[31m'
    GREEN=$'\033[32m'
    YELLOW=$'\033[33m'
    CYAN=$'\033[36m'
    GRAY=$'\033[90m'
else
    RESET=""
    BOLD=""
    RED=""
    GREEN=""
    YELLOW=""
    CYAN=""
    GRAY=""
fi

cd "$WORKSPACE_DIR"

clear_screen() {
    if command -v clear >/dev/null 2>&1; then
        clear
    else
        printf '\033[2J\033[H'
    fi
}

print_success() {
    printf '%b\n' "${BOLD}${GREEN}[OK]${RESET} ${GREEN}$1${RESET}"
}

print_warning() {
    printf '%b\n' "${BOLD}${YELLOW}[WARN]${RESET} ${YELLOW}$1${RESET}"
}

print_error() {
    printf '%b\n' "${BOLD}${RED}[ERROR]${RESET} ${RED}$1${RESET}"
}

print_info() {
    printf '%b\n' "${GRAY}$1${RESET}"
}

format_size() {
    local file="$1"

    if command -v numfmt >/dev/null 2>&1; then
        numfmt \
            --to=iec-i \
            --suffix=B \
            "$(stat -c '%s' "$file")"
    else
        printf '%s bytes\n' "$(stat -c '%s' "$file")"
    fi
}

archive_name() {
    local suffix="$1"
    local timestamp

    timestamp="$(date '+%Y%m%d-%H%M%S')"

    printf '%s/aether-%s-%s.zip\n' \
        "$ARCHIVE_DIR" \
        "$suffix" \
        "$timestamp"
}

create_archive() {
    local label="$1"
    local suffix="$2"
    shift 2

    local paths=("$@")
    local archive

    archive="$(archive_name "$suffix")"

    mkdir -p "$ARCHIVE_DIR"

    clear_screen

    echo
    printf '%b\n' "${BOLD}${CYAN}╭─────────────────────────────────────────────╮${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│                CREATE ZIP                   │${RESET}"
    printf '%b\n' "${BOLD}${CYAN}╰─────────────────────────────────────────────╯${RESET}"
    echo

    print_info "Content:"
    printf '  %b%s%b\n' "$YELLOW" "$label" "$RESET"

    echo
    print_info "Output:"
    printf '  %b%s%b\n' \
        "$YELLOW" \
        "${archive#"$WORKSPACE_DIR"/}" \
        "$RESET"

    echo
    print_info "Creating archive..."
    echo

    if zip \
        -r \
        "$archive" \
        "${paths[@]}" \
        -x \
        '*/target/*' \
        '*/.git/*' \
        '*/.idea/*' \
        '*/.vscode/*' \
        '*/node_modules/*' \
        '*/__pycache__/*' \
        '*/.DS_Store' \
        '*.zip'; then

        echo

        local size
        size="$(format_size "$archive")"

        print_success "Archive created successfully."

        echo
        print_info "Archive:"
        printf '  %b%s%b\n' \
            "$YELLOW" \
            "${archive#"$WORKSPACE_DIR"/}" \
            "$RESET"

        echo
        print_info "Size:"
        printf '  %b%s%b\n' "$YELLOW" "$size" "$RESET"

        return 0
    fi

    local status=$?

    echo
    print_error "Failed to create archive with status $status."

    rm -f "$archive"

    return "$status"
}

show_menu() {
    printf '%b\n' "${BOLD}${CYAN}╭─────────────────────────────────────────────╮${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│                ZIP SOURCE                   │${RESET}"
    printf '%b\n' "${BOLD}${CYAN}├─────────────────────────────────────────────┤${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│                                             │${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│  ${RESET}${BOLD}1)${RESET} Apps                                    ${BOLD}${CYAN}│${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│  ${RESET}${BOLD}2)${RESET} Crates                                  ${BOLD}${CYAN}│${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│  ${RESET}${BOLD}3)${RESET} Apps + Crates                           ${BOLD}${CYAN}│${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│                                             │${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│  ${RESET}${BOLD}0)${RESET} Back                                    ${BOLD}${CYAN}│${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│                                             │${RESET}"
    printf '%b\n' "${BOLD}${CYAN}╰─────────────────────────────────────────────╯${RESET}"
}

if ! command -v zip >/dev/null 2>&1; then
    print_error "zip was not found in PATH."

    echo
    print_info "Install it with:"
    echo

    printf '  %bsudo pacman -S zip%b\n' \
        "$YELLOW" \
        "$RESET"

    exit 1
fi

if [[ ! -f "$WORKSPACE_DIR/Cargo.toml" ]]; then
    print_error "Cargo.toml was not found at:"

    echo
    printf '  %b%s%b\n' \
        "$YELLOW" \
        "$WORKSPACE_DIR" \
        "$RESET"

    exit 1
fi

if [[ ! -d "$WORKSPACE_DIR/apps" ]]; then
    print_error "apps/ directory was not found."

    exit 1
fi

if [[ ! -d "$WORKSPACE_DIR/crates" ]]; then
    print_error "crates/ directory was not found."

    exit 1
fi

while true; do
    clear_screen
    show_menu

    echo
    read -r -p "Select an option: " option

    case "$option" in
        0)
            exit 0
            ;;

        1)
            set +e
            create_archive \
                "apps/" \
                "apps" \
                "apps"
            set -e

            echo
            read -r -p "Press Enter to continue..."
            ;;

        2)
            set +e
            create_archive \
                "crates/" \
                "crates" \
                "crates"
            set -e

            echo
            read -r -p "Press Enter to continue..."
            ;;

        3)
            set +e
            create_archive \
                "apps/ + crates/" \
                "source" \
                "apps" \
                "crates"
            set -e

            echo
            read -r -p "Press Enter to continue..."
            ;;

        *)
            echo
            print_warning "Invalid option: $option"

            sleep 1
            ;;
    esac
done
