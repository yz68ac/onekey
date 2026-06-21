# OneKey Xray + Caddy

这是一个偏个人使用的 Xray 管理脚本骨架，吸收了 `zxcvos/Xray-script` 里比较实用的部分：交互式菜单、JSON 状态、`jq` 渲染配置、分享链接生成、Stats API 流量统计。它没有沿用上游的大型 Nginx/SNI/Cloudreve/WARP 体系，而是收窄成 Xray + Caddy。

目标系统：Debian/Ubuntu + systemd。

## 功能

- `xrayctl.sh` 统一管理入口，无参数进入交互菜单。
- 支持 XHTTP + Caddy：Caddy 管理 80/443 和证书，Xray 监听本地 XHTTP 端口。
- 支持 REALITY + Vision：Xray 直接监听 443，Caddy 会被停止以避免端口冲突。
- 支持 XHTTP + REALITY：Xray 直接监听 443，使用 XHTTP 传输和 REALITY 安全层。
- 支持快速添加、删除、列出 UUID 用户。
- 支持按用户 email 查看 Xray Stats API 流量。
- 支持生成 VLESS 分享链接。
- `caddy-onekey.sh` 可单独安装并配置 Caddy。
- Caddy 安装流程贴近官方 Cloudsmith stable repo 命令。

## 路径约定

- Xray 生效配置：`/usr/local/etc/xray/config.json`
- Xray 二进制：`/usr/local/bin/xray`
- Caddy 生效配置：`/etc/caddy/Caddyfile`
- 管理状态目录：`/etc/onekey-xray`
- 用户状态：`/etc/onekey-xray/users.json`
- 模式状态：`/etc/onekey-xray/state.json`
- 配置备份：`/etc/onekey-xray/backups`
- 渲染输出：`/etc/onekey-xray/rendered`

`/etc/onekey-xray` 只给脚本保存状态，不替代 Xray 官方配置目录。

## 使用

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

切换到 XHTTP + REALITY：

```bash
sudo ./xrayctl.sh switch xhttp-reality --server-name example.com --target example.com:443 --address your.server.com --path /secret
```

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

## 和上游 Xray-script 的取舍

保留的思路：

- 菜单式交互。
- `config/state + jq` 生成最终 Xray JSON。
- API inbound + `StatsService` 做流量统计。
- 根据当前配置生成分享链接。
- REALITY 密钥、shortId、path 默认自动生成。

刻意删掉的部分：

- Nginx 源码编译和 SNI 多站点体系。
- Cloudreve、Cloudflare WARP、Docker 管理。
- 大型 i18n 菜单系统。
- 复杂路由规则编辑。

这样做的结果是脚本更小，后续你自己维护更轻松。

## 注意

- REALITY 的 `target/serverName` 需要自己选择合适目标，脚本不会内置固定伪装域名。
- XHTTP + Caddy 模式要求域名解析到服务器，并开放 80/443。
- REALITY + Vision 和 XHTTP + REALITY 模式会直接占用 443，所以脚本会停止 Caddy。
- 不要把 VPS 上的 `/etc/onekey-xray/state.json`、`users.json`、REALITY 私钥提交到 GitHub。

## 参考

- Xray 官方安装脚本：<https://github.com/XTLS/Xray-install>
- Xray Transport：<https://xtls.github.io/en/config/transport.html>
- Xray REALITY：<https://xtls.github.io/en/config/transports/reality.html>
- Caddy 官方安装文档：<https://caddyserver.com/docs/install>

## License

MIT
