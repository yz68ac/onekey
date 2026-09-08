#!/usr/bin/env bash
# Read-only health and compatibility checks.

DOCTOR_JSON=0
DOCTOR_OFFLINE=0
DOCTOR_FAILURES=0
DOCTOR_WARNINGS=0
DOCTOR_RESULTS=()

caddy_version_number() {
    have_cmd caddy || return 1
    caddy version 2>/dev/null | sed -n '1{s/^v\?\([0-9][0-9.]*\).*$/\1/p;q;}'
}

version_show() {
    local xray_version caddy_version
    xray_version="$(xray_version_number || true)"
    caddy_version="$(caddy_version_number || true)"
    printf 'OneKey Xray: %s\n' "$ONEKEY_VERSION"
    printf 'Xray-core : %s\n' "${xray_version:-not installed}"
    printf 'Caddy     : %s\n' "${caddy_version:-not installed}"
}

doctor_emit() {
    local status="$1" name="$2" detail="$3" record
    case "$status" in
        fail) DOCTOR_FAILURES=$((DOCTOR_FAILURES + 1)) ;;
        warn) DOCTOR_WARNINGS=$((DOCTOR_WARNINGS + 1)) ;;
    esac

    if [ "$DOCTOR_JSON" -eq 1 ]; then
        record="$(jq -cn \
            --arg status "$status" \
            --arg name "$name" \
            --arg detail "$detail" \
            '{status: $status, name: $name, detail: $detail}')"
        DOCTOR_RESULTS+=("$record")
    else
        printf '[%-4s] %-20s %s\n' "${status^^}" "$name" "$detail"
    fi
}

doctor_check_command() {
    local cmd="$1" required="${2:-1}"
    if have_cmd "$cmd"; then
        doctor_emit pass "command:$cmd" "available"
    elif [ "$required" = "1" ]; then
        doctor_emit fail "command:$cmd" "missing"
    else
        doctor_emit warn "command:$cmd" "optional command is missing"
    fi
}

doctor_file_mode() {
    local file="$1"
    if stat -c '%a' "$file" >/dev/null 2>&1; then
        stat -c '%a' "$file"
    elif stat -f '%Lp' "$file" >/dev/null 2>&1; then
        stat -f '%Lp' "$file"
    else
        return 1
    fi
}

doctor_check_mode() {
    local file="$1" expected="$2" label="$3" actual
    [ -e "$file" ] || return 0
    actual="$(doctor_file_mode "$file" || true)"
    if [ -z "$actual" ]; then
        doctor_emit warn "$label" "could not inspect permissions"
    elif [ "$actual" = "$expected" ]; then
        doctor_emit pass "$label" "mode $actual"
    else
        doctor_emit fail "$label" "mode $actual, expected $expected"
    fi
}

doctor_check_json_file() {
    local file="$1" query="$2" label="$3"
    if [ ! -f "$file" ]; then
        doctor_emit warn "$label" "not created yet"
        return 1
    fi
    if jq -e "$query" "$file" >/dev/null 2>&1; then
        doctor_emit pass "$label" "valid JSON"
        return 0
    fi
    doctor_emit fail "$label" "invalid JSON or schema"
    return 1
}

doctor_check_xray() {
    local version
    if [ ! -x "$XRAY_BIN" ]; then
        doctor_emit fail "xray" "binary not found: $XRAY_BIN"
        return
    fi
    version="$(xray_version_number || true)"
    doctor_emit pass "xray" "version ${version:-unknown}"
    if [ -n "$version" ] && ! version_at_least "$version" "$ONEKEY_MIN_XRAY_VERSION"; then
        doctor_emit warn "xray-version" "$version is older than the required baseline $ONEKEY_MIN_XRAY_VERSION"
    fi

    if [ -f "$XRAY_CONFIG" ]; then
        if "$XRAY_BIN" run -test -config "$XRAY_CONFIG" >/dev/null 2>&1; then
            doctor_emit pass "xray-config" "configuration test passed"
        else
            doctor_emit fail "xray-config" "xray run -test failed"
        fi
    else
        doctor_emit warn "xray-config" "not found: $XRAY_CONFIG"
    fi
}

