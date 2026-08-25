#!/usr/bin/env bash
# Snapshot state and generated service configuration before a mutating action.
# Any unhandled error or explicit exit restores the previous files and services.

TRANSACTION_ACTIVE=0
TRANSACTION_DEPTH=0
TRANSACTION_DIR=""
TRANSACTION_LOCK_DIR=""

transaction_lock_acquire() {
    local pid=""
    TRANSACTION_LOCK_DIR="$ONEKEY_STATE_DIR/.operation.lock"
    if mkdir "$TRANSACTION_LOCK_DIR" 2>/dev/null; then
        printf '%s\n' "$$" > "$TRANSACTION_LOCK_DIR/pid"
        return 0
    fi

    pid="$(cat "$TRANSACTION_LOCK_DIR/pid" 2>/dev/null || true)"
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
        die "Another xrayctl operation is running (pid $pid)"
    fi

    warn "Removing stale OneKey operation lock"
    rm -f -- "$TRANSACTION_LOCK_DIR/pid"
    rmdir "$TRANSACTION_LOCK_DIR" 2>/dev/null || die "Cannot remove stale lock: $TRANSACTION_LOCK_DIR"
    mkdir "$TRANSACTION_LOCK_DIR"
    printf '%s\n' "$$" > "$TRANSACTION_LOCK_DIR/pid"
}

transaction_lock_release() {
    [ -n "$TRANSACTION_LOCK_DIR" ] || return 0
    case "$TRANSACTION_LOCK_DIR" in
        "$ONEKEY_STATE_DIR"/.operation.lock)
            rm -f -- "$TRANSACTION_LOCK_DIR/pid"
            rmdir "$TRANSACTION_LOCK_DIR" 2>/dev/null || true
            ;;
    esac
    TRANSACTION_LOCK_DIR=""
}

transaction_dir_is_safe() {
    [ -n "$TRANSACTION_DIR" ] || return 1
    case "$TRANSACTION_DIR" in
        "$ONEKEY_STATE_DIR"/.txn.*) return 0 ;;
        *) return 1 ;;
    esac
}

transaction_capture_file() {
    local file="$1" name="$2"
    if [ -e "$file" ] || [ -L "$file" ]; then
        printf '1\n' > "$TRANSACTION_DIR/$name.exists"
        cp -a -- "$file" "$TRANSACTION_DIR/$name"
    else
        printf '0\n' > "$TRANSACTION_DIR/$name.exists"
    fi
}

transaction_restore_file() {
    local file="$1" name="$2" existed
    existed="$(cat "$TRANSACTION_DIR/$name.exists" 2>/dev/null || printf '0')"
    if [ "$existed" = "1" ]; then
        rm -f -- "$file"
        mkdir -p "$(dirname "$file")"
        cp -a -- "$TRANSACTION_DIR/$name" "$file"
    else
        rm -f -- "$file"
    fi
}
transaction_file_changed() {
    local file="$1" name="$2" existed
    existed="$(cat "$TRANSACTION_DIR/$name.exists" 2>/dev/null || printf '0')"
    if [ "$existed" = "1" ]; then
        [ -e "$file" ] || return 0
        cmp -s -- "$TRANSACTION_DIR/$name" "$file" && return 1
        return 0
    fi
    [ -e "$file" ] || [ -L "$file" ] || return 1
    return 0
}


transaction_service_active() {
    local unit="$1"
    if have_cmd systemctl && systemctl is-active --quiet "$unit" 2>/dev/null; then
        printf '1\n'
    else
        printf '0\n'
    fi
}

transaction_restore_service() {
    local unit="$1" wanted="$2" config_changed="${3:-0}" active=0
    have_cmd systemctl || return 0
    systemctl is-active --quiet "$unit" 2>/dev/null && active=1
    if [ "$wanted" = "1" ]; then
        if [ "$active" = "0" ] || [ "$config_changed" = "1" ]; then
            systemctl restart "$unit" >/dev/null 2>&1 ||
                warn "Rollback could not restart $unit; inspect it with systemctl status $unit"
        fi
    elif [ "$active" = "1" ]; then
        systemctl stop "$unit" >/dev/null 2>&1 ||
            warn "Rollback could not stop $unit"
    fi
}

transaction_cleanup() {
    if transaction_dir_is_safe; then
        rm -rf -- "$TRANSACTION_DIR"
    fi
    TRANSACTION_DIR=""
    transaction_lock_release
}

transaction_exit_handler() {
    local status="$1"
    trap - EXIT
    if [ "$TRANSACTION_ACTIVE" -eq 1 ]; then
        transaction_rollback || true
    fi
    exit "$status"
}

transaction_begin() {
    if [ "$TRANSACTION_ACTIVE" -eq 1 ]; then
        TRANSACTION_DEPTH=$((TRANSACTION_DEPTH + 1))
        return 0
    fi

    init_state_files
    ensure_dirs
    transaction_lock_acquire
    TRANSACTION_DIR="$(mktemp -d "$ONEKEY_STATE_DIR/.txn.XXXXXX")"
    chmod 700 "$TRANSACTION_DIR"
    transaction_capture_file "$XRAY_LOGROTATE_FILE" logrotate

    transaction_capture_file "$STATE_FILE" state
    transaction_capture_file "$USERS_FILE" users
    transaction_capture_file "$XRAY_CONFIG" xray-config
    transaction_capture_file "$CADDYFILE" caddyfile
    transaction_service_active "$XRAY_SERVICE" > "$TRANSACTION_DIR/xray.active"
    transaction_service_active "$CADDY_SERVICE" > "$TRANSACTION_DIR/caddy.active"

    TRANSACTION_ACTIVE=1
    TRANSACTION_DEPTH=1
    trap 'transaction_exit_handler $?' EXIT
}

transaction_commit() {
    [ "$TRANSACTION_ACTIVE" -eq 1 ] || return 0
    TRANSACTION_DEPTH=$((TRANSACTION_DEPTH - 1))
    [ "$TRANSACTION_DEPTH" -le 0 ] || return 0

    trap - EXIT
    TRANSACTION_ACTIVE=0
    TRANSACTION_DEPTH=0
    transaction_cleanup
}

transaction_rollback() {
    local xray_changed=0 caddy_changed=0
    [ "$TRANSACTION_ACTIVE" -eq 1 ] || return 0
    trap - EXIT
    TRANSACTION_ACTIVE=0
    TRANSACTION_DEPTH=0

    transaction_file_changed "$XRAY_CONFIG" xray-config && xray_changed=1
    transaction_file_changed "$CADDYFILE" caddyfile && caddy_changed=1
    warn "Operation failed; restoring the previous OneKey configuration"
    transaction_restore_file "$XRAY_LOGROTATE_FILE" logrotate
    transaction_restore_file "$STATE_FILE" state
    transaction_restore_file "$USERS_FILE" users
    transaction_restore_file "$XRAY_CONFIG" xray-config
    transaction_restore_file "$CADDYFILE" caddyfile

    transaction_restore_service "$XRAY_SERVICE" "$(cat "$TRANSACTION_DIR/xray.active" 2>/dev/null || printf '0')" "$xray_changed"
    transaction_restore_service "$CADDY_SERVICE" "$(cat "$TRANSACTION_DIR/caddy.active" 2>/dev/null || printf '0')" "$caddy_changed"
    transaction_cleanup
    warn "Rollback completed"
}
