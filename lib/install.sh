#!/usr/bin/env bash

install_dependencies() {
    ensure_base_deps
}

ensure_xray_user() {
    if id "$XRAY_RUN_USER" >/dev/null 2>&1; then
        return 0
    fi

    info "Creating system user for Xray: $XRAY_RUN_USER"
    if have_cmd useradd; then
        useradd --system --user-group --no-create-home --shell /usr/sbin/nologin "$XRAY_RUN_USER"
    elif have_cmd adduser; then
        adduser --system --no-create-home --disabled-login --group "$XRAY_RUN_USER"
    else
        die "useradd or adduser is required to create $XRAY_RUN_USER"
    fi
}

xray_service_user() {
    have_cmd systemctl || return 1
    systemctl show -p User --value "$XRAY_SERVICE" 2>/dev/null
}

install_xray() {
    ensure_xray_user
    need_cmd curl
    if [ -x "$XRAY_BIN" ]; then
        info "Reinstalling Xray to refresh the official systemd service user"
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --reinstall --install-user "$XRAY_RUN_USER"
    else
        info "Installing Xray with the official XTLS installer"
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --install-user "$XRAY_RUN_USER"
    fi
}

# Skip the (slow) reinstall when Xray is already present and the official
# systemd unit already runs as the dedicated user.
install_xray_if_needed() {
    ensure_xray_user
    if [ -x "$XRAY_BIN" ] && [ "$(xray_service_user || true)" = "$XRAY_RUN_USER" ]; then
        ui_good "Xray already installed and running as $XRAY_RUN_USER"
        return 0
    fi
    install_xray
    if have_cmd systemctl; then
        systemctl enable "$XRAY_SERVICE" >/dev/null 2>&1 || true
    fi
    ui_good "Xray installed"
}

install_all() {
    install_dependencies
    install_xray
    init_state_files
    apply_xray_config
    if have_cmd systemctl; then
        systemctl enable "$XRAY_SERVICE" >/dev/null 2>&1 || true
    fi
    ok "Initialized xrayctl state and Xray config"
    info "Next: run '$ONEKEY_ENTRY setup' for the guided one-key flow"
}
