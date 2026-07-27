# OneKey Xray + Caddy

## 一键安装

一条命令搞定：装依赖、装 Xray、选模式、建用户、出分享链接和二维码。

```bash
wget -qO- https://raw.githubusercontent.com/yz68ac/onekey/main/install.sh | sudo bash
```

跑完只会问一个问题（选哪种模式），域名类模式再多问一个域名，其余全部自动：公网 IP 自动探测、REALITY target 自动挑选并验证 TLSv1.3 + h2、路径和 UUID 自动生成、ACME 邮箱按域名推导。

完全无人值守（一句话都不问）：

```bash
wget -qO- https://raw.githubusercontent.com/yz68ac/onekey/main/install.sh | sudo bash -s -- setup --mode reality -y
```

带域名的模式同理：

```bash
... | sudo bash -s -- setup --mode reality-self --domain www.example.com -y
```

安装完成后会在 `/usr/local/bin/xrayctl` 放一个软链，之后直接用短命令：

```bash
sudo xrayctl                          # 交互菜单
sudo xrayctl user add bob@example.com # 加用户，自动打印链接和二维码
sudo xrayctl link bob@example.com     # 单独看链接和二维码
sudo xrayctl link all --no-qr         # 所有用户的链接，不要二维码
sudo xrayctl status-panel             # 当前模式一览
```

### setup 参数

没给的一律自动探测或随机生成。

| 参数 | 说明 |
| --- | --- |
| `--mode` | `reality` / `reality-self` / `xhttp` / `xhttp-reality` / `xhttp-reality-self`，也接受菜单里的 1-5 |
| `--domain` | `reality-self`、`xhttp`、`xhttp-reality-self` 必需 |
| `--email` | ACME 邮箱，默认按域名推导为 `admin@<域名>` |
| `--address` | 分享链接里的地址，默认取自动探测到的公网 IP |
| `--target` | REALITY 回落目标，默认从内置候选里挑一个通过 TLSv1.3 + h2 验证的 |
| `--path` | XHTTP 路径，不给则随机 |
| `--port` | Xray 监听端口 |
| `--fallback-port` | self-steal 模式下本机 Caddy 的 HTTPS 端口 |
| `--user` | 首个用户 email，默认 `default@onekey.local` |
| `-y` | 全部走默认值，绝不提问 |

依赖（`curl` `wget` `jq` `openssl` `tar` `gpg` `qrencode`）缺什么装什么，支持 apt / dnf / yum / apk / pacman；`qrencode` 装不上只会少一个二维码，不影响主流程。

## 功能
- `xrayctl.sh setup` 一键直达：依赖 → Xray → 模式 → 用户 → 链接 + 二维码。
- `xrayctl.sh` 统一管理入口，无参数进入交互菜单。
- 支持 XHTTP + Caddy：Caddy 管理 80/443 和证书，Xray 监听本地 XHTTP 端口。
- 支持 REALITY + Vision：Xray 直接监听 443，Caddy 会被停止以避免端口冲突。
- 支持 REALITY self-steal + local Caddy：Xray 监听公网 443，REALITY 回落到本机 Caddy `127.0.0.1:8443`。
- 支持 XHTTP + REALITY：Xray 直接监听 443，使用 XHTTP 传输和 REALITY 安全层。
- 支持 XHTTP + REALITY self-steal + local Caddy：Xray 监听公网 443，XHTTP + REALITY 回落到本机 Caddy `127.0.0.1:8443`。
- 支持快速添加、删除、列出 UUID 用户。
- 支持按用户 email 查看 Xray Stats API 流量。
- 支持生成 VLESS 分享链接。
- `caddy-onekey.sh` 可单独安装并配置 Caddy。
- Caddy 安装流程贴近官方 Cloudsmith stable repo 命令。

## 路径约定

