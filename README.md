# Tailscale DERP Server

部署 Tailscale DERP（IP）、Exit Node 和 Peer Relay 的 Docker 镜像。

## 功能

- DERP         : 自建 Tailscale DERP 中继服务器
- Peer Relay   : 将设备配置为 UDP 中继节点，在直连不可用时优先于 DERP 进行流量中继
- Exit Node    : 作为流量出口节点
- Socket Proxy : 复用宿主机已运行的 tailscaled 实例

## 使用

### 获取镜像

- 从 GHRC 拉取
```bash
docker pull ghcr.io/milkyfox/tailscale-derp-ip:latest
docker tag ghcr.io/milkyfox/tailscale-derp-ip:latest tailscale-derp:latest
```

- 本地编译
```bash
./build-export.sh --local
docker tag tailscale-derp:latest-amd64 tailscale-derp:latest
```

- 加载导出的镜像
```bash
./load-image.sh
```

### 配置环境变量

```bash
cp .env.example .env
```

编辑 `.env`，修改以下环境变量，全部环境变量见 `.env.example`。

```bash
TAILSCALE_AUTH_KEY=tskey-auth-xxx    # Tailscale 认证密钥
DERP_IP=                             # 服务器公网 IP
```

### 获取 Auth Key

1. 登录 [Tailscale Admin Console](https://login.tailscale.com/admin/settings/keys)
2. 选择 **Generate auth key...**
3. 勾选 **Reusable**（可重复使用）
4. 勾选 **Ephemeral**（临时节点，可选）
5. 生成并复制 `tskey-auth-xxx`

### 启动服务

```bash
bash start.sh
```

脚本会：
- 启动容器
- 捕获 CertName
- 输出需要添加到 Tailscale ACL 的 JSON 配置

### 配置 Tailscale ACL

将start.sh脚本输出的 JSON 添加到 [Tailscale ACL](https://login.tailscale.com/admin/acls) 的 `derpMap.Regions.{ID}.Nodes` 中：

```json
{
  "Name": "custom-node-vps",
  "RegionID": 900,
  "RegionCode": "custom-derp",
  "HostName": "YOUR_SERVER_IP",
  "CertName": "sha256-raw:YOUR_CERT_HASH",
  "IPv4": "YOUR_SERVER_IP",
  "DERPPort": 443,
  "STUNPort": 3478,
  "InsecureForTests": true
}
```
如果 CertName 已正确设置，可将 `InsecureForTests` 设为 `false`。

## Peer Relay

### 启用 Peer Relay

在 .env 中设置 RELAY_SERVER_PORT 启用。静态端点通过 RELAY_STATIC_ENDPOINTS 配置，格式 ip:port,ip:port。
所有设备需要 Tailscale >= 1.86。

### ACL 配置

在 [Tailscale ACL](https://login.tailscale.com/admin/acls) 的 `grants` 部分添加：

```json
{
  "grants": [{
    "src": ["tag:relay-clients"],
    "dst": ["tag:relay"],
    "app": {"tailscale.com/cap/relay": []}
  }]
}
```

Peer Relay 节点需要打 `tag:relay` 标签，客户端节点需要打 `tag:relay-clients` 标签，也可以允许所有节点：

```json
{
  "grants": [{
    "src": ["*"],
    "dst": ["*"],
    "app": {"tailscale.com/cap/relay": []}
  }]
}
```

## Socket 代理模式

当宿主机已安装并运行 Tailscale 时，容器可以复用宿主机的 tailscaled 实例。

### 使用方法

在现有 compose 文件的 `volumes` 中挂载宿主机的 tailscaled socket 目录：

```yaml
services:
  tailscale-derp:
    image: tailscale-derp:latest
    volumes:
      - /var/run/tailscale:/var/run/tailscale:ro
```

挂载后，容器会自动检测并切换为 Socket 代理模式：
- 跳过容器内的 tailscaled 启动，忽略 `TAILSCALE_AUTH_KEY` 环境变量
- derper 直接通过宿主机 socket 验证客户端
- Exit Node 和 Peer Relay 由宿主机管理

如果 derper 和宿主机 tailscaled 版本不一致时会输出警告。

## 脚本说明

| 脚本 | 说明 |
|------|------|
| `build-export.sh` | 拉取 ghcr.io 镜像或本地编译，导出 tar。使用 `--local` 本地编译并导出 |
| `load-image.sh` | 从导出的 tar 文件加载 Docker 镜像到本地环境 |
