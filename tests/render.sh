#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

if ! command -v jq >/dev/null 2>&1; then
    if [ "${REQUIRE_JQ:-0}" = "1" ]; then
        printf 'jq is required for render tests\n' >&2
        exit 1
    fi
    printf '[SKIP] render tests require jq\n'
    exit 0
fi

TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
TEST_TMP="$(mktemp -d)"
trap 'rm -rf -- "$TEST_TMP"' EXIT

export ONEKEY_ROOT="$TEST_ROOT"
export ONEKEY_STATE_DIR="$TEST_TMP/state"
export STATE_FILE="$ONEKEY_STATE_DIR/state.json"
export USERS_FILE="$ONEKEY_STATE_DIR/users.json"
export BACKUP_DIR="$ONEKEY_STATE_DIR/backups"
export RENDERED_DIR="$ONEKEY_STATE_DIR/rendered"
export XRAY_CONFIG_DIR="$TEST_TMP/xray"
export XRAY_CONFIG="$XRAY_CONFIG_DIR/config.json"
export XRAY_BIN="$TEST_TMP/bin/xray"
mkdir -p "$ONEKEY_STATE_DIR" "$XRAY_CONFIG_DIR" "$(dirname "$XRAY_BIN")"

cat > "$XRAY_BIN" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    uuid)
        if [ "${2:-}" = "-i" ]; then printf '%s\n' "${3:-}"; else printf '11111111-1111-4111-8111-111111111111\n'; fi
        ;;
    run) exit 0 ;;
    version) printf 'Xray 26.3.27 (test)\n' ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$XRAY_BIN"

cat > "$STATE_FILE" <<'EOF'
{
  "version": 1,
  "mode": "xhttp",
  "domain": "example.com",
  "address": "203.0.113.7",
  "acme_email": "admin@example.com",
  "api": {"host": "127.0.0.1", "port": 32768},
  "xhttp": {"listen": "127.0.0.1", "port": 10000, "path": "/test.path"},
  "reality": {
    "listen_port": 443,
    "target": "www.microsoft.com:443",
    "server_name": "www.microsoft.com",
    "server_names": ["www.microsoft.com"],
    "address": "203.0.113.7",
    "private_key": "private",
    "public_key": "public",
    "short_ids": ["0123456789abcdef"],
    "spider_x": "/"
  },
  "reality_self": {"listen": "127.0.0.1", "port": 8443},
  "caddy": {"site_root": "/usr/share/caddy"}
}
EOF
cat > "$USERS_FILE" <<'EOF'
{
  "users": [
    {"email": "alice@example.com", "id": "00000000-0000-4000-8000-000000000001", "level": 0}
  ]
}
EOF
chmod 600 "$STATE_FILE" "$USERS_FILE"

. "$TEST_ROOT/lib/common.sh"
. "$TEST_ROOT/lib/ui.sh"
. "$TEST_ROOT/lib/deps.sh"
. "$TEST_ROOT/lib/state.sh"
. "$TEST_ROOT/lib/generate.sh"
. "$TEST_ROOT/lib/users.sh"
. "$TEST_ROOT/lib/render.sh"

assert_jq() {
    local name="$1" file="$2"
    shift 2
    if jq -e "$@" "$file" >/dev/null; then
        printf '[PASS] %s\n' "$name"
    else
        printf '[FAIL] %s\n' "$name" >&2
        exit 1
    fi
}

for mode in xhttp reality-vision xhttp-reality reality-self xhttp-reality-self; do
    tmp_state="$STATE_FILE.tmp"
    jq --arg mode "$mode" '.mode = $mode' "$STATE_FILE" > "$tmp_state"
    replace_private_file "$tmp_state" "$STATE_FILE"
    output="$TEST_TMP/$mode.json"
    render_xray_config "$output"
    assert_jq "$mode valid JSON" "$output" '.'
    assert_jq "$mode minimum version" "$output" --arg min "$ONEKEY_MIN_XRAY_VERSION" '.version.min == $min'
    assert_jq "$mode online stats" "$output" '.policy.levels["0"].statsUserOnline == true'
    assert_jq "$mode API is loopback" "$output" '.inbounds[0].listen == "127.0.0.1"'
    assert_jq "$mode has one user" "$output" '.inbounds[1].settings.clients | length == 1'
    if [ "$mode" = "xhttp" ]; then
        assert_jq "xhttp trusts X-Forwarded-For from local Caddy" "$output" \
            '.inbounds[1].listen == "127.0.0.1" and .inbounds[1].streamSettings.sockopt.trustedXForwardedFor == ["X-Forwarded-For"]'
    else
        assert_jq "$mode does not trust X-Forwarded-For on a public inbound" "$output" \
            '.inbounds[1].streamSettings.sockopt == null'
    fi
done

cp "$output" "$XRAY_CONFIG"
if reality_config_matches_state; then
    printf '[PASS] REALITY state/config sync detected\n'
else
    printf '[FAIL] matching REALITY state/config reported as drifted\n' >&2
    exit 1
fi

jq '(.inbounds[] | select(.streamSettings.realitySettings != null)
    | .streamSettings.realitySettings.target) = "www.sony.jp:443"' \
    "$XRAY_CONFIG" > "$XRAY_CONFIG.tmp"
