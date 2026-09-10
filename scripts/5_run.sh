#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

OUTPUT_FILE="$(mktemp)"
CLEAN_OUTPUT_FILE="$(mktemp)"

if [[ -z "${NO_COLOR:-}" ]]; then
    RESET=$'\033[0m'
    BOLD=$'\033[1m'
    RED=$'\033[31m'
    GREEN=$'\033[32m'
    YELLOW=$'\033[33m'
    CYAN=$'\033[36m'
    GRAY=$'\033[90m'

    export CARGO_TERM_COLOR=always
else
    RESET=""
    BOLD=""
    RED=""
    GREEN=""
    YELLOW=""
    CYAN=""
    GRAY=""

    export CARGO_TERM_COLOR=never
fi

cleanup() {
    rm -f "$OUTPUT_FILE"
    rm -f "$CLEAN_OUTPUT_FILE"
}

trap cleanup EXIT

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

strip_ansi() {
    sed -E $'s/\x1B\\[[0-9;]*[[:alpha:]]//g'
}

copy_to_clipboard() {
    strip_ansi < "$OUTPUT_FILE" > "$CLEAN_OUTPUT_FILE"

    if ! command -v xclip >/dev/null 2>&1; then
        echo
        print_warning "xclip was not found in PATH."
        echo
        print_info "Install it with:"
        echo
        printf '  %bsudo pacman -S xclip%b\n' "$YELLOW" "$RESET"
        return 1
    fi

    xclip -selection clipboard < "$CLEAN_OUTPUT_FILE"

    echo
    print_success "Output copied to clipboard."
}

show_menu() {
    printf '%b\n' "${BOLD}${CYAN}╭─────────────────────────────────────────────╮${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│                    RUN                      │${RESET}"
    printf '%b\n' "${BOLD}${CYAN}├─────────────────────────────────────────────┤${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│                                             │${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│  ${RESET}${BOLD}1)${RESET} Aether Host                             ${BOLD}${CYAN}│${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│  ${RESET}${BOLD}2)${RESET} Aether Client                           ${BOLD}${CYAN}│${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│  ${RESET}${BOLD}0)${RESET} Back                                    ${BOLD}${CYAN}│${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│                                             │${RESET}"
    printf '%b\n' "${BOLD}${CYAN}╰─────────────────────────────────────────────╯${RESET}"
}

run_app() {
    local name="$1"
    local manifest="$2"

    : > "$OUTPUT_FILE"

    clear_screen

    {
        echo
        printf '%b\n' "${BOLD}${CYAN}╭─────────────────────────────────────────────╮${RESET}"
        printf '│  %b%-43s%b│\n' \
            "${BOLD}${CYAN}" \
            "RUN — $name" \
            "${RESET}"
        printf '%b\n' "${BOLD}${CYAN}╰─────────────────────────────────────────────╯${RESET}"
        echo

        print_info "Manifest:"
        echo
        printf '  %b%s%b\n' "$YELLOW" "$manifest" "$RESET"
        echo

        print_info "Starting $name..."
        echo

        cargo run \
            --manifest-path "$manifest" \
            -- "$@"

        local status=$?

        echo

        if [[ $status -eq 0 ]]; then
            print_success "$name exited successfully."
        else
            print_error "$name exited with status $status."
        fi

        return "$status"
    } 2>&1 | tee "$OUTPUT_FILE"

    local run_status=${PIPESTATUS[0]}

    copy_to_clipboard || true

    return "$run_status"
}

if ! command -v cargo >/dev/null 2>&1; then
    print_error "cargo was not found in PATH."
    exit 1
fi

if [[ ! -f "Cargo.toml" ]]; then
    print_error "Cargo.toml was not found at:"
    echo
    printf '  %b%s%b\n' "$YELLOW" "$WORKSPACE_DIR" "$RESET"
    exit 1
fi

while true; do
    clear_screen
    show_menu

    echo
    read -r -p "Select an option: " option

    case "$option" in
        1)
            set +e

            run_app \
                "AETHER HOST" \
                "apps/aether-host/Cargo.toml" \
                "$@"

            run_status=$?

            set -e

            exit "$run_status"
            ;;

        2)
            set +e

            run_app \
                "AETHER CLIENT" \
                "apps/aether-client/Cargo.toml" \
                "$@"

            run_status=$?

            set -e

            exit "$run_status"
            ;;

        0)
            exit 0
            ;;

        *)
            echo
            print_warning "Invalid option: $option"
            sleep 1
            ;;
    esac
done
