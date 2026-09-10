#!/usr/bin/env bash

set -Euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"

cd "$ROOT_DIR"

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

# Prevent Ctrl+C from closing the main menu.
# Child scripts still receive SIGINT normally.
trap ':' INT

clear_screen() {
    if command -v clear >/dev/null 2>&1; then
        clear
    else
        printf '\033[2J\033[H'
    fi
}

print_warning() {
    printf '%b\n' "${BOLD}${YELLOW}[WARN]${RESET} ${YELLOW}$1${RESET}"
}

print_error() {
    printf '%b\n' "${BOLD}${RED}[ERROR]${RESET} ${RED}$1${RESET}"
}

pause_menu() {
    echo
    read -r -p "Press Enter to return to the menu..." _
}

run_script() {
    local script_name="$1"
    shift

    local pause_after=1

    if [[ "${1:-}" == "--no-pause" ]]; then
        pause_after=0
        shift
    fi

    local script_path="$SCRIPTS_DIR/$script_name"
    local status

    clear_screen

    if [[ ! -f "$script_path" ]]; then
        print_error "Script was not found:"
        echo
        printf '  %b%s%b\n' "$YELLOW" "$script_path" "$RESET"
        pause_menu
        return
    fi

    if bash "$script_path" "$@"; then
        status=0
    else
        status=$?
    fi

    # Ctrl+C in a child script returns directly to the main menu.
    if [[ $status -eq 130 ]]; then
        return
    fi

    if [[ $status -ne 0 ]]; then
        echo
        print_error "Script exited with status $status."
    fi

    if [[ $pause_after -eq 1 ]]; then
        pause_menu
    fi
}

show_menu() {
    printf '%b\n' "${BOLD}${CYAN}╭─────────────────────────────────────────────╮${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│                  AETHER                     │${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│                  SCRIPTS                    │${RESET}"
    printf '%b\n' "${BOLD}${CYAN}├─────────────────────────────────────────────┤${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│                                             │${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│  ${RESET}${BOLD}1)${RESET} Format Workspace                        ${BOLD}${CYAN}│${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│  ${RESET}${BOLD}2)${RESET} Check Targets                           ${BOLD}${CYAN}│${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│  ${RESET}${BOLD}3)${RESET} Clippy                                  ${BOLD}${CYAN}│${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│  ${RESET}${BOLD}4)${RESET} Tests                                   ${BOLD}${CYAN}│${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│  ${RESET}${BOLD}5)${RESET} Run                                     ${BOLD}${CYAN}│${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│  ${RESET}${BOLD}6)${RESET} Build                                   ${BOLD}${CYAN}│${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│  ${RESET}${BOLD}7)${RESET} Examples                                ${BOLD}${CYAN}│${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│  ${RESET}${BOLD}0)${RESET} Exit                                    ${BOLD}${CYAN}│${RESET}"
    printf '%b\n' "${BOLD}${CYAN}│                                             │${RESET}"
    printf '%b\n' "${BOLD}${CYAN}╰─────────────────────────────────────────────╯${RESET}"
}

while true; do
    clear_screen
    show_menu

    echo
    read -r -p "Select an option: " option

    case "$option" in
        1)
            run_script "1_format_workspace.sh"
            ;;

        2)
            run_script "2_check_targets.sh"
            ;;

        3)
            run_script "3_clippy.sh"
            ;;

        4)
            run_script "4_tests.sh"
            ;;

        5)
            run_script "5_run.sh" --no-pause
            ;;

        6)
            run_script "6_build.sh" --no-pause
            ;;

        7)
            run_script "7_examples.sh" --no-pause
            ;;

        0)
            clear_screen
            exit 0
            ;;

        *)
            echo
            print_warning "Invalid option: $option"
            sleep 1
            ;;
    esac
done
