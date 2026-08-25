#!/usr/bin/env bash
# Network probing: public address detection and REALITY target selection.

# Auto-selection is a convenience fallback. An explicitly verified target in
# the server's ASN is preferable because it reduces fallback-forwarding abuse.
REALITY_TARGET_CANDIDATES=(
    "www.microsoft.com"
    "www.samsung.com"
    "www.nvidia.com"
    "www.ibm.com"
    "addons.mozilla.org"
    "www.amazon.com"
    "dl.google.com"
)

validate_ipv4() {
    local ip="$1" octet
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    for octet in ${ip//./ }; do
        [ "$octet" -le 255 ] || return 1
    done
    return 0
}

validate_ipv6() {
    local ip="$1" reduced group
    local -a groups=()
    [ -n "$ip" ] && [ "${#ip}" -le 45 ] || return 1
    [[ "$ip" =~ ^[0-9A-Fa-f:]+$ ]] && [[ "$ip" == *:* ]] || return 1
    [[ "$ip" != *:::* ]] || return 1
    if [[ "$ip" == *::* ]]; then
        reduced="${ip/::/:}"
        [[ "$reduced" != *::* ]] || return 1
    else
        reduced="$ip"
    fi
    IFS=':' read -r -a groups <<< "$reduced"
    if [[ "$ip" == *::* ]]; then
        [ "${#groups[@]}" -le 7 ] || return 1
    else
        [ "${#groups[@]}" -eq 8 ] || return 1
    fi
    for group in "${groups[@]}"; do
        [ -z "$group" ] && continue
        [ "${#group}" -le 4 ] || return 1
        [[ "$group" =~ ^[0-9A-Fa-f]+$ ]] || return 1
    done
}

validate_host() {
    local host="$1"
    validate_domain "$host" || validate_ipv4 "$host" || validate_ipv6 "$host"
}

validate_client_address() {
    local address="$1"
    address="${address#[}"
    address="${address%]}"
    validate_host "$address"
}

# Wrap bare IPv6 in brackets so it is usable in a URL authority.
format_host() {
    local host="$1"
    host="${host#[}"
    host="${host%]}"
    if validate_ipv6 "$host"; then
        printf '[%s]\n' "$host"
    else
        printf '%s\n' "$host"
    fi
}

normalize_reality_target() {
    local target="$1" host port
    if [[ "$target" =~ ^\[([^]]+)\]:([0-9]+)$ ]]; then
        host="${BASH_REMATCH[1]}"
        port="${BASH_REMATCH[2]}"
    elif [[ "$target" =~ ^([^:]+):([0-9]+)$ ]]; then
        host="${BASH_REMATCH[1]}"
        port="${BASH_REMATCH[2]}"
    elif validate_host "$target"; then
        host="$target"
        port=443
    else
        return 1
    fi
    validate_host "$host" || return 1
    validate_port "$port" || return 1
    if validate_ipv6 "$host"; then
        printf '[%s]:%s\n' "$host" "$port"
    else
        printf '%s:%s\n' "$host" "$port"
    fi
}

reality_target_host() {
    local normalized
    normalized="$(normalize_reality_target "$1")" || return 1
    if [[ "$normalized" =~ ^\[([^]]+)\]: ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
    else
        printf '%s\n' "${normalized%:*}"
    fi
}

reality_target_port() {
    local normalized
    normalized="$(normalize_reality_target "$1")" || return 1
    printf '%s\n' "${normalized##*:}"
}

is_discouraged_reality_target() {
    local host="${1,,}"
    case "$host" in
        cloudflare.com|*.cloudflare.com|apple.com|*.apple.com|icloud.com|*.icloud.com)
            return 0
            ;;
        *) return 1 ;;
    esac
}

detect_public_ip() {
    local url ip=""
    if have_cmd curl; then
        for url in "https://api.ipify.org" "https://ipv4.icanhazip.com" "https://ifconfig.me/ip"; do
            ip="$(curl -fsS4 --max-time 6 "$url" 2>/dev/null | tr -d '[:space:]')" || ip=""
            if validate_ipv4 "$ip"; then
                printf '%s\n' "$ip"
                return 0
            fi
        done
    fi

    if have_cmd ip; then
        ip="$(ip -4 route get 1.1.1.1 2>/dev/null |
            awk '{for (i = 1; i <= NF; i++) if ($i == "src") {print $(i + 1); exit}}')"
        if validate_ipv4 "$ip"; then
            printf '%s\n' "$ip"
            return 0
        fi
    fi

    if have_cmd curl; then
        ip="$(curl -fsS6 --max-time 6 "https://api64.ipify.org" 2>/dev/null | tr -d '[:space:]')" || ip=""
        if validate_ipv6 "$ip"; then
            printf '%s\n' "$ip"
            return 0
        fi
    fi
    return 1
}