- 项目安装目录：`/usr/local/onekey-xray-caddy`
- 短命令软链：`/usr/local/bin/xrayctl` → `xrayctl.sh`
- Xray 生效配置：`/usr/local/etc/xray/config.json`
- Xray 二进制：`/usr/local/bin/xray`
- Xray 运行用户：`xray`
- Caddy 生效配置：`/etc/caddy/Caddyfile`
- 管理状态目录：`/etc/onekey-xray`
- 用户状态：`/etc/onekey-xray/users.json`
- 模式状态：`/etc/onekey-xray/state.json`
- 配置备份：`/etc/onekey-xray/backups`
- 渲染输出：`/etc/onekey-xray/rendered`

`/etc/onekey-xray` 只给脚本保存状态，不替代 Xray 官方配置目录。

`/usr/local/bin/xrayctl` 由 `setup` 创建；如果该路径上已经存在一个真实文件（不是软链），脚本不会覆盖它，只是跳过，后续用完整路径调用即可。可用 `ONEKEY_CLI_LINK` 改到别处。

## 服务用户

- Xray：脚本会创建 `xray` 系统用户，并调用官方安装脚本的 `--install-user xray`，让 systemd 服务以专属用户运行。
- `setup` 会先看 systemd unit 的 `User=` 是不是已经是 `xray`：是就跳过重装，省掉每次一键都去 GitHub 拉一遍官方安装器；不是（或没装过）才真正安装。
- `install` 子命令始终强制走 `--reinstall --install-user xray` 刷新官方 systemd service。官方安装器在版本未变化时可能直接退出而不改运行用户，所以想强制纠正运行用户时用 `install` 而不是 `setup`。
- Caddy：脚本使用 Caddy 官方 apt 包安装，服务用户和 systemd unit 交给官方包维护，通常为 `caddy` 用户。

## 手动使用

想跳过一键流程、自己逐项指定时用下面这些命令。

一行安装并直接执行命令：

```bash
wget -qO- https://raw.githubusercontent.com/yz68ac/onekey/main/install.sh | sudo bash -s -- switch xhttp --domain example.com --email admin@example.com --path /secret
```

默认会把项目安装到 `/usr/local/onekey-xray-caddy`，之后可直接运行：

```bash
sudo /usr/local/onekey-xray-caddy/xrayctl.sh
```

重复运行安装器会在原目录内覆盖更新，不会删除并重建 `/usr/local/onekey-xray-caddy`，所以可以安全地在安装目录中执行一键命令。
克隆后进入目录：

```bash
cd onekey-xray-caddy
chmod +x xrayctl.sh install.sh caddy-onekey.sh
sudo ./xrayctl.sh
```
安装或更新 Xray（强制刷新运行用户，见「服务用户」）：

```bash
sudo ./xrayctl.sh install
```
添加用户（会自动打印该用户的分享链接和二维码）：

```bash
sudo ./xrayctl.sh user add alice@example.com
```
切换到 XHTTP + Caddy：

```bash
sudo ./xrayctl.sh switch xhttp --domain example.com --email admin@example.com --path /secret --port 10000
```

切换到 REALITY + Vision：

```bash
sudo ./xrayctl.sh switch reality --server-name example.com --target example.com:443 --address your.server.com
```

切换到 REALITY self-steal + local Caddy：

```bash
sudo ./xrayctl.sh switch reality-self --domain www.example.com --email admin@example.com --address your.server.com --fallback-port 8443
```

这个模式会生成类似下面的关系：

```text
Client -> Xray REALITY :443
Xray REALITY target -> 127.0.0.1:8443
Caddy HTTPS -> 127.0.0.1:8443, cert for www.example.com
Caddy HTTP -> public :80, normal webpage and ACME HTTP-01
```

这个模式要求域名解析到服务器；Xray 占用公网 443，Caddy 只在 `127.0.0.1:8443` 提供 HTTPS 回落，请保持公网 80 可达，方便 Caddy 用 HTTP-01 申请和续期证书。

切换到 XHTTP + REALITY：

```bash
sudo ./xrayctl.sh switch xhttp-reality --server-name example.com --target example.com:443 --address your.server.com --path /secret
```

切换到 XHTTP + REALITY self-steal + local Caddy：

```bash
sudo ./xrayctl.sh switch xhttp-reality-self --domain www.example.com --email admin@example.com --address your.server.com --path /secret --fallback-port 8443
```

这个模式会生成类似下面的关系：

