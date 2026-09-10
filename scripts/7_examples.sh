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

discover_examples() {
    mapfile -t EXAMPLES < <(
        cargo metadata \
            --no-deps \
            --format-version 1 |
            python3 -c '
import json
import sys

metadata = json.load(sys.stdin)
workspace_members = set(metadata["workspace_members"])

for package in metadata["packages"]:
    if package["id"] not in workspace_members:
        continue

    manifest = package["manifest_path"]
    package_name = package["name"]

    for target in package["targets"]:
        if "example" in target["kind"]:
            print(
                f"{package_name}\t"
                f"{target['name']}\t"
                f"{manifest}"
            )
'
    )
}

show_menu() {
    printf '%b\n' "${BOLD}${CYAN}╭─────────────────────────────────────────────╮${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│                  EXAMPLES                   │${RESET}"
    printf '%b\n' "${BOLD}${CYAN}├─────────────────────────────────────────────┤${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│                                             │${RESET}"

    for i in "${!EXAMPLES[@]}"; do
        IFS=$'\t' read -r package example manifest <<< "${EXAMPLES[$i]}"

        label="$package / $example"

        printf '│  %b%2d)%b %-38s%b│%b\n' \
            "$BOLD" \
            "$((i + 1))" \
            "$RESET" \
            "$label" \
            "${BOLD}${CYAN}" \
            "$RESET"
    done

    printf '%b\n' "${BOLD}${CYAN}│                                             │${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│  ${RESET}${BOLD}A)${RESET} Run All                                 ${BOLD}${CYAN}│${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│  ${RESET}${BOLD}0)${RESET} Back                                    ${BOLD}${CYAN}│${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│                                             │${RESET}"
    printf '%b\n' "${BOLD}${CYAN}╰─────────────────────────────────────────────╯${RESET}"
}

run_example() {
    local entry="$1"

    IFS=$'\t' read -r package example manifest <<< "$entry"

    local relative_manifest="${manifest#"$WORKSPACE_DIR"/}"

    : > "$OUTPUT_FILE"

    clear_screen

    {
        echo
        printf '%b\n' "${BOLD}${CYAN}╭─────────────────────────────────────────────╮${RESET}"
        printf '%b\n' "${BOLD}${CYAN}│                RUN EXAMPLE                  │${RESET}"
        printf '%b\n' "${BOLD}${CYAN}╰─────────────────────────────────────────────╯${RESET}"
        echo

        print_info "Package:"
        printf '  %b%s%b\n' "$YELLOW" "$package" "$RESET"

        echo
        print_info "Example:"
        printf '  %b%s%b\n' "$YELLOW" "$example" "$RESET"

        echo
        print_info "Manifest:"
        printf '  %b%s%b\n' "$YELLOW" "$relative_manifest" "$RESET"

        echo
        print_info "Running example..."
        echo

        cargo run \
            --manifest-path "$manifest" \
            --example "$example"

        local status=$?

        echo

        if [[ $status -eq 0 ]]; then
            print_success "Example completed successfully."
        else
            print_error "Example failed with status $status."
        fi

        return "$status"
    } 2>&1 | tee "$OUTPUT_FILE"

    local run_status=${PIPESTATUS[0]}

    copy_to_clipboard || true

    echo
    read -r -p "Press Enter to continue..."

    return "$run_status"
}

run_all_examples() {
    local failed=0

    : > "$OUTPUT_FILE"

    clear_screen

    {
        echo
        printf '%b\n' "${BOLD}${CYAN}╭─────────────────────────────────────────────╮${RESET}"
        printf '%b\n' "${BOLD}${CYAN}│              RUN ALL EXAMPLES               │${RESET}"
        printf '%b\n' "${BOLD}${CYAN}╰─────────────────────────────────────────────╯${RESET}"
        echo

        for entry in "${EXAMPLES[@]}"; do
            IFS=$'\t' read -r package example manifest <<< "$entry"

            printf '%b\n' "${CYAN}───────────────────────────────────────────────${RESET}"
            echo
            print_info "Running:"
            printf '  %b%s / %s%b\n' \
                "$YELLOW" \
                "$package" \
                "$example" \
                "$RESET"
            echo

            if cargo run \
                --manifest-path "$manifest" \
                --example "$example"; then

                echo
                print_success "$package / $example"
            else
                local status=$?

                echo
                print_error "$package / $example failed with status $status."
                failed=1
            fi

            echo
        done

        printf '%b\n' "${CYAN}───────────────────────────────────────────────${RESET}"
        echo

        if [[ $failed -eq 0 ]]; then
            print_success "All examples completed successfully."
        else
            print_error "One or more examples failed."
        fi

        return "$failed"
    } 2>&1 | tee "$OUTPUT_FILE"

    local run_status=${PIPESTATUS[0]}

    copy_to_clipboard || true

    echo
    read -r -p "Press Enter to continue..."

    return "$run_status"
}

if ! command -v cargo >/dev/null 2>&1; then
    print_error "cargo was not found in PATH."
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    print_error "python3 was not found in PATH."
    exit 1
fi

if [[ ! -f "Cargo.toml" ]]; then
    print_error "Cargo.toml was not found at:"
    echo
    printf '  %b%s%b\n' "$YELLOW" "$WORKSPACE_DIR" "$RESET"
    exit 1
fi

discover_examples

if [[ ${#EXAMPLES[@]} -eq 0 ]]; then
    clear_screen
    echo
    print_warning "No examples found in the workspace."
    echo
    read -r -p "Press Enter to continue..."
    exit 0
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

        a|A)
            set +e
            run_all_examples
            set -e
            ;;

        *)
            if [[ "$option" =~ ^[0-9]+$ ]] &&
               (( option >= 1 && option <= ${#EXAMPLES[@]} )); then

                set +e
                run_example "${EXAMPLES[$((option - 1))]}"
                set -e
            else
                echo
                print_warning "Invalid option: $option"
                sleep 1
            fi
            ;;
    esac
done

