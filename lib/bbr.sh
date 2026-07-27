#!/usr/bin/env bash

BBR_SYSCTL_FILE="${BBR_SYSCTL_FILE:-/etc/sysctl.d/99-onekey-bbr.conf}"

bbr_require_linux() {
    [ "$(uname -s 2>/dev/null)" = "Linux" ] || die "BBR is only supported on Linux"
}

bbr_current_congestion() {
    sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || printf 'unknown\n'
}

bbr_current_qdisc() {
    sysctl -n net.core.default_qdisc 2>/dev/null || printf 'unknown\n'
}

bbr_available_congestion() {
    sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || printf 'unknown\n'
}

bbr_module_loaded() {
    [ -r /proc/modules ] || return 1
    grep -q '^tcp_bbr ' /proc/modules
}

bbr_status() {
    bbr_require_linux
    ensure_cmd sysctl

    local cc qdisc available module_state config_state
    cc="$(bbr_current_congestion)"
    qdisc="$(bbr_current_qdisc)"
    available="$(bbr_available_congestion)"
    if bbr_module_loaded || printf '%s\n' "$available" | grep -qw bbr; then
        module_state="available"
    else
        module_state="not loaded"
    fi
    if [ -f "$BBR_SYSCTL_FILE" ]; then
        config_state="$BBR_SYSCTL_FILE"
    else
        config_state="not managed by onekey"
    fi

    if declare -F ui_panel_top >/dev/null 2>&1; then
        ui_panel_top
        ui_title "BBR status"
        ui_panel_sep
        ui_row "Congestion" "$cc"
        ui_row "Qdisc" "$qdisc"
        ui_row "BBR" "$module_state"
        ui_row "Config" "$config_state"
        ui_panel_bottom
    else
        printf 'Congestion: %s\n' "$cc"
        printf 'Qdisc    : %s\n' "$qdisc"
        printf 'BBR      : %s\n' "$module_state"
        printf 'Config   : %s\n' "$config_state"
    fi
}

bbr_enable() {
    bbr_require_linux
    require_root
    ensure_cmd sysctl
    ensure_cmd modprobe optional >/dev/null 2>&1 || true

    if have_cmd modprobe; then
        modprobe tcp_bbr 2>/dev/null || true
    fi

    mkdir -p "$(dirname "$BBR_SYSCTL_FILE")"
    cat > "$BBR_SYSCTL_FILE" <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

    sysctl --system >/dev/null
    if [ "$(bbr_current_congestion)" != "bbr" ]; then
        die "Failed to enable BBR; current congestion control is $(bbr_current_congestion)"
    fi
    ok "BBR enabled"
    bbr_status
}

bbr_disable() {
    bbr_require_linux
    require_root
    ensure_cmd sysctl

    if [ -f "$BBR_SYSCTL_FILE" ]; then
        rm -f "$BBR_SYSCTL_FILE"
        sysctl --system >/dev/null
        ok "Removed $BBR_SYSCTL_FILE"
    else
        warn "No onekey BBR config found: $BBR_SYSCTL_FILE"
    fi
    bbr_status
}

bbr_command() {
    local action="${1:-status}"
    case "$action" in
        status|show|info)
            bbr_status
            ;;
        on|enable)
            bbr_enable
            ;;
        off|disable)
            bbr_disable
            ;;
        *)
            die "Usage: $ONEKEY_ENTRY bbr status|on|off"
            ;;
    esac
}
