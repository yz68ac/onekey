#!/usr/bin/env bash

XRAY_INSTALLER_URL="${XRAY_INSTALLER_URL:-https://github.com/XTLS/Xray-install/raw/main/install-release.sh}"

install_dependencies() {
    ensure_base_deps
}

xray_service_user() {
    have_cmd systemctl || return 1
    systemctl show -p User --value "$XRAY_SERVICE" 2>/dev/null
}

# The official installer (since Xray-install#123, 2026-10) always creates and
# runs the service as its own dedicated `xray` account; the old
# --install-user option no longer exists. Do not pre-create the account here:
# the installer warns when it has to reuse an existing one.
run_official_xray_installer() {
    local script
    need_cmd curl
    script="$(curl -fsSL --retry 3 --retry-connrefused "$XRAY_INSTALLER_URL")" ||
        die "Failed to download the official Xray installer: $XRAY_INSTALLER_URL"
    bash -c "$script" @ install "$@"
}

install_xray() {
    if [ -x "$XRAY_BIN" ]; then
        # --reinstall would reinstall the *current* version, which can never
        # lift an outdated binary over the supported baseline. -f installs the
        # latest stable release and rewrites the official systemd unit.
        info "Updating Xray to the latest stable release and refreshing its systemd service"
        run_official_xray_installer -f
    else
        info "Installing Xray with the official XTLS installer"
        run_official_xray_installer
    fi
    id "$XRAY_RUN_USER" >/dev/null 2>&1 ||
        die "The official installer did not create the '$XRAY_RUN_USER' account (set XRAY_RUN_USER only if upstream changes its account name)"
}

# Skip the (slow) reinstall when Xray is already present and the official
# systemd unit already runs as the dedicated user.
install_xray_if_needed() {
    local installed_version="" final_version=""
    if [ -x "$XRAY_BIN" ]; then
        installed_version="$(xray_version_number || true)"
    fi
    if [ -x "$XRAY_BIN" ] &&
        [ "$(xray_service_user || true)" = "$XRAY_RUN_USER" ] &&
        version_at_least "$installed_version" "$ONEKEY_MIN_XRAY_VERSION"; then
        ui_good "Xray $installed_version already installed and running as $XRAY_RUN_USER"
        return 0
    fi
    if [ -n "$installed_version" ]; then
        ui_note "updating Xray $installed_version to the latest stable release (baseline $ONEKEY_MIN_XRAY_VERSION+)"
    fi
    install_xray
    final_version="$(xray_version_number || true)"
    version_at_least "$final_version" "$ONEKEY_MIN_XRAY_VERSION" ||
        die "Installed Xray version ${final_version:-unknown} is below $ONEKEY_MIN_XRAY_VERSION"
    if have_cmd systemctl; then
        systemctl enable "$XRAY_SERVICE" >/dev/null 2>&1 || true
    fi
    ui_good "Xray $final_version installed"
}

install_all() {
    local final_version=""
    install_dependencies
    install_xray
    final_version="$(xray_version_number || true)"
    version_at_least "$final_version" "$ONEKEY_MIN_XRAY_VERSION" ||
        die "Installed Xray version ${final_version:-unknown} is below $ONEKEY_MIN_XRAY_VERSION"
    init_state_files
    transaction_begin
    if have_cmd systemctl; then
        systemctl enable "$XRAY_SERVICE" >/dev/null 2>&1 || true
    fi
    apply_xray_config_and_restart
    transaction_commit
    ok "Initialized xrayctl state and restarted Xray"
    info "Next: run '$ONEKEY_ENTRY setup' for the guided one-key flow"
}
