#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

OUTPUT_FILE="$(mktemp)"
CLEAN_OUTPUT_FILE="$(mktemp)"
METADATA_FILE="$(mktemp)"
EXAMPLES_FILE="$(mktemp)"
ARGS_FILE="$(mktemp)"

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
    rm -f "$METADATA_FILE"
    rm -f "$EXAMPLES_FILE"
    rm -f "$ARGS_FILE"
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
    local max_label_width
    local visible_length
    local right_padding

    inner_width=$((width - 2))

    # 2 spaces + 2-char key + ") " = 6 visible characters.
    max_label_width=$((inner_width - 6))

    if (( max_label_width < 1 )); then
        max_label_width=1
    fi

    if (( ${#label} > max_label_width )); then
        if (( max_label_width > 3 )); then
            label="${label:0:$((max_label_width - 3))}..."
        else
            label="${label:0:$max_label_width}"
        fi
    fi

    visible_length=$((6 + ${#label}))
    right_padding=$((inner_width - visible_length))

    if (( right_padding < 0 )); then
        right_padding=0
    fi

    printf '%b│%b' "${BOLD}${CYAN}" "$RESET"

    printf '  %b%2s)%b %s' \
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

print_horizontal_line() {
    local width

    width="$(box_width)"

    printf '%b' "$CYAN"
    repeat_char '─' "$width"
    printf '%b\n' "$RESET"
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

parse_example_arguments() {
    local input="$1"

    PARSED_ARGS=()

    if [[ -z "$input" ]]; then
        return 0
    fi

    : > "$ARGS_FILE"

    if ! python3 - "$input" "$ARGS_FILE" <<'PY'
import shlex
import sys

input_value = sys.argv[1]
output_path = sys.argv[2]

try:
    arguments = shlex.split(input_value)
except ValueError as error:
    print(f"Invalid arguments: {error}", file=sys.stderr)
    sys.exit(1)

with open(output_path, "wb") as output_file:
    for argument in arguments:
        output_file.write(argument.encode("utf-8"))
        output_file.write(b"\0")
PY
    then
        return 1
    fi

    mapfile -d '' -t PARSED_ARGS < "$ARGS_FILE"
}

parse_examples_metadata() {
    python3 - "$METADATA_FILE" <<'PY'
import json
import sys

metadata_path = sys.argv[1]

with open(metadata_path, "r", encoding="utf-8") as metadata_file:
    metadata = json.load(metadata_file)

workspace_members = set(metadata["workspace_members"])
examples = []

for package in metadata["packages"]:
    if package["id"] not in workspace_members:
        continue

    package_name = package["name"]
    manifest_path = package["manifest_path"]

    for target in package["targets"]:
        if "example" not in target["kind"]:
            continue

        example_name = target["name"]

        examples.append(
            (
                package_name,
                example_name,
                manifest_path,
            )
        )

examples.sort(key=lambda entry: (entry[0], entry[1]))

for package_name, example_name, manifest_path in examples:
    print(
        package_name,
        example_name,
        manifest_path,
        sep="\t",
    )
PY
}

discover_examples() {
    : > "$METADATA_FILE"
    : > "$EXAMPLES_FILE"

    if ! cargo metadata \
        --no-deps \
        --format-version 1 \
        > "$METADATA_FILE"; then

        echo
        print_error "Failed to read Cargo workspace metadata."

        return 1
    fi

    if ! parse_examples_metadata > "$EXAMPLES_FILE"; then
        echo
        print_error "Failed to parse example targets from Cargo metadata."

        return 1
    fi

    mapfile -t EXAMPLES < "$EXAMPLES_FILE"
}

show_menu() {
    local width

    width="$(box_width)"

    print_box_top "$width"
    print_box_title "$width" "EXAMPLES"
    print_box_separator "$width"

    print_box_empty "$width"

    for i in "${!EXAMPLES[@]}"; do
        IFS=$'\t' read -r package example manifest <<< "${EXAMPLES[$i]}"

        local label
        label="$package / $example"

        print_box_option \
            "$width" \
            "$((i + 1))" \
            "$label"
    done

    print_box_empty "$width"

    print_box_option "$width" "A" "Run All"
    print_box_option "$width" "0" "Back"

    print_box_empty "$width"

    print_box_bottom "$width"
}

run_example() {
    local entry="$1"
    shift

    local example_args=("$@")

    IFS=$'\t' read -r package example manifest <<< "$entry"

    local relative_manifest="${manifest#"$WORKSPACE_DIR"/}"

    local cargo_command=(
        cargo run
        --manifest-path "$manifest"
        --example "$example"
    )

    if (( ${#example_args[@]} > 0 )); then
        cargo_command+=(-- "${example_args[@]}")
    fi

    : > "$OUTPUT_FILE"

    clear_screen

    {
        echo

        print_banner "RUN EXAMPLE"

        echo

        print_info "Package:"
        printf '  %b%s%b\n' \
            "$YELLOW" \
            "$package" \
            "$RESET"

        echo

        print_info "Example:"
        printf '  %b%s%b\n' \
            "$YELLOW" \
            "$example" \
            "$RESET"

        echo

        print_info "Manifest:"
        printf '  %b%s%b\n' \
            "$YELLOW" \
            "$relative_manifest" \
            "$RESET"

        if (( ${#example_args[@]} > 0 )); then
            echo

            print_info "Arguments:"

            printf '  %b' "$YELLOW"
            printf '%q ' "${example_args[@]}"
            printf '%b\n' "$RESET"
        fi

        echo

        print_info "Running example..."

        echo

        "${cargo_command[@]}"

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

        print_banner "RUN ALL EXAMPLES"

        echo

        for entry in "${EXAMPLES[@]}"; do
            IFS=$'\t' read -r package example manifest <<< "$entry"

            print_horizontal_line

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

        print_horizontal_line

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

    printf '  %b%s%b\n' \
        "$YELLOW" \
        "$WORKSPACE_DIR" \
        "$RESET"

    exit 1
fi

if ! discover_examples; then
    exit 1
fi

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

                echo

                read -r -p "Arguments (optional): " arguments_input

                if ! parse_example_arguments "$arguments_input"; then
                    echo

                    print_error "Failed to parse example arguments."

                    echo
                    read -r -p "Press Enter to continue..."

                    continue
                fi

                set +e

                run_example \
                    "${EXAMPLES[$((option - 1))]}" \
                    "${PARSED_ARGS[@]}"

                set -e
            else
                echo

                print_warning "Invalid option: $option"

                sleep 1
            fi
            ;;
    esac
done
