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
 4) Switch to XHTTP + REALITY
 5) Add UUID user
 6) Delete user
 7) List users
 8) Show traffic
 9) Generate share link
10) Start Xray
11) Stop Xray
12) Restart Xray
13) Xray status
14) Xray logs
15) Test generated config
16) Re-apply Caddy config
 0) Exit
EOF
        printf '\n'
        read -r -p "Choose: " choice
        printf '\n'
        case "$choice" in
            1) menu_install ;;
            2) menu_switch_xhttp ;;
            3) menu_switch_reality ;;
            4) menu_switch_xhttp_reality ;;
            5) menu_user_add ;;
            6) menu_user_del ;;
            7) user_list ;;
            8) menu_traffic ;;
            9) menu_link ;;
            10) service_command start ;;
            11) service_command stop ;;
            12) service_command restart ;;
            13) service_command status ;;
            14) service_command logs ;;
            15) service_command test ;;
            16) require_root; caddy_apply_from_state ;;
            0) exit 0 ;;
            *) warn "Unknown choice: $choice" ;;
        esac
        pause_menu
    done
}
