#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

WINDOWS_TARGET="x86_64-pc-windows-gnu"
LINUX_TARGET="x86_64-unknown-linux-gnu"

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

target_installed() {
    local target="$1"

    rustup target list --installed | grep -Fxq "$target"
}

require_target() {
    local target="$1"

    if target_installed "$target"; then
        return 0
    fi

    print_error "Rust target is not installed:"
    echo
    printf '  %b%s%b\n' "$YELLOW" "$target" "$RESET"
    echo
    print_info "Install it with:"
    echo
    printf '  %brustup target add %s%b\n' \
        "$YELLOW" \
        "$target" \
        "$RESET"

    return 1
}

show_menu() {
    printf '%b\n' "${BOLD}${CYAN}╭─────────────────────────────────────────────╮${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│                   BUILD                     │${RESET}"
    printf '%b\n' "${BOLD}${CYAN}├─────────────────────────────────────────────┤${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│                                             │${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│  ${RESET}${BOLD}1)${RESET} Windows                                 ${BOLD}${CYAN}│${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│  ${RESET}${BOLD}2)${RESET} Linux                                   ${BOLD}${CYAN}│${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│  ${RESET}${BOLD}0)${RESET} Back                                    ${BOLD}${CYAN}│${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│                                             │${RESET}"
    printf '%b\n' "${BOLD}${CYAN}╰─────────────────────────────────────────────╯${RESET}"
}

run_build() {
    local name="$1"
    local target="$2"

    : > "$OUTPUT_FILE"

    clear_screen

    {
        echo
        printf '%b\n' "${BOLD}${CYAN}╭─────────────────────────────────────────────╮${RESET}"
        printf '│  %b%-43s%b│\n' \
            "${BOLD}${CYAN}" \
            "BUILD — $name" \
            "${RESET}"
        printf '%b\n' "${BOLD}${CYAN}╰─────────────────────────────────────────────╯${RESET}"
        echo

        print_info "Target:"
        echo
        printf '  %b%s%b\n' "$YELLOW" "$target" "$RESET"
        echo

        if ! require_target "$target"; then
            return 1
        fi

        print_info "Building workspace in release mode..."
        echo

        cargo build \
            --workspace \
            --release \
            --target "$target"

        local status=$?

        echo

        if [[ $status -eq 0 ]]; then
            print_success "Build completed successfully."
            echo
            print_info "Artifacts:"
            echo
            printf '  %btarget/%s/release/%b\n' \
                "$YELLOW" \
                "$target" \
                "$RESET"
        else
            print_error "Build failed with status $status."
        fi

        return "$status"
    } 2>&1 | tee "$OUTPUT_FILE"

    local build_status=${PIPESTATUS[0]}

    copy_to_clipboard || true

    return "$build_status"
}

if ! command -v cargo >/dev/null 2>&1; then
    print_error "cargo was not found in PATH."
    exit 1
fi

if ! command -v rustup >/dev/null 2>&1; then
    print_error "rustup was not found in PATH."
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
            run_build "WINDOWS" "$WINDOWS_TARGET"
            build_status=$?
            set -e

            exit "$build_status"
            ;;

        2)
            set +e
            run_build "LINUX" "$LINUX_TARGET"
            build_status=$?
            set -e

            exit "$build_status"
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
