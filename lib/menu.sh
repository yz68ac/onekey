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

menu_user_exists() {
    jq -e --arg email "$1" '.users[]? | select(.email == $email)' "$USERS_FILE" >/dev/null
}

menu_user_add() {
    require_root
    init_state_files
    local email uuid suggested
    suggested="user$(random_hex 2)@onekey.local"
    while true; do
        email="$(ask "User email (only a label, nothing is sent)" "$suggested")"
        if ! validate_email "$email"; then
            ui_bad "'$email' is not an email-style label (example: alice@onekey.local)"
        elif menu_user_exists "$email"; then
            ui_bad "$email already exists; pick another label"
        else
            break
        fi
    done

    uuid="$(ask "UUID, leave empty for a random one (recommended)")"
    # Anything that is not a UUID becomes a deterministic seed: whoever
    # guesses the text can derive the credential, so make that explicit.
    if [ -n "$uuid" ] && ! validate_uuid "$uuid"; then
        ui_bad "'$uuid' is not a UUID, so it would be used as a seed"
        ui_bad "anyone who guesses that text can derive this user's credential"
        if ! confirm "Use it as a seed anyway?" "n"; then
            uuid=""
            ui_note "using a random UUID instead"
        fi
    fi
    user_add_and_apply "$email" "$uuid"
    link_show "$email"
}

menu_user_del() {
    require_root
    init_state_files
    local email
    if [ "$(jq '.users | length' "$USERS_FILE")" -eq 0 ]; then
        printf 'No users configured.\n'
        return 0
    fi
    user_list
    printf '\n'
    while true; do
        email="$(ask "User email to delete, empty to cancel")"
        if [ -z "$email" ]; then
            ui_note "cancelled"
            return 0
        fi
        menu_user_exists "$email" && break
        ui_bad "no user named $email"
    done
    if ! confirm "Delete $email? Their share link stops working immediately" "n"; then
        ui_note "cancelled"
        return 0
    fi
    user_delete_and_apply "$email"
}

menu_traffic() {
    local target
    target="$(ask "Email or all" "all")"
    traffic_show "$target"
}

menu_link() {
    local email
    email="$(single_user_email)"
    if [ -n "$email" ]; then
        link_show "$email"
        return 0
    fi
    user_list
    email="$(ask "User email, empty for all" "")"
    if [ -z "$email" ]; then
        link_show_all
    else
        link_show "$email"
    fi
}

menu_header() {
    local mode="$1" detail=""
    printf '\n%s%s  ONEKEY XRAY + CADDY%s\n' "$c_bold" "$c_cyan" "$c_reset"
    printf '%s  %s%s\n' "$c_dim" "$(ui_repeat '-' 46)" "$c_reset"
    if [ -z "$mode" ]; then
        printf '  %sNot set up yet: press Enter to start the one-key setup%s\n\n' "$c_yellow" "$c_reset"
        return 0
    fi
    case "$mode" in
        xhttp) detail=" | Domain: $(jq -r '.domain // ""' "$STATE_FILE")" ;;
        *) detail=" | SNI: $(jq -r '.reality.server_name // ""' "$STATE_FILE")" ;;
    esac
    printf '  %sCurrent: %s%s, %s user(s)%s\n' "$c_dim" "$(mode_display_name "$mode")" "$detail" \
        "$(jq '.users | length' "$USERS_FILE" 2>/dev/null || printf '?')" "$c_reset"
    printf '  %sPress Enter for the share link; 1 re-runs setup%s\n\n' "$c_dim" "$c_reset"
}

# Run one menu action in a subshell so a failed validation (die) or a rolled
# back transaction returns to the menu instead of closing it. errexit is
# switched off in the parent only, so it still applies inside the action.
menu_run() {
    local rc
    set +e
    (
        set -e
        "$@"
    )
    rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
        printf '\n'
        ui_bad "that action did not complete (exit $rc); see the message above"
    fi
    return 0
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

menu_caddy_apply() {
    require_root
    caddy_apply_from_state
}

interactive_menu() {
    local choice current default
    while true; do
        clear 2>/dev/null || true
        current="$(onekey_current_mode 2>/dev/null || true)"
        # Enter on a fresh server starts setup; on a configured one it shows
        # the share link instead of re-running the whole installation.
        if [ -n "$current" ]; then
            default="12"
        else
            default="1"
        fi
        menu_header "$current"
        menu_body
        printf '\n'
        choice="$(ask "Choose" "$default")"
        printf '\n'
        case "$choice" in
            1) menu_run menu_one_key ;;
            2) menu_run menu_install ;;
            r | R | reconfigure | edit) menu_run menu_reconfigure_current ;;
            3) menu_run menu_switch_reality ;;
            4) menu_run menu_switch_reality_self ;;
            5) menu_run menu_switch_xhttp ;;
            6) menu_run menu_switch_xhttp_reality ;;
            7) menu_run menu_switch_xhttp_reality_self ;;
            8) menu_run menu_user_add ;;
            9) menu_run menu_user_del ;;
            10) menu_run user_list ;;
            11) menu_run menu_traffic ;;
            12) menu_run menu_link ;;
            13) menu_run service_command start ;;
            14) menu_run service_command stop ;;
            15) menu_run service_command restart ;;
            16) menu_run service_command status ;;
            17) menu_run service_command logs ;;
            18) menu_run service_command test ;;
            19) menu_run menu_caddy_apply ;;
            20) menu_run bbr_status ;;
            21) menu_run bbr_enable ;;
            22) menu_run bbr_disable ;;
            0 | q | quit | exit) exit 0 ;;
            *) ui_bad "unknown choice: $choice" ;;
        esac
        pause_menu
    done
}
