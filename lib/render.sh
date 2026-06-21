#!/usr/bin/env bash

render_xhttp_config() {
    local output="$1"
    init_state_files
    jq -n \
        --slurpfile state "$STATE_FILE" \
        --slurpfile users "$USERS_FILE" '
        def client:
            {
                email: .email,
                id: .id,
                level: (.level // 0)
            };
        {
            log: {
                loglevel: "warning",
                error: "/var/log/xray/error.log",
                access: "/var/log/xray/access.log"
            },
            api: {
                tag: "api",
                services: ["HandlerService", "LoggerService", "StatsService"]
            },
            stats: {},
            policy: {
                levels: {
                    "0": {
                        statsUserUplink: true,
                        statsUserDownlink: true
                    }
                },
                system: {
                    statsInboundUplink: true,
                    statsInboundDownlink: true,
                    statsOutboundUplink: true,
                    statsOutboundDownlink: true
                }
            },
            routing: {
                rules: [
                    {
                        ruleTag: "api",
                        inboundTag: ["api"],
                        outboundTag: "api"
                    },
                    {
                        ruleTag: "private-ip",
                        ip: ["geoip:private"],
                        outboundTag: "block"
                    }
                ]
            },
            inbounds: [
                {
                    tag: "api",
                    listen: ($state[0].api.host // "127.0.0.1"),
                    port: ($state[0].api.port // 32768),
                    protocol: "dokodemo-door",
                    settings: {
                        address: "127.0.0.1"
                    },
                    sniffing: null
                },
                {
                    tag: "VLESS-XHTTP-CADDY",
                    listen: ($state[0].xhttp.listen // "127.0.0.1"),
                    port: ($state[0].xhttp.port // 10000),
                    protocol: "vless",
                    settings: {
                        clients: (($users[0].users // []) | map(client)),
                        decryption: "none"
                    },
                    streamSettings: {
                        network: "xhttp",
                        security: "none",
                        xhttpSettings: {
                            host: ($state[0].domain // ""),
                            path: ($state[0].xhttp.path // "/xhttp"),
                            mode: "auto"
                        }
                    },
                    sniffing: {
                        enabled: true,
                        destOverride: ["http", "tls", "quic"]
                    }
                }
            ],
            outbounds: [
                { tag: "direct", protocol: "freedom" },
                { tag: "block", protocol: "blackhole" }
            ]
        }' > "$output"
}

render_reality_config() {
    local output="$1"
    init_state_files
    jq -n \
        --slurpfile state "$STATE_FILE" \
        --slurpfile users "$USERS_FILE" '
        def client:
            {
                email: .email,
                id: .id,
                flow: "xtls-rprx-vision",
                level: (.level // 0)
            };
        {
            log: {
                loglevel: "warning",
                error: "/var/log/xray/error.log",
                access: "/var/log/xray/access.log"
            },
            api: {
                tag: "api",
                services: ["HandlerService", "LoggerService", "StatsService"]
            },
            stats: {},
            policy: {
                levels: {
                    "0": {
                        statsUserUplink: true,
                        statsUserDownlink: true
                    }
                },
                system: {
                    statsInboundUplink: true,
                    statsInboundDownlink: true,
                    statsOutboundUplink: true,
                    statsOutboundDownlink: true
                }
            },
            routing: {
                rules: [
                    {
                        ruleTag: "api",
                        inboundTag: ["api"],
                        outboundTag: "api"
                    },
                    {
                        ruleTag: "private-ip",
                        ip: ["geoip:private"],
                        outboundTag: "block"
                    }
                ]
            },
            inbounds: [
                {
                    tag: "api",
                    listen: ($state[0].api.host // "127.0.0.1"),
                    port: ($state[0].api.port // 32768),
                    protocol: "dokodemo-door",
                    settings: {
                        address: "127.0.0.1"
                    },
                    sniffing: null
                },
                {
                    tag: "VLESS-VISION-REALITY",
                    listen: "0.0.0.0",
                    port: ($state[0].reality.listen_port // 443),
                    protocol: "vless",
                    settings: {
                        clients: (($users[0].users // []) | map(client)),
                        decryption: "none"
                    },
                    streamSettings: {
                        network: "raw",
                        security: "reality",
                        realitySettings: {
                            show: false,
                            target: $state[0].reality.target,
                            xver: 0,
                            serverNames: ($state[0].reality.server_names // [$state[0].reality.server_name]),
                            privateKey: $state[0].reality.private_key,
                            shortIds: ($state[0].reality.short_ids // []),
                            spiderX: ($state[0].reality.spider_x // "/")
                        }
                    },
                    sniffing: {
                        enabled: true,
                        destOverride: ["http", "tls", "quic"]
                    }
                }
            ],
            outbounds: [
                { tag: "direct", protocol: "freedom" },
                { tag: "block", protocol: "blackhole" }
            ]
        }' > "$output"
}

render_xhttp_reality_config() {
    local output="$1"
    init_state_files
    jq -n \
        --slurpfile state "$STATE_FILE" \
        --slurpfile users "$USERS_FILE" '
        def client:
            {
                email: .email,
                id: .id,
                level: (.level // 0)
            };
        {
            log: {
                loglevel: "warning",
                error: "/var/log/xray/error.log",
                access: "/var/log/xray/access.log"
            },
            api: {
                tag: "api",
                services: ["HandlerService", "LoggerService", "StatsService"]
            },
            stats: {},
            policy: {
                levels: {
                    "0": {
                        statsUserUplink: true,
                        statsUserDownlink: true
                    }
                },
                system: {
                    statsInboundUplink: true,
                    statsInboundDownlink: true,
                    statsOutboundUplink: true,
                    statsOutboundDownlink: true
                }
            },
            routing: {
                rules: [
                    {
                        ruleTag: "api",
                        inboundTag: ["api"],
                        outboundTag: "api"
                    },
                    {
                        ruleTag: "private-ip",
                        ip: ["geoip:private"],
                        outboundTag: "block"
                    }
                ]
            },
            inbounds: [
                {
                    tag: "api",
                    listen: ($state[0].api.host // "127.0.0.1"),
                    port: ($state[0].api.port // 32768),
                    protocol: "dokodemo-door",
                    settings: {
                        address: "127.0.0.1"
                    },
                    sniffing: null
                },
                {
                    tag: "VLESS-XHTTP-REALITY",
                    listen: "0.0.0.0",
                    port: ($state[0].reality.listen_port // 443),
                    protocol: "vless",
                    settings: {
                        clients: (($users[0].users // []) | map(client)),
                        decryption: "none"
                    },
                    streamSettings: {
                        network: "xhttp",
                        security: "reality",
                        realitySettings: {
                            show: false,
                            target: $state[0].reality.target,
                            xver: 0,
                            serverNames: ($state[0].reality.server_names // [$state[0].reality.server_name]),
                            privateKey: $state[0].reality.private_key,
                            shortIds: ($state[0].reality.short_ids // []),
                            spiderX: ($state[0].reality.spider_x // "/")
                        },
                        xhttpSettings: {
                            host: "",
                            path: ($state[0].xhttp.path // "/xhttp"),
                            mode: "auto"
                        }
                    },
                    sniffing: {
                        enabled: true,
                        destOverride: ["http", "tls", "quic"]
                    }
                }
            ],
            outbounds: [
                { tag: "direct", protocol: "freedom" },
                { tag: "block", protocol: "blackhole" }
            ]
        }' > "$output"
}

render_xray_config() {
    local output="$1" mode
    init_state_files
    mode="$(state_get '.mode // "xhttp"')"
    case "$mode" in
        xhttp)
            render_xhttp_config "$output"
            ;;
        xhttp-reality)
            render_xhttp_reality_config "$output"
            ;;
        reality|reality-vision|vision|vison)
            render_reality_config "$output"
            ;;
        *)
            die "Unsupported mode in state: $mode"
            ;;
    esac
    jq -e . "$output" >/dev/null || die "Rendered invalid JSON: $output"
}

test_xray_config_file() {
    local file="$1"
    jq -e . "$file" >/dev/null || die "Invalid JSON: $file"
    if have_cmd "$XRAY_BIN"; then
        "$XRAY_BIN" run -test -config "$file" >/dev/null
    else
        warn "$XRAY_BIN not found; skipped xray run -test"
    fi
}

apply_xray_config() {
    init_state_files
    mkdir -p "$XRAY_CONFIG_DIR" /var/log/xray
    if id "$XRAY_RUN_USER" >/dev/null 2>&1; then
        local xray_group
        xray_group="$(id -gn "$XRAY_RUN_USER")"
        touch /var/log/xray/access.log /var/log/xray/error.log
        chown "$XRAY_RUN_USER:$xray_group" /var/log/xray/access.log /var/log/xray/error.log 2>/dev/null || true
        chmod 600 /var/log/xray/access.log /var/log/xray/error.log 2>/dev/null || true
    fi
    local rendered="$RENDERED_DIR/config.$(timestamp).json"
    render_xray_config "$rendered"
    test_xray_config_file "$rendered"
    backup_file "$XRAY_CONFIG"
    install -m 0644 "$rendered" "$XRAY_CONFIG"
    ok "Wrote Xray config: $XRAY_CONFIG"
}

apply_xray_config_and_restart() {
    apply_xray_config
    if have_cmd systemctl; then
        systemctl restart "$XRAY_SERVICE"
        ok "Restarted $XRAY_SERVICE"
    fi
}

switch_xhttp() {
    local domain="$1" acme_email="$2" path="$3" port="$4"
    validate_domain "$domain" || die "Invalid domain: $domain"
    validate_email "$acme_email" || die "Invalid email: $acme_email"
    validate_port "$port" || die "Invalid port: $port"
    path="$(normalize_path "$path")"

    state_set_xhttp "$domain" "$acme_email" "$path" "$port"
    apply_xray_config_and_restart
    caddy_apply_from_state
    ok "Switched to XHTTP + Caddy"
}

switch_reality_vision() {
    local server_name="$1" target="$2" address="$3" port="$4"
    validate_domain "$server_name" || die "Invalid serverName: $server_name"
    validate_port "$port" || die "Invalid port: $port"
    [ -n "$target" ] || die "REALITY target cannot be empty"
    [ -n "$address" ] || die "Client address cannot be empty"

    init_state_files
    local private_key public_key short_id keys
    private_key="$(state_get '.reality.private_key // ""')"
    public_key="$(state_get '.reality.public_key // ""')"
    short_id="$(state_get '(.reality.short_ids // []) | .[0] // ""')"

    if [ -z "$private_key" ] || [ -z "$public_key" ]; then
        keys="$(generate_x25519_pair)"
        private_key="$(printf '%s\n' "$keys" | sed -n '1p')"
        public_key="$(printf '%s\n' "$keys" | sed -n '2p')"
    fi
    if [ -z "$short_id" ]; then
        short_id="$(generate_short_id)"
    fi
    validate_short_id "$short_id" || die "Invalid generated shortId"

    if have_cmd systemctl && systemctl is-active --quiet "$CADDY_SERVICE"; then
        warn "Stopping Caddy because REALITY/Vision uses port $port directly"
        systemctl stop "$CADDY_SERVICE" || true
    fi

    state_set_reality "$server_name" "$target" "$address" "$port" "$private_key" "$public_key" "$short_id"
    apply_xray_config_and_restart
    ok "Switched to REALITY + Vision"
}

switch_xhttp_reality() {
    local server_name="$1" target="$2" address="$3" path="$4" port="$5"
    validate_domain "$server_name" || die "Invalid serverName: $server_name"
    validate_port "$port" || die "Invalid port: $port"
    [ -n "$target" ] || die "REALITY target cannot be empty"
    [ -n "$address" ] || die "Client address cannot be empty"
    path="$(normalize_path "$path")"

    init_state_files
    local private_key public_key short_id keys
    private_key="$(state_get '.reality.private_key // ""')"
    public_key="$(state_get '.reality.public_key // ""')"
    short_id="$(state_get '(.reality.short_ids // []) | .[0] // ""')"

    if [ -z "$private_key" ] || [ -z "$public_key" ]; then
        keys="$(generate_x25519_pair)"
        private_key="$(printf '%s\n' "$keys" | sed -n '1p')"
        public_key="$(printf '%s\n' "$keys" | sed -n '2p')"
    fi
    if [ -z "$short_id" ]; then
        short_id="$(generate_short_id)"
    fi
    validate_short_id "$short_id" || die "Invalid generated shortId"

    if have_cmd systemctl && systemctl is-active --quiet "$CADDY_SERVICE"; then
        warn "Stopping Caddy because XHTTP + REALITY uses port $port directly"
        systemctl stop "$CADDY_SERVICE" || true
    fi

    state_set_xhttp_reality "$server_name" "$target" "$address" "$path" "$port" "$private_key" "$public_key" "$short_id"
    apply_xray_config_and_restart
    ok "Switched to XHTTP + REALITY"
}
