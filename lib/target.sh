#!/usr/bin/env bash
# Network probing: public address detection and REALITY target selection.

# Well-known sites that terminate TLSv1.3 and negotiate HTTP/2, are not
# CDN-fronted back into China, and are boring enough to blend in.
REALITY_TARGET_CANDIDATES=(
    "www.apple.com"
    "www.microsoft.com"
    "www.amazon.com"
    "www.samsung.com"
    "www.cloudflare.com"
    "addons.mozilla.org"
    "dl.google.com"
    "www.nvidia.com"
    "www.ibm.com"
    "swdist.apple.com"
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
    local ip="$1"
    [[ "$ip" =~ ^[0-9A-Fa-f:]+$ ]] && [[ "$ip" == *:* ]]
}

# Wrap bare IPv6 in brackets so it is usable in a URL authority.
format_host() {
    local host="$1"
    if validate_ipv6 "$host" && [[ "$host" != \[* ]]; then
        printf '[%s]\n' "$host"
    else
        printf '%s\n' "$host"
    fi
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

    # Fall back to whatever source address the kernel would pick.
    if have_cmd ip; then
        ip="$(ip -4 route get 1.1.1.1 2>/dev/null |
            awk '{for (i = 1; i <= NF; i++) if ($i == "src") {print $(i + 1); exit}}')"
        if validate_ipv4 "$ip"; then
            printf '%s\n' "$ip"
            return 0
        fi
    fi

    # Last resort: IPv6.
    if have_cmd curl; then
        ip="$(curl -fsS6 --max-time 6 "https://api64.ipify.org" 2>/dev/null | tr -d '[:space:]')" || ip=""
        if validate_ipv6 "$ip"; then
            printf '%s\n' "$ip"
            return 0
        fi
    fi
    return 1
}

resolve_domain_ip() {
    local domain="$1" ip=""
    if have_cmd getent; then
        ip="$(getent ahostsv4 "$domain" 2>/dev/null | awk 'NR == 1 {print $1}')"
    fi
    if [ -z "$ip" ] && have_cmd dig; then
        ip="$(dig +short A "$domain" 2>/dev/null | grep -E '^[0-9.]+$' | head -n 1)"
    fi
    [ -n "$ip" ] || return 1
    printf '%s\n' "$ip"
}

# A REALITY target must speak TLSv1.3 and offer h2, otherwise the handshake
# Xray forwards will not look like the real thing.
verify_reality_target() {
    local host="$1" port="${2:-443}" out=""
    have_cmd openssl || return 1
    out="$(timeout 10 openssl s_client -connect "$host:$port" -servername "$host" \
        -tls1_3 -alpn h2 </dev/null 2>&1 || true)"
    printf '%s' "$out" | grep -q 'TLSv1.3' || return 1
    printf '%s' "$out" | grep -qi 'ALPN protocol *: *h2' || return 1
    return 0
}

# Print the first candidate that passes verification.
pick_reality_target() {
    local host order
    ensure_cmd openssl >/dev/null 2>&1 || true
    if have_cmd shuf; then
        order="$(printf '%s\n' "${REALITY_TARGET_CANDIDATES[@]}" | shuf)"
    else
        order="$(printf '%s\n' "${REALITY_TARGET_CANDIDATES[@]}")"
    fi

    while IFS= read -r host; do
        [ -n "$host" ] || continue
        if verify_reality_target "$host"; then
            ui_good "REALITY target verified: $host (TLSv1.3 + h2)"
            printf '%s\n' "$host"
            return 0
        fi
        ui_note "skipped $host (no TLSv1.3/h2 from this server)"
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

# Warn (never block) when the domain does not point here yet.
check_domain_points_here() {
    local domain="$1" expected="${2:-}" actual=""
    actual="$(resolve_domain_ip "$domain" || true)"
    if [ -z "$actual" ]; then
        ui_bad "$domain does not resolve yet; certificates will fail until DNS is set"
        return 1
    fi
    if [ -n "$expected" ] && [ "$actual" != "$expected" ]; then
        ui_bad "$domain resolves to $actual but this server looks like $expected"
        return 1
    fi
    ui_good "$domain resolves to $actual"
    return 0
}
