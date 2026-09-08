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
done

if (user_add bob@example.com 00000000-0000-4000-8000-000000000001 >/dev/null 2>&1); then
    printf '[FAIL] duplicate UUID was accepted\n' >&2
    exit 1
fi
printf '[PASS] duplicate UUID rejected\n'

printf 'Render tests passed\n'
