#!/usr/bin/env bash

service_command() {
    local action="$1"
    shift || true

    case "$action" in
        start|stop|restart|status)
            have_cmd systemctl || die "systemctl is required"
            systemctl "$action" "$XRAY_SERVICE"
            ;;
        logs)
            have_cmd journalctl || die "journalctl is required"
            journalctl -u "$XRAY_SERVICE" -e --no-pager -n "${1:-120}"
            ;;
        test)
            init_state_files
            local rendered="$RENDERED_DIR/config.test.$(timestamp).json"
            render_xray_config "$rendered"
            test_xray_config_file "$rendered"
            ok "Xray config test passed: $rendered"
            ;;
        *)
            die "Unsupported service action: $action"
            ;;
    esac
}
