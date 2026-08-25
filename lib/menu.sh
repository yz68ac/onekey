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
    local domain acme_email path port
    domain="$(ask "Domain for Caddy/XHTTP")"
    acme_email="$(ask "ACME email" "$(derive_acme_email "$domain")")"
    path="$(ask "XHTTP path" "$(generate_path)")"
    port="$(ask "Local Xray XHTTP port" "10000")"
    switch_xhttp "$domain" "$acme_email" "$path" "$port"
    onekey_status_panel
}

menu_switch_reality() {
    require_root
    local server_name target address port
    server_name="$(ask "REALITY serverName/SNI, empty to auto-pick")"
    if [ -z "$server_name" ]; then
        target="$(setup_resolve_target)"
        server_name="$(reality_target_host "$target")"
    else
        target="$(ask "REALITY target" "$server_name:443")"
    fi
    address="$(ask "Client address in share link" "$(detect_public_ip || printf '%s' "$server_name")")"
    port="$(ask "Xray listen port" "443")"
    switch_reality_vision "$server_name" "$target" "$address" "$port"
    onekey_status_panel
}

menu_switch_xhttp_reality() {
    require_root
    local server_name target address path port
    server_name="$(ask "REALITY serverName/SNI, empty to auto-pick")"
    if [ -z "$server_name" ]; then
        target="$(setup_resolve_target)"
        server_name="$(reality_target_host "$target")"
    else
        target="$(ask "REALITY target" "$server_name:443")"
    fi
    address="$(ask "Client address in share link" "$(detect_public_ip || printf '%s' "$server_name")")"
    path="$(ask "XHTTP path" "$(generate_path)")"
    port="$(ask "Xray listen port" "443")"
    switch_xhttp_reality "$server_name" "$target" "$address" "$path" "$port"
    onekey_status_panel
}

menu_switch_reality_self() {
    require_root
    local domain acme_email address port fallback_port
    domain="$(ask "REALITY self-steal domain/SNI")"
    acme_email="$(ask "ACME email for local Caddy TLS" "$(derive_acme_email "$domain")")"
    address="$(ask "Client address in share link" "$(detect_public_ip || printf '%s' "$domain")")"
    port="$(ask "Xray public listen port" "443")"
    fallback_port="$(ask "Local Caddy HTTPS fallback port" "8443")"
    switch_reality_self "$domain" "$acme_email" "$address" "$port" "$fallback_port"
    onekey_status_panel
}

menu_switch_xhttp_reality_self() {
    require_root
    local domain acme_email address path port fallback_port
    domain="$(ask "XHTTP REALITY self-steal domain/SNI")"
    acme_email="$(ask "ACME email for local Caddy TLS" "$(derive_acme_email "$domain")")"
    address="$(ask "Client address in share link" "$(detect_public_ip || printf '%s' "$domain")")"
    path="$(ask "XHTTP path" "$(generate_path)")"
    port="$(ask "Xray public listen port" "443")"
    fallback_port="$(ask "Local Caddy HTTPS fallback port" "8443")"
    switch_xhttp_reality_self "$domain" "$acme_email" "$address" "$path" "$port" "$fallback_port"
    onekey_status_panel
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
    printf '\n%s%s  ONEKEY XRAY + CADDY%s\n' "$c_bold" "$c_cyan" "$c_reset"
    printf '%s  %s%s\n\n' "$c_dim" "$(ui_repeat '-' 46)" "$c_reset"
}

menu_body() {
    cat <<EOF
  ${c_bold}${c_green}1)${c_reset} One-key setup ${c_dim}(deps + Xray + mode + user + link)${c_reset}
  ${c_bold}2)${c_reset} Install or update Xray

  ${c_dim}-- modes --${c_reset}
  ${c_bold}3)${c_reset} REALITY + Vision
  ${c_bold}4)${c_reset} REALITY self-steal + local Caddy
  ${c_bold}5)${c_reset} XHTTP + Caddy (TLS)
  ${c_bold}6)${c_reset} XHTTP + REALITY
  ${c_bold}7)${c_reset} XHTTP + REALITY self-steal + local Caddy

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
