#!/usr/bin/env bash

menu_one_key() {
    onekey_setup
}

menu_install() {
    require_root
    install_all
}

menu_switch_xhttp() {
    require_root
    local use_current="${1:-0}" domain acme_email path port
    local domain_default="" email_default="" path_default="" port_default="10000"
    if [ "$use_current" = "1" ]; then
        domain_default="$(state_get '.domain // ""')"
        email_default="$(state_get '.acme_email // ""')"
        path_default="$(state_get '.xhttp.path // ""')"
        port_default="$(state_get '.xhttp.port // 10000')"
    fi
    domain="$(ask_required "Domain for Caddy/XHTTP" "$domain_default")"
    acme_email="$(ask "ACME email" "${email_default:-$(derive_acme_email "$domain")}")"
    path="$(ask "XHTTP path" "${path_default:-$(generate_path)}")"
    port="$(ask "Local Xray XHTTP port" "$port_default")"
    switch_xhttp "$domain" "$acme_email" "$path" "$port"
    onekey_status_panel
}

menu_switch_reality() {
    require_root
    local use_current="${1:-0}" server_name target suggested_target address port
    local server_default="" target_default="" address_default="" port_default="443"
    if [ "$use_current" = "1" ]; then
        server_default="$(state_get '.reality.server_name // ""')"
        target_default="$(state_get '.reality.target // ""')"
        address_default="$(state_get '.reality.address // .address // ""')"
        port_default="$(state_get '.reality.listen_port // 443')"
    fi
    server_name="$(ask "REALITY serverName/SNI, empty to auto-pick" "$server_default")"
    if [ -z "$server_name" ]; then
        target="$(setup_resolve_target)"
        server_name="$(reality_target_host "$target")"
    else
        if [ "$use_current" = "1" ] && [ "$server_name" = "$server_default" ]; then
            suggested_target="${target_default:-$server_name:443}"
        else
            suggested_target="$server_name:443"
        fi
        target="$(ask "REALITY target" "$suggested_target")"
    fi
    address="$(ask "Client address in share link" "${address_default:-$(detect_public_ip || printf '%s' "$server_name")}")"
    port="$(ask "Xray listen port" "$port_default")"
    switch_reality_vision "$server_name" "$target" "$address" "$port"
    onekey_status_panel
}

menu_switch_xhttp_reality() {
    require_root
    local use_current="${1:-0}" server_name target suggested_target address path port
    local server_default="" target_default="" address_default="" path_default="" port_default="443"
    if [ "$use_current" = "1" ]; then
        server_default="$(state_get '.reality.server_name // ""')"
        target_default="$(state_get '.reality.target // ""')"
        address_default="$(state_get '.reality.address // .address // ""')"
        path_default="$(state_get '.xhttp.path // ""')"
        port_default="$(state_get '.reality.listen_port // 443')"
    fi
    server_name="$(ask "REALITY serverName/SNI, empty to auto-pick" "$server_default")"
    if [ -z "$server_name" ]; then
        target="$(setup_resolve_target)"
        server_name="$(reality_target_host "$target")"
    else
        if [ "$use_current" = "1" ] && [ "$server_name" = "$server_default" ]; then
            suggested_target="${target_default:-$server_name:443}"
        else
            suggested_target="$server_name:443"
        fi
        target="$(ask "REALITY target" "$suggested_target")"
    fi
    address="$(ask "Client address in share link" "${address_default:-$(detect_public_ip || printf '%s' "$server_name")}")"
    path="$(ask "XHTTP path" "${path_default:-$(generate_path)}")"
    port="$(ask "Xray listen port" "$port_default")"
    switch_xhttp_reality "$server_name" "$target" "$address" "$path" "$port"
    onekey_status_panel
}

menu_switch_reality_self() {
    require_root
    local use_current="${1:-0}" domain acme_email address port fallback_port
    local domain_default="" email_default="" address_default="" port_default="443" fallback_default="8443"
    if [ "$use_current" = "1" ]; then
        domain_default="$(state_get '.reality.server_name // .domain // ""')"
        email_default="$(state_get '.acme_email // ""')"
        address_default="$(state_get '.reality.address // .address // ""')"
        port_default="$(state_get '.reality.listen_port // 443')"
        fallback_default="$(state_get '.reality_self.port // 8443')"
    fi
    domain="$(ask_required "REALITY self-steal domain/SNI" "$domain_default")"
    acme_email="$(ask "ACME email for local Caddy TLS" "${email_default:-$(derive_acme_email "$domain")}")"
    address="$(ask "Client address in share link" "${address_default:-$(detect_public_ip || printf '%s' "$domain")}")"
    port="$(ask "Xray public listen port" "$port_default")"
    fallback_port="$(ask "Local Caddy HTTPS fallback port" "$fallback_default")"
    switch_reality_self "$domain" "$acme_email" "$address" "$port" "$fallback_port"
    onekey_status_panel
}

menu_switch_xhttp_reality_self() {
    require_root
    local use_current="${1:-0}" domain acme_email address path port fallback_port
    local domain_default="" email_default="" address_default="" path_default="" port_default="443" fallback_default="8443"
    if [ "$use_current" = "1" ]; then
        domain_default="$(state_get '.reality.server_name // .domain // ""')"
        email_default="$(state_get '.acme_email // ""')"
        address_default="$(state_get '.reality.address // .address // ""')"
        path_default="$(state_get '.xhttp.path // ""')"
        port_default="$(state_get '.reality.listen_port // 443')"
        fallback_default="$(state_get '.reality_self.port // 8443')"
    fi
    domain="$(ask_required "XHTTP REALITY self-steal domain/SNI" "$domain_default")"
    acme_email="$(ask "ACME email for local Caddy TLS" "${email_default:-$(derive_acme_email "$domain")}")"
    address="$(ask "Client address in share link" "${address_default:-$(detect_public_ip || printf '%s' "$domain")}")"
    path="$(ask "XHTTP path" "${path_default:-$(generate_path)}")"
    port="$(ask "Xray public listen port" "$port_default")"
    fallback_port="$(ask "Local Caddy HTTPS fallback port" "$fallback_default")"
    switch_xhttp_reality_self "$domain" "$acme_email" "$address" "$path" "$port" "$fallback_port"
    onekey_status_panel
}