```text
Client -> Xray XHTTP + REALITY :443
Xray REALITY target -> 127.0.0.1:8443
Caddy HTTPS -> 127.0.0.1:8443, cert for www.example.com
Caddy HTTP -> public :80, normal webpage and ACME HTTP-01
```

XHTTP + REALITY self-steal 的分享链接会使用 `type=xhttp&security=reality`，不会带 `flow=xtls-rprx-vision`。

查看流量：

```bash
sudo ./xrayctl.sh traffic all
sudo ./xrayctl.sh traffic alice@example.com
```
生成分享链接（默认带二维码）：

```bash
sudo ./xrayctl.sh link alice@example.com
sudo ./xrayctl.sh link alice@example.com --no-qr
sudo ./xrayctl.sh link alice@example.com --raw   # 只输出裸链接，方便管道
sudo ./xrayctl.sh link all
```

服务管理：

```bash
sudo ./xrayctl.sh start
sudo ./xrayctl.sh stop
sudo ./xrayctl.sh restart
sudo ./xrayctl.sh status
sudo ./xrayctl.sh logs
sudo ./xrayctl.sh test
```

查看当前模式、地址、端口、用户数和两个服务的运行状态：

```bash
sudo ./xrayctl.sh status-panel
```

单独安装并配置 Caddy：

```bash
sudo ./caddy-onekey.sh --domain example.com --email admin@example.com --xhttp-port 10000 --path /secret
```

单独生成 REALITY self-steal 的本机 Caddy 回落配置：

```bash
sudo ./caddy-onekey.sh --mode reality-self --domain www.example.com --email admin@example.com --fallback-port 8443
```

## 环境变量

都有默认值，只在需要偏离约定时设置。

| 变量 | 默认 | 作用 |
| --- | --- | --- |
| `ONEKEY_INSTALL_DIR` | `/usr/local/onekey-xray-caddy` | 安装器落地目录 |
| `ONEKEY_REPO_URL` / `ONEKEY_BRANCH` | 本仓库 / `main` | 安装器拉取来源，方便从 fork 装 |
| `ONEKEY_CLI_LINK` | `/usr/local/bin/xrayctl` | 短命令软链位置，指向不存在的目录即跳过创建 |
| `ONEKEY_ASSUME_YES` | `0` | 设为 `1` 等价于全局 `-y` |
| `NO_COLOR` / `ONEKEY_NO_COLOR` | 未设置 | 关闭彩色输出；输出不是终端时本来就自动关闭 |
| `ONEKEY_STATE_DIR` | `/etc/onekey-xray` | 状态目录 |
| `XRAY_CONFIG` | `/usr/local/etc/xray/config.json` | Xray 生效配置路径 |
| `XRAY_RUN_USER` | `xray` | Xray systemd 运行用户 |
| `CADDYFILE` | `/etc/caddy/Caddyfile` | Caddy 生效配置路径 |

## 排查

- 一键跑完连不上：先确认服务商安全组／防火墙放行了对应端口，脚本不会替你改防火墙。可以用 `https://tcp.ping.pe/ip:port` 验证端口是否真的开放。
- `reality-self` / `xhttp-reality-self` 拿不到证书：这两个模式下 Xray 占着公网 443，Caddy 只能走 HTTP-01，所以公网 80 必须可达，域名也必须已经解析到本机。一键流程会在切换前做一次解析检查，不匹配只警告不阻断；直接用 `switch` 子命令则不做这个检查。
- 二维码在终端里糊成一团：终端窗口太窄导致换行，拉宽窗口重跑 `xrayctl link <email>`，或者用 `--raw` 取裸链接自己贴到客户端。
- 想把输出写进日志：`xrayctl link alice@example.com --raw` 或加 `NO_COLOR=1`，避免 ANSI 转义混进文件。

## 参考

- Xray 官方安装脚本：<https://github.com/XTLS/Xray-install>
- Xray Transport：<https://xtls.github.io/en/config/transport.html>
- Xray REALITY：<https://xtls.github.io/en/config/transports/reality.html>
- Caddy 官方安装文档：<https://caddyserver.com/docs/install>

## License

MIT
