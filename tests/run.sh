#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

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
export CADDYFILE="$TEST_TMP/Caddyfile"
export XRAY_LOGROTATE_FILE="$TEST_TMP/onekey-xray.logrotate"
export XRAY_BIN="$TEST_TMP/bin/xray"
export PATH="$TEST_TMP/bin:$PATH"
mkdir -p "$TEST_TMP/bin"

cat > "$TEST_TMP/bin/jq" <<'EOF'
#!/usr/bin/env bash
set -u
file="${*: -1}"
[ -f "$file" ] || exit 1
python -X utf8 -c 'import json,sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$file"
EOF

cat > "$XRAY_BIN" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    x25519)
        case "${MOCK_X25519_STYLE:-current}" in
            old)
                printf 'Private key: private-old\nPublic key: public-old\n'
                ;;
            mid)
                printf 'PrivateKey: private-mid\nPassword: public-mid\nHash32: ignored\n'
                ;;
            current)
                printf 'PrivateKey: private-current\nPassword (PublicKey): public-current\nHash32: ignored\n'
                ;;
        esac
        ;;
    version)
        printf 'Xray 26.3.27 (Xray, Penetrates Everything.)\n'
        ;;
    run)
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
EOF
chmod +x "$TEST_TMP/bin/jq" "$XRAY_BIN"

# shellcheck source=../lib/common.sh
. "$TEST_ROOT/lib/common.sh"
# shellcheck source=../lib/ui.sh
. "$TEST_ROOT/lib/ui.sh"
# shellcheck source=../lib/deps.sh
. "$TEST_ROOT/lib/deps.sh"
# shellcheck source=../lib/state.sh
. "$TEST_ROOT/lib/state.sh"
# shellcheck source=../lib/transaction.sh
. "$TEST_ROOT/lib/transaction.sh"
# shellcheck source=../lib/generate.sh
. "$TEST_ROOT/lib/generate.sh"
# shellcheck source=../lib/target.sh
. "$TEST_ROOT/lib/target.sh"
# shellcheck source=../lib/traffic.sh
. "$TEST_ROOT/lib/traffic.sh"
# shellcheck source=../lib/doctor.sh
. "$TEST_ROOT/lib/doctor.sh"

TESTS=0
FAILURES=0

pass() {
    TESTS=$((TESTS + 1))
    printf '[PASS] %s\n' "$1"
}

fail() {
    TESTS=$((TESTS + 1))
    FAILURES=$((FAILURES + 1))
    printf '[FAIL] %s: %s\n' "$1" "$2" >&2
}

assert_eq() {
    local name="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        pass "$name"
    else
        fail "$name" "expected '$expected', got '$actual'"
    fi
}

assert_ok() {
    local name="$1"
    shift
    if "$@"; then pass "$name"; else fail "$name" "command failed"; fi
}

assert_fail() {
    local name="$1"
    shift
    if "$@" >/dev/null 2>&1; then fail "$name" "command unexpectedly succeeded"; else pass "$name"; fi
}

assert_eq "normalize relative XHTTP path" "/secret" "$(normalize_path secret)"
assert_eq "preserve valid XHTTP path" "/a.b_c-1" "$(normalize_path /a.b_c-1)"
assert_fail "reject whitespace in XHTTP path" bash -c     '. "$1/lib/common.sh"; normalize_path "bad path"' _ "$TEST_ROOT"

assert_ok "validate IPv4" validate_ipv4 "203.0.113.7"
assert_fail "reject invalid IPv4" validate_ipv4 "999.0.0.1"
assert_ok "validate compressed IPv6" validate_ipv6 "2001:db8::1"
assert_ok "validate loopback IPv6" validate_ipv6 "::1"
assert_fail "reject malformed IPv6" validate_ipv6 ":::"
assert_eq "normalize domain target" "example.com:443" "$(normalize_reality_target example.com)"
assert_eq "normalize IPv6 target" "[2001:db8::1]:8443" "$(normalize_reality_target '[2001:db8::1]:8443')"
assert_ok "flag discouraged target" is_discouraged_reality_target "www.cloudflare.com"