doctor_check_state_config_sync() {
    local mode="$1"
    case "$mode" in
        reality|reality-vision|vision|vison|reality-self|xhttp-reality|xhttp-reality-self) ;;
        *) return 0 ;;
    esac
    [ -f "$XRAY_CONFIG" ] || return 0
    if reality_config_matches_state; then
        doctor_emit pass "config-sync" "OneKey state matches the Xray REALITY configuration"
    else
        doctor_emit warn "config-sync" "$(reality_config_drift_detail)"
    fi
}

doctor_check_caddy() {
    local required="$1"
    if ! have_cmd caddy; then
        if [ "$required" = "1" ]; then
            doctor_emit fail "caddy" "required by the current mode but not installed"
        else
            doctor_emit pass "caddy" "not required by the current mode"
        fi
        return
    fi
    doctor_emit pass "caddy" "version $(caddy_version_number || printf 'unknown')"
    if [ "$required" = "1" ]; then
        if [ ! -f "$CADDYFILE" ]; then
            doctor_emit fail "caddy-config" "not found: $CADDYFILE"
        elif caddy validate --config "$CADDYFILE" --adapter caddyfile >/dev/null 2>&1; then
            doctor_emit pass "caddy-config" "configuration validation passed"
        else
            doctor_emit fail "caddy-config" "caddy validate failed"
        fi
        if [ -f "$CADDYFILE" ] && ! grep -q '^# Managed by OneKey Xray' "$CADDYFILE"; then
            doctor_emit warn "caddy-ownership" "Caddyfile has no OneKey marker and may contain unrelated sites"
        fi
    fi
}

doctor_check_services() {
    local caddy_required="$1"
    if ! have_cmd systemctl || ! systemctl list-unit-files >/dev/null 2>&1; then
        doctor_emit warn "systemd" "systemctl is not usable in this environment"
        return
    fi

    if systemctl is-active --quiet "$XRAY_SERVICE"; then
        doctor_emit pass "service:xray" "running"
    else
        doctor_emit fail "service:xray" "not running"
    fi

    if [ "$caddy_required" = "1" ]; then
        if systemctl is-active --quiet "$CADDY_SERVICE"; then
            doctor_emit pass "service:caddy" "running"
        else
            doctor_emit fail "service:caddy" "required by the current mode but not running"
        fi
    fi
}

doctor_check_network() {
    local mode="$1" domain target expected
    [ "$DOCTOR_OFFLINE" -eq 0 ] || {
        doctor_emit warn "network-checks" "skipped by --offline"
        return
    }

    case "$mode" in
        xhttp|reality-self|xhttp-reality-self)
            domain="$(jq -r '.domain // ""' "$STATE_FILE")"
            if [ -n "$domain" ]; then
                expected="$(detect_public_ip || true)"
                if check_domain_points_here "$domain" "$expected" >/dev/null 2>&1; then
                    doctor_emit pass "dns" "$domain points to this server"
                else
                    doctor_emit fail "dns" "$domain does not point to the detected server address"
                fi
            fi
            ;;
    esac

    case "$mode" in
        reality-vision|reality|vision|vison|xhttp-reality)
            target="$(jq -r '.reality.target // ""' "$STATE_FILE")"
            if [ -z "$target" ]; then
                doctor_emit fail "reality-target" "target is empty"
            elif is_discouraged_reality_target "$(reality_target_host "$target" 2>/dev/null || printf '')"; then
                doctor_emit fail "reality-target" "$target is a discouraged fallback target"
            elif verify_reality_target "$target"; then
                doctor_emit pass "reality-target" "$target passed certificate/TLSv1.3/h2 checks"
            else
                doctor_emit fail "reality-target" "$target failed certificate/TLSv1.3/h2 checks"
            fi
            ;;
    esac
}

doctor_check_logs() {
    local file size
    for file in /var/log/xray/access.log /var/log/xray/error.log; do
        [ -f "$file" ] || continue
        size="$(stat -c '%s' "$file" 2>/dev/null || printf '0')"
        if [ "$size" -gt 104857600 ]; then
            doctor_emit warn "log-size" "$file is $(bytes_human "$size")"
        fi
    done
    if [ -f /var/log/xray/access.log ] &&
        [ ! -f "$XRAY_LOGROTATE_FILE" ] &&
        [ ! -f /etc/logrotate.d/xray ]; then
        doctor_emit warn "logrotate" "Xray file logging is enabled without a detected logrotate policy"
    fi
}

