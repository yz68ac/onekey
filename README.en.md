# OneKey Xray + Caddy

[中文](README.md) | English

## One-command installation

One command installs dependencies and Xray, lets you select a mode, creates a user, then prints a share link and QR code.

Full automation currently targets **Debian/Ubuntu with systemd**. The dependency layer can recognize other package managers, but the complete Xray/Caddy service workflow is not yet guaranteed on other distributions.

```bash
wget -qO- https://raw.githubusercontent.com/yz68ac/onekey/main/install.sh | sudo bash
```

The installer normally asks only which mode to use. Domain-based modes ask for one additional domain. Everything else is automatic: public IP detection, REALITY target selection and certificate/TLSv1.3/h2 validation, random path and UUID generation, and ACME email derivation.

Fully unattended:

```bash
wget -qO- https://raw.githubusercontent.com/yz68ac/onekey/main/install.sh | sudo bash -s -- setup --mode reality -y
```

For a domain-based mode:

```bash
... | sudo bash -s -- setup --mode reality-self --domain www.example.com -y
```

After setup, a shortcut is created at `/usr/local/bin/xrayctl`:

```bash
sudo xrayctl                          # interactive menu
sudo xrayctl user add bob@example.com # add a user and print link + QR
sudo xrayctl link bob@example.com     # show one user's link
sudo xrayctl link all --no-qr         # show all links without QR codes
sudo xrayctl status-panel             # current mode overview
sudo xrayctl version                  # OneKey / Xray / Caddy versions
sudo xrayctl doctor                   # complete health check
sudo xrayctl doctor --offline         # skip DNS and target network checks
sudo xrayctl bbr status               # show BBR status
```

### Setup options

Anything omitted is detected or generated automatically.

| Option | Description |
| --- | --- |
| `--mode` | `reality` / `reality-self` / `xhttp` / `xhttp-reality` / `xhttp-reality-self`; menu numbers 1-5 are also accepted |
| `--domain` | Required by `reality-self`, `xhttp`, and `xhttp-reality-self` |
| `--email` | ACME email; defaults to `admin@<domain>` |
| `--address` | Address placed in share links; defaults to the detected public IP |
| `--target` | REALITY fallback target in `host[:port]` form; automatic candidates must pass certificate, TLSv1.3, and h2 checks |
| `--skip-target-check` | Advanced troubleshooting only: accept an explicit target without probing it |
| `--path` | XHTTP path; random when omitted |
| `--port` | Xray listen port |
| `--fallback-port` | Local Caddy HTTPS port in self-steal modes |
| `--user` | Initial user email; defaults to `default@onekey.local` |
| `-y` | Accept every default and never prompt |

Missing dependencies (`curl`, `wget`, `jq`, `openssl`, `tar`, `gpg`, `logrotate`, `timeout`, and optional `qrencode`) are installed automatically. The dependency layer supports apt, dnf, yum, apk, and pacman; see the support statement above for the complete service workflow. Failure to install `qrencode` only disables QR output.

## Features

- `xrayctl.sh setup`: dependencies → Xray → mode → user → share link + QR code.
- One management entry point; running `xrayctl.sh` without arguments opens the interactive menu.
- XHTTP + Caddy: Caddy owns ports 80/443 and certificates; Xray listens on a local XHTTP port.
- REALITY + Vision: Xray listens directly on 443; Caddy is stopped to avoid a port conflict.
- REALITY self-steal + local Caddy: Xray listens on public 443 and falls back to local Caddy at `127.0.0.1:8443`.
- XHTTP + REALITY: Xray listens directly on 443 with XHTTP transport and REALITY security.
- XHTTP + REALITY self-steal + local Caddy.
- Fast add, delete, and list operations for UUID users.
- Per-user Xray Stats API traffic display with current JSON and legacy text output compatibility.
- Cross-process operation lock, snapshots, and automatic rollback for configuration and user changes.
- Built-in `doctor`, minimum-version checks, private-file permission checks, and Xray log rotation.
- VLESS share-link generation.
- Manual BBR enable, disable, and status commands; setup never changes kernel networking automatically.
- Standalone Caddy installation and configuration through `caddy-onekey.sh`.
- Caddy installation follows the official Cloudsmith stable repository flow.

## Paths

- Project installation: `/usr/local/onekey-xray-caddy`
- CLI shortcut: `/usr/local/bin/xrayctl` → `xrayctl.sh`
- Active Xray config: `/usr/local/etc/xray/config.json`
- Xray binary: `/usr/local/bin/xray`
- Xray service user: `xray`
- Active Caddyfile: `/etc/caddy/Caddyfile`
- OneKey state directory: `/etc/onekey-xray`
- User state: `/etc/onekey-xray/users.json`
- Mode state: `/etc/onekey-xray/state.json`
- Configuration backups: `/etc/onekey-xray/backups`
- Rendered output: `/etc/onekey-xray/rendered`
- Xray log rotation: `/etc/logrotate.d/onekey-xray`

