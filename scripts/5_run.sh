#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

OUTPUT_FILE="$(mktemp)"
CLEAN_OUTPUT_FILE="$(mktemp)"

MIN_BOX_WIDTH=47
MAX_BOX_WIDTH=100

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

terminal_width() {
    local width=""

    if command -v tput >/dev/null 2>&1; then
        width="$(tput cols 2>/dev/null || true)"
    fi

    if [[ ! "$width" =~ ^[0-9]+$ ]]; then
        width=80
    fi

    printf '%d\n' "$width"
}

box_width() {
    local terminal
    local width

    terminal="$(terminal_width)"

    width=$((terminal - 4))

    if (( width < MIN_BOX_WIDTH )); then
        width="$MIN_BOX_WIDTH"
    fi

    if (( width > MAX_BOX_WIDTH )); then
        width="$MAX_BOX_WIDTH"
    fi

    printf '%d\n' "$width"
}

repeat_char() {
    local char="$1"
    local count="$2"
    local i

    for ((i = 0; i < count; i++)); do
        printf '%s' "$char"
    done
}

print_box_top() {
    local width="$1"

    printf '%b╭' "${BOLD}${CYAN}"
    repeat_char '─' "$((width - 2))"
    printf '╮%b\n' "$RESET"
}

print_box_separator() {
    local width="$1"

    printf '%b├' "${BOLD}${CYAN}"
    repeat_char '─' "$((width - 2))"
    printf '┤%b\n' "$RESET"
}

print_box_bottom() {
    local width="$1"

    printf '%b╰' "${BOLD}${CYAN}"
    repeat_char '─' "$((width - 2))"
    printf '╯%b\n' "$RESET"
}

print_box_empty() {
    local width="$1"

    printf '%b│%b' "${BOLD}${CYAN}" "$RESET"
    printf '%*s' "$((width - 2))" ''
    printf '%b│%b\n' "${BOLD}${CYAN}" "$RESET"
}

print_box_title() {
    local width="$1"
    local title="$2"

    local inner_width
    local title_length
    local left_padding
    local right_padding

    inner_width=$((width - 2))
    title_length=${#title}

    left_padding=$(((inner_width - title_length) / 2))
    right_padding=$((inner_width - title_length - left_padding))

    printf '%b│%b' "${BOLD}${CYAN}" "$RESET"

    printf '%*s' "$left_padding" ''

    printf '%b%s%b' \
        "$BOLD" \
        "$title" \
        "$RESET"

    printf '%*s' "$right_padding" ''

    printf '%b│%b\n' "${BOLD}${CYAN}" "$RESET"
}

print_box_option() {
    local width="$1"
    local key="$2"
    local label="$3"

    local inner_width
    local visible_length
    local right_padding

    inner_width=$((width - 2))

    visible_length=$((2 + ${#key} + 2 + ${#label}))
    right_padding=$((inner_width - visible_length))

    if (( right_padding < 0 )); then
        right_padding=0
    fi

    printf '%b│%b' "${BOLD}${CYAN}" "$RESET"

    printf '  %b%s)%b %s' \
        "$BOLD" \
        "$key" \
        "$RESET" \
        "$label"

    printf '%*s' "$right_padding" ''

    printf '%b│%b\n' "${BOLD}${CYAN}" "$RESET"
}

print_banner() {
    local title="$1"
    local width

    width="$(box_width)"

    print_box_top "$width"
    print_box_title "$width" "$title"
    print_box_bottom "$width"
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

        printf '  %bsudo pacman -S xclip%b\n' \
            "$YELLOW" \
            "$RESET"

        return 1
    fi

    xclip -selection clipboard < "$CLEAN_OUTPUT_FILE"

    echo

    print_success "Output copied to clipboard."
}

show_menu() {
    local width

    width="$(box_width)"

    print_box_top "$width"
    print_box_title "$width" "RUN"
    print_box_separator "$width"

    print_box_empty "$width"

    print_box_option "$width" "1" "Aether Host"
    print_box_option "$width" "2" "Aether Client"

    print_box_empty "$width"

    print_box_option "$width" "0" "Back"

    print_box_empty "$width"

    print_box_bottom "$width"
}

run_app() {
    local name="$1"
    local manifest="$2"

    shift 2

    local app_args=("$@")

    : > "$OUTPUT_FILE"

    clear_screen

    {
        echo

        print_banner "RUN — $name"

        echo

        print_info "Manifest:"

        echo

        printf '  %b%s%b\n' \
            "$YELLOW" \
            "$manifest" \
            "$RESET"

        if (( ${#app_args[@]} > 0 )); then
            echo

            print_info "Arguments:"

            echo

            printf '  %b' "$YELLOW"
            printf '%q ' "${app_args[@]}"
            printf '%b\n' "$RESET"
        fi

        echo

        print_info "Starting $name..."

        echo

        if (( ${#app_args[@]} > 0 )); then
            cargo run \
                --manifest-path "$manifest" \
                -- \
                "${app_args[@]}"
        else
            cargo run \
                --manifest-path "$manifest"
        fi

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

    printf '  %b%s%b\n' \
        "$YELLOW" \
        "$WORKSPACE_DIR" \
        "$RESET"

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
