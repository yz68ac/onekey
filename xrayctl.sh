#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
export ONEKEY_ROOT="$SCRIPT_DIR"

# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/state.sh
. "$SCRIPT_DIR/lib/state.sh"
# shellcheck source=lib/generate.sh
. "$SCRIPT_DIR/lib/generate.sh"
# shellcheck source=lib/users.sh
. "$SCRIPT_DIR/lib/users.sh"
# shellcheck source=lib/render.sh
. "$SCRIPT_DIR/lib/render.sh"
# shellcheck source=lib/caddy.sh
. "$SCRIPT_DIR/lib/caddy.sh"
# shellcheck source=lib/install.sh
. "$SCRIPT_DIR/lib/install.sh"
# shellcheck source=lib/service.sh
. "$SCRIPT_DIR/lib/service.sh"
# shellcheck source=lib/traffic.sh
. "$SCRIPT_DIR/lib/traffic.sh"
# shellcheck source=lib/links.sh
. "$SCRIPT_DIR/lib/links.sh"
# shellcheck source=lib/menu.sh
. "$SCRIPT_DIR/lib/menu.sh"

usage() {
    cat <<'EOF'
Usage:
  ./xrayctl.sh
  ./xrayctl.sh menu
  ./xrayctl.sh install
  ./xrayctl.sh switch xhttp --domain example.com --email admin@example.com [--path /secret] [--port 10000]
  ./xrayctl.sh switch xhttp-reality --server-name example.com --target example.com:443 [--address your.server.com] [--path /secret] [--port 443]
  ./xrayctl.sh switch reality --server-name example.com --target example.com:443 [--address your.server.com] [--port 443]
  ./xrayctl.sh switch vision --server-name example.com --target example.com:443 [--address your.server.com]
  ./xrayctl.sh user add alice@example.com [uuid]
  ./xrayctl.sh user del alice@example.com
  ./xrayctl.sh user list
  ./xrayctl.sh traffic all
  ./xrayctl.sh traffic alice@example.com
  ./xrayctl.sh link alice@example.com
  ./xrayctl.sh start|stop|restart|status|logs|test

Runtime paths:
  Xray config : /usr/local/etc/xray/config.json
  Caddyfile   : /etc/caddy/Caddyfile
  State       : /etc/onekey-xray
EOF
}

parse_switch_xhttp() {
    local domain="" acme_email="" path="" port=""

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --domain)
                domain="${2:-}"
                shift 2
                ;;
            --email|--acme-email)
                acme_email="${2:-}"
                shift 2
                ;;
            --path)
                path="${2:-}"
                shift 2
                ;;
            --port|--xhttp-port)
                port="${2:-}"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "Unknown xhttp option: $1"
                ;;
        esac
    done

    [ -n "$domain" ] || die "--domain is required"
    [ -n "$acme_email" ] || die "--email is required"
    path="${path:-$(generate_path)}"
    port="${port:-10000}"

    switch_xhttp "$domain" "$acme_email" "$path" "$port"
}

parse_switch_reality() {
    local server_name="" target="" address="" port="443"

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --server-name|--sni)
                server_name="${2:-}"
                shift 2
                ;;
            --target|--dest)
                target="${2:-}"
                shift 2
                ;;
            --address)
                address="${2:-}"
                shift 2
                ;;
            --port)
                port="${2:-}"
                shift 2
                ;;
            --vision)
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "Unknown reality option: $1"
                ;;
        esac
    done

    [ -n "$server_name" ] || die "--server-name is required"
    [ -n "$target" ] || die "--target is required"
    address="${address:-$server_name}"

    switch_reality_vision "$server_name" "$target" "$address" "$port"
}

parse_switch_xhttp_reality() {
    local server_name="" target="" address="" path="" port="443"

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --server-name|--sni)
                server_name="${2:-}"
                shift 2
                ;;
            --target|--dest)
                target="${2:-}"
                shift 2
                ;;
            --address)
                address="${2:-}"
                shift 2
                ;;
            --path)
                path="${2:-}"
                shift 2
                ;;
            --port)
                port="${2:-}"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "Unknown xhttp-reality option: $1"
                ;;
        esac
    done

    [ -n "$server_name" ] || die "--server-name is required"
    [ -n "$target" ] || die "--target is required"
    address="${address:-$server_name}"
    path="${path:-$(generate_path)}"

    switch_xhttp_reality "$server_name" "$target" "$address" "$path" "$port"
}

main() {
    local cmd="${1:-menu}"
    if [ "$#" -gt 0 ]; then
        shift
    fi

    case "$cmd" in
        menu)
            interactive_menu
            ;;
        help|-h|--help)
            usage
            ;;
        install)
            require_root
            install_all
            ;;
        switch)
            require_root
            local mode="${1:-}"
            [ -n "$mode" ] || die "Missing switch mode: xhttp, xhttp-reality, reality, or vision"
            shift || true
            case "$mode" in
                xhttp)
                    parse_switch_xhttp "$@"
                    ;;
                xhttp-reality|xreality|xhttp_reality)
                    parse_switch_xhttp_reality "$@"
                    ;;
                reality|reality-vision|vision|vison)
                    parse_switch_reality "$@"
                    ;;
                *)
                    die "Unsupported mode: $mode"
                    ;;
            esac
            ;;
        user)
            require_root
            local action="${1:-}"
            shift || true
            case "$action" in
                add)
                    user_add "${1:-}" "${2:-}"
                    apply_xray_config_and_restart
                    ;;
                del|delete|remove)
                    user_delete "${1:-}"
                    apply_xray_config_and_restart
                    ;;
                list|ls)
                    user_list
                    ;;
                *)
                    die "Usage: ./xrayctl.sh user add|del|list ..."
                    ;;
            esac
            ;;
        traffic)
            traffic_show "${1:-all}"
            ;;
        link)
            link_show "${1:-}"
            ;;
        caddy)
            require_root
            caddy_apply_from_state
            ;;
        start|stop|restart|status|logs|test)
            service_command "$cmd" "$@"
            ;;
        *)
            die "Unknown command: $cmd"
            ;;
    esac
}

main "$@"
