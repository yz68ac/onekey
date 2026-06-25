#!/usr/bin/env bash

menu_install() {
    require_root
    install_all
}

menu_switch_xhttp() {
    require_root
    local domain acme_email path port
    domain="$(prompt "Domain for Caddy/XHTTP")"
    acme_email="$(prompt "ACME email")"
    path="$(prompt "XHTTP path" "$(generate_path)")"
    port="$(prompt "Local Xray XHTTP port" "10000")"
    switch_xhttp "$domain" "$acme_email" "$path" "$port"
}

menu_switch_reality() {
    require_root
    local server_name target address port
    server_name="$(prompt "REALITY serverName/SNI")"
    target="$(prompt "REALITY target" "$server_name:443")"
    address="$(prompt "Client address in share link" "$server_name")"
    port="$(prompt "Xray listen port" "443")"
    switch_reality_vision "$server_name" "$target" "$address" "$port"
}

menu_switch_xhttp_reality() {
    require_root
    local server_name target address path port
    server_name="$(prompt "REALITY serverName/SNI")"
    target="$(prompt "REALITY target" "$server_name:443")"
    address="$(prompt "Client address in share link" "$server_name")"
    path="$(prompt "XHTTP path" "$(generate_path)")"
    port="$(prompt "Xray listen port" "443")"
    switch_xhttp_reality "$server_name" "$target" "$address" "$path" "$port"
}

menu_switch_reality_self() {
    require_root
    local domain acme_email address port fallback_port
    domain="$(prompt "REALITY self-steal domain/SNI")"
    acme_email="$(prompt "ACME email for local Caddy TLS")"
    address="$(prompt "Client address in share link" "$domain")"
    port="$(prompt "Xray public listen port" "443")"
    fallback_port="$(prompt "Local Caddy HTTPS fallback port" "8443")"
    switch_reality_self "$domain" "$acme_email" "$address" "$port" "$fallback_port"
}

menu_switch_xhttp_reality_self() {
    require_root
    local domain acme_email address path port fallback_port
    domain="$(prompt "XHTTP REALITY self-steal domain/SNI")"
    acme_email="$(prompt "ACME email for local Caddy TLS")"
    address="$(prompt "Client address in share link" "$domain")"
    path="$(prompt "XHTTP path" "$(generate_path)")"
    port="$(prompt "Xray public listen port" "443")"
    fallback_port="$(prompt "Local Caddy HTTPS fallback port" "8443")"
    switch_xhttp_reality_self "$domain" "$acme_email" "$address" "$path" "$port" "$fallback_port"
}

menu_user_add() {
    require_root
    local email uuid
    email="$(prompt "User email")"
    uuid="$(prompt "UUID or custom seed, leave empty to auto-generate")"
    user_add "$email" "$uuid"
    apply_xray_config_and_restart
}

menu_user_del() {
    require_root
    local email
    email="$(prompt "User email to delete")"
    user_delete "$email"
    apply_xray_config_and_restart
}

menu_traffic() {
    local target
    target="$(prompt "Email or all" "all")"
    traffic_show "$target"
}

menu_link() {
    local email
    email="$(prompt "User email")"
    link_show "$email"
}

interactive_menu() {
    while true; do
        clear 2>/dev/null || true
        cat <<'EOF'
===============================
 OneKey Xray + Caddy Manager
===============================
 1) Install or update Xray
 2) Switch to XHTTP + Caddy
 3) Switch to REALITY + Vision
 4) Switch to REALITY self-steal + local Caddy
 5) Switch to XHTTP + REALITY
 6) Switch to XHTTP + REALITY self-steal + local Caddy
 7) Add UUID user
 8) Delete user
 9) List users
10) Show traffic
11) Generate share link
12) Start Xray
13) Stop Xray
14) Restart Xray
15) Xray status
16) Xray logs
17) Test generated config
18) Re-apply Caddy config
 0) Exit
EOF
        printf '\n'
        read -r -p "Choose: " choice
        printf '\n'
        case "$choice" in
            1) menu_install ;;
            2) menu_switch_xhttp ;;
            3) menu_switch_reality ;;
            4) menu_switch_reality_self ;;
            5) menu_switch_xhttp_reality ;;
            6) menu_switch_xhttp_reality_self ;;
            7) menu_user_add ;;
            8) menu_user_del ;;
            9) user_list ;;
            10) menu_traffic ;;
            11) menu_link ;;
            12) service_command start ;;
            13) service_command stop ;;
            14) service_command restart ;;
            15) service_command status ;;
            16) service_command logs ;;
            17) service_command test ;;
            18) require_root; caddy_apply_from_state ;;
            0) exit 0 ;;
            *) warn "Unknown choice: $choice" ;;
        esac
        pause_menu
    done
}
