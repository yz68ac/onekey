# OneKey Xray + Caddy

## 功能
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

## 服务用户

- Xray：脚本会创建 `xray` 系统用户，并调用官方安装脚本的 `--install-user xray`，让 systemd 服务以专属用户运行。
- 已安装 Xray 时，脚本会用 `--reinstall --install-user xray` 强制刷新官方 systemd service；否则官方安装器在版本未变化时可能直接退出，不会改运行用户。
- Caddy：脚本使用 Caddy 官方 apt 包安装，服务用户和 systemd unit 交给官方包维护，通常为 `caddy` 用户。

## 使用

一行安装并进入菜单：

```bash
wget -qO- https://raw.githubusercontent.com/yz68ac/onekey/main/install.sh | sudo bash
```

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
安装或更新 Xray：

```bash
sudo ./xrayctl.sh install
```
添加用户：

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
生成分享链接：

```bash
sudo ./xrayctl.sh link alice@example.com
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

单独安装并配置 Caddy：

```bash
sudo ./caddy-onekey.sh --domain example.com --email admin@example.com --xhttp-port 10000 --path /secret
```

单独生成 REALITY self-steal 的本机 Caddy 回落配置：

```bash
sudo ./caddy-onekey.sh --mode reality-self --domain www.example.com --email admin@example.com --fallback-port 8443
```

## 参考

- Xray 官方安装脚本：<https://github.com/XTLS/Xray-install>
- Xray Transport：<https://xtls.github.io/en/config/transport.html>
- Xray REALITY：<https://xtls.github.io/en/config/transports/reality.html>
- Caddy 官方安装文档：<https://caddyserver.com/docs/install>

## License

MIT