doctor_check_operation_lock() {
    local lock_dir="$ONEKEY_STATE_DIR/.operation.lock" pid=""
    if [ ! -d "$lock_dir" ]; then
        doctor_emit pass "operation-lock" "free"
        return
    fi
    pid="$(cat "$lock_dir/pid" 2>/dev/null || true)"
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
        doctor_emit fail "operation-lock" "another xrayctl operation is active (pid $pid)"
    else
        doctor_emit warn "operation-lock" "stale lock detected; the next write operation will remove it"
    fi
}

doctor_command() {
    local arg mode="" caddy_required=0
    DOCTOR_JSON=0
    DOCTOR_OFFLINE=0
    DOCTOR_FAILURES=0
    DOCTOR_WARNINGS=0
    DOCTOR_RESULTS=()

    for arg in "$@"; do
        case "$arg" in
            --json) DOCTOR_JSON=1 ;;
            --offline) DOCTOR_OFFLINE=1 ;;
            -h|--help)
                printf 'Usage: %s doctor [--offline] [--json]\n' "$ONEKEY_ENTRY"
                return 0
                ;;
            *) die "Unknown doctor option: $arg" ;;
        esac
    done
    if [ "$DOCTOR_JSON" -eq 1 ] && ! have_cmd jq; then
        die "doctor --json requires jq"
    fi

    doctor_check_command bash
    doctor_check_command jq
    doctor_check_command openssl
    doctor_check_command curl
    doctor_check_command qrencode 0

    local state_ok=0
    doctor_check_json_file "$STATE_FILE" 'type == "object" and (.version | type == "number")' "state" && state_ok=1
    doctor_check_json_file "$USERS_FILE" '.users | type == "array"' "users" || true
    doctor_check_mode "$ONEKEY_STATE_DIR" 700 "state-dir"
    doctor_check_mode "$STATE_FILE" 600 "state-permissions"
    doctor_check_mode "$USERS_FILE" 600 "users-permissions"
    if [ -f "$XRAY_CONFIG" ]; then
        local config_mode
        config_mode="$(doctor_file_mode "$XRAY_CONFIG" || true)"
        case "$config_mode" in
            600|640) doctor_emit pass "xray-permissions" "mode $config_mode" ;;
            "") doctor_emit warn "xray-permissions" "could not inspect permissions" ;;
            *) doctor_emit fail "xray-permissions" "mode $config_mode, expected 600 or 640" ;;
        esac
    fi

    if [ "$state_ok" -eq 1 ]; then
        mode="$(jq -r '.mode // ""' "$STATE_FILE")"
        case "$mode" in
            xhttp|reality-self|xhttp-reality-self) caddy_required=1 ;;
        esac
        doctor_emit pass "mode" "$mode"
    else
        DOCTOR_OFFLINE=1
    fi

    doctor_check_operation_lock
    doctor_check_xray
    [ "$state_ok" -eq 0 ] || doctor_check_state_config_sync "$mode"
    doctor_check_caddy "$caddy_required"
    doctor_check_services "$caddy_required"
    [ "$state_ok" -eq 0 ] || doctor_check_network "$mode"
    doctor_check_logs

    if [ -d "${ONEKEY_ROOT}.new" ]; then
        doctor_emit warn "staged-update" "stale directory exists: ${ONEKEY_ROOT}.new"
    fi

    if [ "$DOCTOR_JSON" -eq 1 ]; then
        printf '%s\n' "${DOCTOR_RESULTS[@]}" |
            jq -s \
                --argjson failures "$DOCTOR_FAILURES" \
                --argjson warnings "$DOCTOR_WARNINGS" \
                '{ok: ($failures == 0), failures: $failures, warnings: $warnings, checks: .}'
    else
        printf '\nDoctor summary: %s failure(s), %s warning(s)\n' "$DOCTOR_FAILURES" "$DOCTOR_WARNINGS"
    fi
    [ "$DOCTOR_FAILURES" -eq 0 ]
}