replace_private_file "$XRAY_CONFIG.tmp" "$XRAY_CONFIG"
if reality_config_matches_state; then
    printf '[FAIL] REALITY config drift was not detected\n' >&2
    exit 1
fi
printf '[PASS] REALITY config drift detected\n'

. "$TEST_ROOT/lib/setup.sh"
. "$TEST_ROOT/lib/menu.sh"
require_root() { return 0; }
switch_xhttp_reality_self() {
    printf '%s|%s|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" "$5" "$6"
}
onekey_status_panel() { return 0; }
ONEKEY_ASSUME_YES=1
menu_values="$(menu_reconfigure_current)"
if [ "$menu_values" != "www.microsoft.com|admin@example.com|203.0.113.7|/test.path|443|8443" ]; then
    printf '[FAIL] current-mode reconfigure did not preserve existing values: %s\n' "$menu_values" >&2
    exit 1
fi
printf '[PASS] current-mode reconfigure preserved existing values\n'

ask() {
    case "$1" in
        "REALITY serverName/SNI, empty to auto-pick") printf 'www.sony.jp\n' ;;
        *) printf '%s\n' "${2:-}" ;;
    esac
}
switch_reality_vision() { printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$4"; }
menu_values="$(menu_switch_reality 1)"
if [ "$menu_values" != "www.sony.jp|www.sony.jp:443|203.0.113.7|443" ]; then
    printf '[FAIL] changed SNI did not update the suggested target: %s\n' "$menu_values" >&2
    exit 1
fi
printf '[PASS] changed SNI updates the suggested target\n'

if (user_add bob@example.com 00000000-0000-4000-8000-000000000001 >/dev/null 2>&1); then
    printf '[FAIL] duplicate UUID was accepted\n' >&2
    exit 1
fi
printf '[PASS] duplicate UUID rejected\n'

# --- generate_uuid keeps caller input -------------------------------------
supplied="00000000-0000-4000-8000-0000000000aa"
if [ "$(XRAY_BIN="$TEST_TMP/missing-xray" generate_uuid "$supplied")" != "$supplied" ]; then
    printf '[FAIL] supplied UUID was replaced when Xray is missing\n' >&2
    exit 1
fi
if (XRAY_BIN="$TEST_TMP/missing-xray" generate_uuid "some seed" >/dev/null 2>&1); then
    printf '[FAIL] seed without Xray was silently replaced\n' >&2
    exit 1
fi
printf '[PASS] generate_uuid never discards caller input\n'

# --- menu_run survives a failing action ----------------------------------
menu_failing_action() { die "expected failure"; }
menu_run menu_failing_action 2>/dev/null
printf '[PASS] menu_run returns to the menu after a failed action\n'

# --- setup: re-apply keeps the values existing clients depend on ----------
. "$TEST_ROOT/lib/target.sh"
ask() { printf '%s\n' "${2:-}"; }
setup_warn_port() { return 0; }
check_domain_points_here() { return 0; }
detect_public_ip() { printf '198.51.100.1\n'; }
if [ "$(onekey_current_mode)" != "xhttp-reality-self" ]; then
    printf '[FAIL] configured mode not detected: %s\n' "$(onekey_current_mode)" >&2
    exit 1
fi
SETUP_REAPPLY=1
setup_collect_plan xhttp-reality-self 2>/dev/null
plan="$PLAN_DOMAIN|$PLAN_EMAIL|$PLAN_ADDRESS|$PLAN_PATH|$PLAN_PORT|$PLAN_FALLBACK"
if [ "$plan" != "www.microsoft.com|admin@example.com|203.0.113.7|/test.path|443|8443" ]; then
    printf '[FAIL] re-applying the same mode changed existing values: %s\n' "$plan" >&2
    exit 1
fi
printf '[PASS] re-applying the same mode keeps domain, path and ports\n'

SETUP_REAPPLY=0
SETUP_TARGET="www.sony.jp:443"
SETUP_SKIP_TARGET_CHECK=1
setup_collect_plan xhttp-reality 2>/dev/null
if [ "$PLAN_SNI" != "www.sony.jp" ] || [ "$PLAN_ADDRESS" != "198.51.100.1" ] || [ "$PLAN_PATH" = "/test.path" ]; then
    printf '[FAIL] switching modes did not start from fresh values: %s|%s|%s\n' "$PLAN_SNI" "$PLAN_ADDRESS" "$PLAN_PATH" >&2
    exit 1
fi
printf '[PASS] switching modes uses fresh values\n'
SETUP_TARGET=""
SETUP_SKIP_TARGET_CHECK=0

# --- setup: an invalid mode is asked again instead of aborting ------------
answers="$TEST_TMP/answers"
printf '9\n4\n' > "$answers"
ask() {
    local first
    first="$(head -n 1 "$answers")"
    sed -i '1d' "$answers"
    printf '%s\n' "$first"
}
setup_can_ask() { return 0; }
picked="$(setup_choose_mode 1 2>/dev/null)"
if [ "$picked" != "xhttp-reality" ]; then
    printf '[FAIL] invalid mode was not re-asked: %s\n' "$picked" >&2
    exit 1
fi
printf '[PASS] invalid mode input is asked again\n'

printf 'Render tests passed\n'