resolve_domain_ips() {
    local domain="$1"
    {
        if have_cmd getent; then
            getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1}' || true
            getent ahostsv6 "$domain" 2>/dev/null | awk '{print $1}' || true
        fi
        if have_cmd dig; then
            dig +short A "$domain" 2>/dev/null || true
            dig +short AAAA "$domain" 2>/dev/null || true
        fi
    } | awk '/^[0-9A-Fa-f:.]+$/' | sort -u
}

resolve_domain_ip() {
    local domain="$1"
    resolve_domain_ips "$domain" | head -n 1
}

verify_reality_target() {
    local input="$1" explicit_port="${2:-}" normalized host out=""
    local -a verify_args=()

    if [ -n "$explicit_port" ]; then
        normalized="$(normalize_reality_target "$input:$explicit_port")" || return 1
    else
        normalized="$(normalize_reality_target "$input")" || return 1
    fi
    host="$(reality_target_host "$normalized")"
    have_cmd openssl && have_cmd timeout || return 1

    if validate_domain "$host"; then
        verify_args=(-verify_hostname "$host" -verify_return_error)
    else
        verify_args=(-verify_ip "$host" -verify_return_error)
    fi

    out="$(timeout 12 openssl s_client -connect "$normalized" -servername "$host" \
        -tls1_3 -alpn h2 "${verify_args[@]}" </dev/null 2>&1 || true)"
    printf '%s' "$out" | grep -q 'TLSv1.3' || return 1
    printf '%s' "$out" | grep -qi 'ALPN protocol *: *h2' || return 1
    printf '%s' "$out" | grep -Eq 'Verify return code: 0|Verification: OK' || return 1
    return 0
}

pick_reality_target() {
    local host target order
    ensure_cmd openssl >/dev/null 2>&1 || true
    ensure_cmd timeout >/dev/null 2>&1
    if have_cmd shuf; then
        order="$(printf '%s\n' "${REALITY_TARGET_CANDIDATES[@]}" | shuf)"
    else
        order="$(printf '%s\n' "${REALITY_TARGET_CANDIDATES[@]}")"
    fi

    while IFS= read -r host; do
        [ -n "$host" ] || continue
        is_discouraged_reality_target "$host" && continue
        target="$host:443"
        if verify_reality_target "$target"; then
            ui_good "REALITY target verified: $target (certificate + TLSv1.3 + h2)"
            printf '%s\n' "$target"
            return 0
        fi
        ui_note "skipped $target (certificate/TLSv1.3/h2 check failed)"
    done <<< "$order"

    return 1
}

port_in_use() {
    local port="$1"
    if have_cmd ss; then
        ss -Hltn "sport = :$port" 2>/dev/null | grep -q . && return 0
        return 1
    fi
    if have_cmd netstat; then
        netstat -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$port\$" && return 0
        return 1
    fi
    return 1
}

check_domain_points_here() {
    local domain="$1" expected="${2:-}" actuals="" summary
    actuals="$(resolve_domain_ips "$domain" || true)"
    if [ -z "$actuals" ]; then
        ui_bad "$domain does not resolve yet; certificates will fail until DNS is set"
        return 1
    fi

    summary="$(printf '%s\n' "$actuals" | awk 'BEGIN { first=1 } { if (!first) printf ","; printf "%s", $0; first=0 }')"
    expected="${expected#[}"
    expected="${expected%]}"
    if [ -n "$expected" ] && { validate_ipv4 "$expected" || validate_ipv6 "$expected"; }; then
        if ! printf '%s\n' "$actuals" | grep -Fxq "$expected"; then
            ui_bad "$domain resolves to $summary but this server looks like $expected"
            return 1
        fi
    fi
    ui_good "$domain resolves to $summary"
    return 0
}
