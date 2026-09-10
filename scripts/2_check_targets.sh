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

run_check() {
    echo
    printf '%b\n' "${BOLD}${CYAN}╭─────────────────────────────────────────────╮${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│                CHECK TARGETS                │${RESET}"
    printf '%b\n' "${BOLD}${CYAN}╰─────────────────────────────────────────────╯${RESET}"
    echo

    if ! command -v cargo >/dev/null 2>&1; then
        print_error "cargo was not found in PATH."
        return 1
    fi

    if [[ ! -f "Cargo.toml" ]]; then
        print_error "Cargo.toml was not found at:"
        echo
        printf '  %b%s%b\n' "$YELLOW" "$WORKSPACE_DIR" "$RESET"
        return 1
    fi

    print_info "Checking all workspace targets..."
    echo

    if cargo check --workspace --all-targets; then
        echo
        print_success "All workspace targets checked successfully."
        return 0
    else
        local status=$?

        echo
        print_error "Workspace target check failed."
        return "$status"
    fi
}

set +e

run_check 2>&1 | tee "$OUTPUT_FILE"
check_status=${PIPESTATUS[0]}

set -e

copy_to_clipboard || true

exit "$check_status"