`/etc/onekey-xray` stores OneKey state; it does not replace Xray's official configuration directory. State, users, rendered files, and backups use private permissions. The active Xray configuration defaults to `0640 root:xray`.

## Safety and rollback

- Mode switches, user changes, and the one-command setup snapshot state, Xray configuration, Caddyfile, logrotate policy, and service state before modifying anything.
- A failed operation restores the previous files and only restores services whose configuration or active state actually changed.
- Only one write operation can run at a time. A stale lock left by an abnormal exit is removed only after confirming that its process no longer exists.
- Every Caddyfile replacement creates a timestamped backup. Replacing a Caddyfile not marked as OneKey-managed produces an explicit warning.

The `/usr/local/bin/xrayctl` shortcut is created by `setup`. If that path already contains a real file rather than a symlink, it is left untouched. Set `ONEKEY_CLI_LINK` to choose another location.

## Service users

- Xray: the script creates an `xray` system user and invokes the official installer with `--install-user xray`.
- `setup` checks both the systemd unit's `User=` value and the installed Xray version. It skips reinstallation only when the user is correct and the version meets the supported baseline; otherwise it refreshes Xray from the official stable channel.
- The `install` command always uses `--reinstall --install-user xray` to refresh the official systemd service. Use it when the runtime user must be corrected explicitly.
- Caddy: the official apt package owns the service user and systemd unit, normally using the `caddy` user.

## Manual usage

Use these commands when you want to bypass the guided setup and provide values directly.

Install and immediately execute a command:

```bash
wget -qO- https://raw.githubusercontent.com/yz68ac/onekey/main/install.sh | sudo bash -s -- switch xhttp --domain example.com --email admin@example.com --path /secret
```

The project is installed at `/usr/local/onekey-xray-caddy` by default:

```bash
sudo /usr/local/onekey-xray-caddy/xrayctl.sh
```

Running the installer again updates the existing installation in place instead of deleting and recreating it.

Clone and run locally:

```bash
cd onekey-xray-caddy
chmod +x xrayctl.sh install.sh caddy-onekey.sh
sudo ./xrayctl.sh
```

Install or update Xray and refresh its runtime user:

```bash
sudo ./xrayctl.sh install
```

Add a user:

```bash
sudo ./xrayctl.sh user add alice@example.com
```

Switch to XHTTP + Caddy:

```bash
sudo ./xrayctl.sh switch xhttp --domain example.com --email admin@example.com --path /secret --port 10000
```

Switch to REALITY + Vision:

```bash
sudo ./xrayctl.sh switch reality --server-name example.com --target example.com:443 --address your.server.com
```

Switch to REALITY self-steal + local Caddy:

```bash
sudo ./xrayctl.sh switch reality-self --domain www.example.com --email admin@example.com --address your.server.com --fallback-port 8443
```

This mode creates the following relationship:

```text
Client -> Xray REALITY :443
Xray REALITY target -> 127.0.0.1:8443
Caddy HTTPS -> 127.0.0.1:8443, cert for www.example.com
Caddy HTTP -> public :80, normal webpage and ACME HTTP-01
```

The domain must resolve to the server. Xray owns public port 443, while Caddy serves local HTTPS only on `127.0.0.1:8443`. Keep public port 80 reachable so Caddy can issue and renew certificates through HTTP-01.

Switch to XHTTP + REALITY:

```bash
sudo ./xrayctl.sh switch xhttp-reality --server-name example.com --target example.com:443 --address your.server.com --path /secret
```

Switch to XHTTP + REALITY self-steal + local Caddy:

```bash
sudo ./xrayctl.sh switch xhttp-reality-self --domain www.example.com --email admin@example.com --address your.server.com --path /secret --fallback-port 8443
```

This mode creates:

```text
Client -> Xray XHTTP + REALITY :443
Xray REALITY target -> 127.0.0.1:8443
Caddy HTTPS -> 127.0.0.1:8443, cert for www.example.com
Caddy HTTP -> public :80, normal webpage and ACME HTTP-01
```

XHTTP + REALITY self-steal links use `type=xhttp&security=reality` without `flow=xtls-rprx-vision`.

Show traffic:

```bash
sudo ./xrayctl.sh traffic all
sudo ./xrayctl.sh traffic alice@example.com
```

These counters belong to the currently running Xray process. OneKey fetches a single complete snapshot to avoid inconsistent per-user queries. Persistent accounting across restarts still requires external storage.

Generate share links:

```bash
sudo ./xrayctl.sh link alice@example.com
sudo ./xrayctl.sh link alice@example.com --no-qr
sudo ./xrayctl.sh link alice@example.com --raw   # raw link only, suitable for pipelines
sudo ./xrayctl.sh link all
```