for style in old mid current; do
    export MOCK_X25519_STYLE="$style"
    keys="$(generate_x25519_pair)"
    assert_eq "parse $style private key" "private-$style" "$(printf '%s\n' "$keys" | sed -n '1p')"
    assert_eq "parse $style public key" "public-$style" "$(printf '%s\n' "$keys" | sed -n '2p')"
done

traffic_json='{
  "stat": [
    {
      "name": "user>>>alice@example.com>>>traffic>>>uplink",
      "value": "1176"
    },
    {
      "name": "user>>>alice@example.com>>>traffic>>>downlink",
      "value": "2040"
    }
  ]
}'
assert_eq "parse JSON uplink counter" "1176"     "$(traffic_value_from_output "$traffic_json" 'user>>>alice@example.com>>>traffic>>>uplink')"
assert_eq "parse JSON downlink counter" "2040"     "$(traffic_value_from_output "$traffic_json" 'user>>>alice@example.com>>>traffic>>>downlink')"

traffic_legacy='stat: <
  name: "user>>>alice@example.com>>>traffic>>>uplink"
  value: 42
>'
assert_eq "parse legacy traffic counter" "42"     "$(traffic_value_from_output "$traffic_legacy" 'user>>>alice@example.com>>>traffic>>>uplink')"

assert_eq "parse Xray version" "26.3.27" "$(xray_version_number)"
assert_ok "version comparison" version_at_least "26.3.27" "26.3.27"
assert_fail "version comparison rejects old version" version_at_least "25.8.3" "26.3.27"

mkdir -p "$TEST_TMP/shortcut"
ln -s "$TEST_ROOT/xrayctl.sh" "$TEST_TMP/shortcut/xrayctl"
if [ -L "$TEST_TMP/shortcut/xrayctl" ]; then
    assert_ok "CLI shortcut resolves the installation root" \
        bash "$TEST_TMP/shortcut/xrayctl" --help
else
    printf '[SKIP] CLI shortcut test (filesystem symlinks unavailable)\n'
fi

mkdir -p "$ONEKEY_STATE_DIR" "$XRAY_CONFIG_DIR"
printf '{"version":1,"mode":"xhttp","api":{"host":"127.0.0.1","port":32768},"xhttp":{"path":"/x","port":10000}}\n' > "$STATE_FILE"
printf '{"users":[]}\n' > "$USERS_FILE"
printf 'old-xray\n' > "$XRAY_CONFIG"
printf 'old-caddy\n' > "$CADDYFILE"
printf 'old-logrotate\n' > "$XRAY_LOGROTATE_FILE"
chmod 600 "$STATE_FILE" "$USERS_FILE" "$XRAY_CONFIG"

transaction_begin
printf 'new-state\n' > "$STATE_FILE"
printf 'new-users\n' > "$USERS_FILE"
printf 'new-xray\n' > "$XRAY_CONFIG"
printf 'new-caddy\n' > "$CADDYFILE"
printf 'new-logrotate\n' > "$XRAY_LOGROTATE_FILE"
transaction_rollback

assert_eq "rollback state" "xhttp" "$(python -X utf8 -c 'import json,sys; print(json.load(open(sys.argv[1]))["mode"])' "$STATE_FILE")"
assert_eq "rollback users" '{"users":[]}' "$(tr -d '\r\n ' < "$USERS_FILE")"
assert_eq "rollback Xray config" "old-xray" "$(tr -d '\r\n' < "$XRAY_CONFIG")"
assert_eq "rollback Caddyfile" "old-caddy" "$(tr -d '\r\n' < "$CADDYFILE")"
assert_eq "rollback logrotate" "old-logrotate" "$(tr -d '\r\n' < "$XRAY_LOGROTATE_FILE")"
assert_fail "operation lock released" test -d "$ONEKEY_STATE_DIR/.operation.lock"

printf '\nTests: %s, failures: %s\n' "$TESTS" "$FAILURES"
[ "$FAILURES" -eq 0 ]
