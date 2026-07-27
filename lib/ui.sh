#!/usr/bin/env bash
# Terminal presentation helpers: colors, panels, QR codes.
# All progress output goes to stderr so these are safe inside $( ).

UI_PANEL_W="${UI_PANEL_W:-66}"

c_reset=""
c_bold=""
c_dim=""
c_red=""
c_green=""
c_yellow=""
c_blue=""
c_cyan=""

ui_init() {
    if [ -n "${NO_COLOR:-}" ] || [ "${ONEKEY_NO_COLOR:-0}" = "1" ] || [ ! -t 1 ]; then
        return 0
    fi
    c_reset=$'\033[0m'
    c_bold=$'\033[1m'
    c_dim=$'\033[2m'
    c_red=$'\033[31m'
    c_green=$'\033[32m'
    c_yellow=$'\033[33m'
    c_blue=$'\033[34m'
    c_cyan=$'\033[36m'
}

ui_repeat() {
    local ch="$1" n="$2" out="" i
    for ((i = 0; i < n; i++)); do
        out+="$ch"
    done
    printf '%s' "$out"
}

ui_trunc() {
    local s="$1" n="$2"
    if [ "${#s}" -le "$n" ]; then
        printf '%s' "$s"
    else
        printf '%s...' "${s:0:$((n - 3))}"
    fi
}

# Progress helpers. stderr on purpose.
ui_step() {
    printf '%s==>%s %s%s%s\n' "$c_cyan$c_bold" "$c_reset" "$c_bold" "$*" "$c_reset" >&2
}

ui_note() {
    printf '    %s%s%s\n' "$c_dim" "$*" "$c_reset" >&2
}

ui_good() {
    printf '    %s+%s %s\n' "$c_green" "$c_reset" "$*" >&2
}

ui_bad() {
    printf '    %s!%s %s\n' "$c_yellow" "$c_reset" "$*" >&2
}

ui_banner() {
    printf '%s\n' "$c_cyan$c_bold" >&2
    cat >&2 <<'EOF'
   ___             _  __
  / _ \ _ __   ___| |/ /___ _   _
 | | | | '_ \ / _ \ ' // _ \ | | |
 | |_| | | | |  __/ . \  __/ |_| |
  \___/|_| |_|\___|_|\_\___|\__, |
                            |___/   Xray + Caddy
EOF
    printf '%s\n' "$c_reset" >&2
}

ui_panel_top() {
    printf '%s+%s+%s\n' "$c_cyan" "$(ui_repeat '-' "$UI_PANEL_W")" "$c_reset"
}

ui_panel_sep() {
    printf '%s+%s+%s\n' "$c_cyan" "$(ui_repeat '-' "$UI_PANEL_W")" "$c_reset"
}

ui_panel_bottom() {
    printf '%s+%s+%s\n' "$c_cyan" "$(ui_repeat '-' "$UI_PANEL_W")" "$c_reset"
}

# One "  LABEL        value  " row, padded to the panel width.
ui_row() {
    local label="$1" value="$2" w
    w=$((UI_PANEL_W - 16))
    value="$(ui_trunc "$value" "$w")"
    printf '%s|%s  %-12s %s%-*s%s %s|%s\n' \
        "$c_cyan" "$c_reset" "$label" "$c_bold" "$w" "$value" "$c_reset" "$c_cyan" "$c_reset"
}

ui_row_plain() {
    local text="$1" w
    w=$((UI_PANEL_W - 3))
    text="$(ui_trunc "$text" "$w")"
    printf '%s|%s  %-*s %s|%s\n' "$c_cyan" "$c_reset" "$w" "$text" "$c_cyan" "$c_reset"
}

ui_title() {
    local text="$1" w
    w=$((UI_PANEL_W - 3))
    printf '%s|%s  %s%-*s%s %s|%s\n' \
        "$c_cyan" "$c_reset" "$c_bold$c_green" "$w" "$text" "$c_reset" "$c_cyan" "$c_reset"
}

# Print a share link so it is easy to select and copy, then its QR code.
ui_link_block() {
    local link="$1" show_qr="${2:-1}"
    printf '\n%s%sShare link%s\n' "$c_bold" "$c_green" "$c_reset"
    printf '%s\n' "$link"
    if [ "$show_qr" = "1" ]; then
        ui_qr "$link"
    fi
}

ui_qr() {
    local text="$1"
    if ! have_cmd qrencode; then
        if ! ensure_cmd qrencode optional; then
            printf '\n%s(install qrencode to get a scannable QR code here)%s\n' "$c_dim" "$c_reset"
            return 0
        fi
    fi
    printf '\n'
    qrencode -t ANSIUTF8 -m 1 -l L "$text" 2>/dev/null ||
        qrencode -t UTF8 -m 1 -l L "$text" 2>/dev/null ||
        printf '%s(QR generation failed)%s\n' "$c_dim" "$c_reset"
}