Share links are generated from `/etc/onekey-xray/state.json` and `users.json`. Do not edit Xray's `config.json` directly; use `r) Reconfigure current mode` in the interactive menu (current values are prefilled) or `xrayctl switch ...` so state, Xray configuration, and links change together. If they drift, `link` warns and `doctor` reports `config-sync`.

Service management:

```bash
sudo ./xrayctl.sh start
sudo ./xrayctl.sh stop
sudo ./xrayctl.sh restart
sudo ./xrayctl.sh status
sudo ./xrayctl.sh logs
sudo ./xrayctl.sh test
```

Show the current mode, address, port, user count, and service status:

```bash
sudo ./xrayctl.sh status-panel
```

BBR management:

```bash
sudo ./xrayctl.sh bbr status
sudo ./xrayctl.sh bbr on
sudo ./xrayctl.sh bbr off
```

`bbr on` writes `/etc/sysctl.d/99-onekey-bbr.conf` and runs `sysctl --system`. It does not restart the server, SSH, Xray, or Caddy. `bbr off` removes only the policy created by OneKey and does not touch BBR settings in other sysctl files.

Install and configure Caddy separately:

```bash
sudo ./caddy-onekey.sh --domain example.com --email admin@example.com --xhttp-port 10000 --path /secret
```

Generate only the local Caddy fallback for REALITY self-steal:

```bash
sudo ./caddy-onekey.sh --mode reality-self --domain www.example.com --email admin@example.com --fallback-port 8443
```

## Environment variables

Every variable has a default and only needs to be set when deviating from the standard layout.

| Variable | Default | Purpose |
| --- | --- | --- |
| `ONEKEY_INSTALL_DIR` | `/usr/local/onekey-xray-caddy` | Installer destination |
| `ONEKEY_REPO_URL` / `ONEKEY_BRANCH` | This repository / `main` | Install from a fork or another branch |
| `ONEKEY_CLI_LINK` | `/usr/local/bin/xrayctl` | CLI shortcut path; creation is skipped if its parent directory is absent |
| `ONEKEY_ASSUME_YES` | `0` | Set to `1` for global non-interactive defaults |
| `NO_COLOR` / `ONEKEY_NO_COLOR` | unset | Disable colored output; colors are already disabled when output is not a terminal |
| `ONEKEY_STATE_DIR` | `/etc/onekey-xray` | State directory |
| `XRAY_CONFIG` | `/usr/local/etc/xray/config.json` | Active Xray configuration |
| `XRAY_RUN_USER` | `xray` | Xray systemd runtime user |
| `CADDYFILE` | `/etc/caddy/Caddyfile` | Active Caddyfile |
| `XRAY_LOGROTATE_FILE` | `/etc/logrotate.d/onekey-xray` | Xray logrotate policy |
| `ONEKEY_MIN_XRAY_VERSION` | `26.3.27` | Minimum Xray version supported by OneKey |
| `BBR_SYSCTL_FILE` | `/etc/sysctl.d/99-onekey-bbr.conf` | BBR sysctl policy |

## Troubleshooting

Run `sudo xrayctl doctor` first. Use `sudo xrayctl doctor --offline` to inspect files, versions, and services without DNS or target network probes. Add `--json` for machine-readable output.

- Cannot connect after setup: check the provider security group and firewall for the required ports. OneKey does not change firewall rules. `https://tcp.ping.pe/ip:port` can confirm whether a TCP port is reachable.
- `reality-self` / `xhttp-reality-self` cannot obtain a certificate: Xray owns public 443, so Caddy must use HTTP-01. Public port 80 must be reachable and the domain must already resolve to this server. Guided setup performs a non-blocking DNS check; direct `switch` commands do not.
- QR code wraps into unreadable output: widen the terminal and run `xrayctl link <email>` again, or use `--raw`.
- Writing links to a log: use `xrayctl link alice@example.com --raw` or set `NO_COLOR=1` to avoid ANSI escapes.
- `link` warns that OneKey state differs from Xray: run `sudo xrayctl`, choose `r) Reconfigure current mode`, and confirm or edit the prefilled values instead of editing `config.json` again.

## Local tests

```bash
bash -n xrayctl.sh install.sh caddy-onekey.sh lib/*.sh tests/*.sh
bash tests/run.sh
bash tests/render.sh
```

Local tests cover path/address/target validation, historical output labels from the Xray `x25519` command, JSON and legacy traffic parsing, version comparison, transactional rollback, and operation locking. Real Xray, Caddy, systemd, ACME issuance, and port-switching behavior still require integration tests in a Linux container or disposable VPS.

## References

- Official Xray installer: <https://github.com/XTLS/Xray-install>
- Xray transport configuration: <https://xtls.github.io/en/config/transport.html>
- Xray REALITY: <https://xtls.github.io/en/config/transports/reality.html>
- Official Caddy installation guide: <https://caddyserver.com/docs/install>

## License

MIT