menu_reconfigure_current() {
    require_root
    local mode
    mode="$(state_get '.mode // ""')"
    case "$mode" in
        xhttp) menu_switch_xhttp 1 ;;
        reality|reality-vision|vision|vison) menu_switch_reality 1 ;;
        xhttp-reality) menu_switch_xhttp_reality 1 ;;
        reality-self) menu_switch_reality_self 1 ;;
        xhttp-reality-self) menu_switch_xhttp_reality_self 1 ;;
        *) die "Current mode is not configured: $mode" ;;
    esac
}

menu_user_add() {
    require_root
    local email uuid
    email="$(ask "User email" "user$(random_hex 2)@onekey.local")"
    uuid="$(ask "UUID or custom seed, leave empty to auto-generate")"
    user_add_and_apply "$email" "$uuid"
    link_show "$email"
}

menu_user_del() {
    require_root
    local email
    user_list
    email="$(ask "User email to delete")"
    user_delete_and_apply "$email"
}

menu_traffic() {
    local target
    target="$(ask "Email or all" "all")"
    traffic_show "$target"
}

menu_link() {
    local email
    user_list
    email="$(ask "User email, empty for all" "")"
    if [ -z "$email" ]; then
        link_show_all
    else
        link_show "$email"
    fi
}

menu_header() {
    local mode="" detail=""
    printf '\n%s%s  ONEKEY XRAY + CADDY%s\n' "$c_bold" "$c_cyan" "$c_reset"
    printf '%s  %s%s\n' "$c_dim" "$(ui_repeat '-' 46)" "$c_reset"
    if [ -r "$STATE_FILE" ] && jq -e . "$STATE_FILE" >/dev/null 2>&1; then
        mode="$(jq -r '.mode // ""' "$STATE_FILE")"
        case "$mode" in
            reality|reality-vision|vision|vison|reality-self|xhttp-reality|xhttp-reality-self)
                detail=" | SNI: $(jq -r '.reality.server_name // ""' "$STATE_FILE")"
                ;;
        esac
        printf '  %sCurrent: %s%s%s\n\n' "$c_dim" "$(mode_display_name "$mode")" "$detail" "$c_reset"
    else
        printf '\n'
    fi
}

menu_body() {
    cat <<EOF
  ${c_bold}${c_green}1)${c_reset} One-key setup ${c_dim}(deps + Xray + mode + user + link)${c_reset}
  ${c_bold}2)${c_reset} Install or update Xray

  ${c_dim}-- configuration --${c_reset}
  ${c_bold}${c_green}r)${c_reset} Reconfigure current mode ${c_dim}(current values are prefilled)${c_reset}
  ${c_bold}3)${c_reset} Switch to REALITY + Vision
  ${c_bold}4)${c_reset} Switch to REALITY self-steal + local Caddy
  ${c_bold}5)${c_reset} Switch to XHTTP + Caddy (TLS)
  ${c_bold}6)${c_reset} Switch to XHTTP + REALITY
  ${c_bold}7)${c_reset} Switch to XHTTP + REALITY self-steal + local Caddy

  ${c_dim}-- users --${c_reset}
  ${c_bold}8)${c_reset} Add user           ${c_bold}9)${c_reset} Delete user       ${c_bold}10)${c_reset} List users
 ${c_bold}11)${c_reset} Traffic           ${c_bold}12)${c_reset} Share link + QR

  ${c_dim}-- service --${c_reset}
 ${c_bold}13)${c_reset} Start    ${c_bold}14)${c_reset} Stop    ${c_bold}15)${c_reset} Restart   ${c_bold}16)${c_reset} Status
 ${c_bold}17)${c_reset} Logs     ${c_bold}18)${c_reset} Test config           ${c_bold}19)${c_reset} Re-apply Caddy

  ${c_dim}-- kernel --${c_reset}
 ${c_bold}20)${c_reset} BBR status       ${c_bold}21)${c_reset} Enable BBR          ${c_bold}22)${c_reset} Disable BBR

  ${c_bold}0)${c_reset} Exit
EOF
}

interactive_menu() {
    local choice
    while true; do
        clear 2>/dev/null || true
        menu_header
        menu_body
        printf '\n'
        choice="$(ask "Choose" "1")"
        printf '\n'
        case "$choice" in
            1) menu_one_key ;;
            2) menu_install ;;
            r | R | reconfigure | edit) menu_reconfigure_current ;;
            3) menu_switch_reality ;;
            4) menu_switch_reality_self ;;
            5) menu_switch_xhttp ;;
            6) menu_switch_xhttp_reality ;;
            7) menu_switch_xhttp_reality_self ;;
            8) menu_user_add ;;
            9) menu_user_del ;;
            10) user_list ;;
            11) menu_traffic ;;
            12) menu_link ;;
            13) service_command start ;;
            14) service_command stop ;;
            15) service_command restart ;;
            16) service_command status ;;
            17) service_command logs ;;
            18) service_command test ;;
            19)
                require_root
                caddy_apply_from_state
                ;;
            20) bbr_status ;;
            21) bbr_enable ;;
            22) bbr_disable ;;
            0 | q | quit | exit) exit 0 ;;
            *) warn "Unknown choice: $choice" ;;
        esac
        pause_menu
    done
}
