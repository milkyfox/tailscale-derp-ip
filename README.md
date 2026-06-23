# Tailscale DERP Server + Exit Node

部署 Tailscale DERP 和 Exit Node 的 Docker 镜像。

## 功能特性

- 部署 Tailscale DERP server
- 支持 Exit Node

## 新功能

- **Peer Relay**: 将设备配置为高吞吐量 UDP 中继节点，在直连不可用时优先于 DERP 进行流量中继
- **Exit Node 开关**: 通过环境变量控制是否启用 Exit Node 功能
- **宿主机 Socket 代理**: 复用宿主机已运行的 tailscaled 实例，无需在容器内启动 tailscaled

## 使用
docker-compose.yml

```yaml
services:
  tailscale-derp:
    image: tailscale-derp:latest
    container_name: tailscale-derp
    restart: always
    network_mode: "host"
    privileged: true
    environment:
      - TAILSCALE_AUTH_KEY=tskey-auth-xxx
      - TAILSCALE_HOSTNAME=
      - DERP_IP=
      - DERP_PORT=
      - STUN_PORT=
      - TAILSCALE_PORT=
      - ENABLE_EXIT_NODE=true       # 可选：是否启用 Exit Node
      - RELAY_SERVER_PORT=          # 可选：Peer Relay UDP 端口（留空不启用）
      - RELAY_STATIC_ENDPOINTS=     # 可选：Peer Relay 静态端点
    volumes:
      - ./data/state:/var/lib/tailscale
      - ./data/certs:/app/certs
      - /dev/net/tun:/dev/net/tun
      # - /var/run/tailscale:/var/run/tailscale:ro  # Socket 代理模式（可选）
```
## 获取镜像

### 方式 1：从 GitHub Container Registry 拉取
```bash
docker pull ghcr.io/milkyfox/tailscale-derp-ip:latest
docker tag ghcr.io/milkyfox/tailscale-derp-ip:latest tailscale-derp:latest
```

### 方式 2：本地编译
```bash
./build-export.sh --local
```

### 方式 3：加载导出的镜像
```bash
./load-image.sh
```

### 配置环境变量

编辑 `docker-compose.yml`，填写以下环境变量：

```yaml
environment:
  - TAILSCALE_AUTH_KEY=tskey-auth-xxx   # 必填：Tailscale Auth Key
  - TAILSCALE_HOSTNAME=                 # 可选：Tailscale 机器名称
  - DERP_IP=                            # 必填：服务器公网 IP
  - DERP_PORT=443                       # 可选：DERP HTTPS 端口（默认 443）
  - STUN_PORT=3478                      # 可选：STUN 端口（默认 3478）
  - TAILSCALE_PORT=41641                # 可选：Tailscale P2P 端口（默认 41641）
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
- 构建并启动容器
- 捕获 CertName
- 输出需要添加到 Tailscale ACL 的 JSON 配置

### 配置 Tailscale ACL

将脚本输出的 JSON 添加到 [Tailscale ACL](https://login.tailscale.com/admin/acls) 的 `derpMap` 中：

```json
{
  "Name": "custom-node-vps",
  "RegionID": 900,
  "HostName": "YOUR_SERVER_IP",
  "CertName": "sha256-raw:YOUR_CERT_HASH",
  "IPv4": "YOUR_SERVER_IP",
  "DERPPort": 443,
  "STUNPort": 3478,
  "InsecureForTests": true
}
```

## 环境变量说明

| 变量 | 必填 | 默认值 | 说明 |
|------|------|--------|------|
| `TAILSCALE_AUTH_KEY` | ✅ | - | Tailscale 认证密钥 |
| `TAILSCALE_HOSTNAME` | ❌ | derp-{DERP_IP} | Tailscale 网络中的主机名 |
| `DERP_IP` | ✅ | - | 服务器公网 IP 或域名 |
| `DERP_PORT` | ❌ | 443 | DERP HTTPS 服务端口 |
| `STUN_PORT` | ❌ | 3478 | STUN 服务端口 |
| `TAILSCALE_PORT` | ❌ | 41641 | Tailscale P2P 通信端口 |
| `RELAY_SERVER_PORT` | ❌ | - | Peer Relay UDP 端口（如 40000），留空则不启用 |
| `RELAY_STATIC_ENDPOINTS` | ❌ | - | Peer Relay 静态端点（逗号分隔 ip:port） |
| `ENABLE_EXIT_NODE` | ❌ | true | 是否启用 Exit Node（true/false） |

## Peer Relay 功能

Tailscale Peer Relay 允许将设备配置为高吞吐量的 UDP 中继节点，在直连不可用时优先于 DERP 进行流量中继。

### 启用 Peer Relay

设置 `RELAY_SERVER_PORT` 环境变量来启用 Peer Relay：

```yaml
environment:
  - RELAY_SERVER_PORT=40000
```

### ACL 配置

在 [Tailscale ACL](https://login.tailscale.com/admin/acls) 的 `grants` 部分添加：

```json
{
  "grants": [{
    "src": ["tag:relay-clients"],
    "dst": ["tag:relay"],
    "app": {"tailscale.com/cap/relay": [{}]}
  }]
}
```

> **注意**：
> - Peer Relay 节点需要打 `tag:relay` 标签，客户端节点需要打 `tag:relay-clients` 标签
> - 所有设备需要 Tailscale >= 1.86
> - Peer Relay 与 Exit Node 可以独立启用

### 静态端点（可选）

```yaml
environment:
  - RELAY_SERVER_PORT=40000
  - RELAY_STATIC_ENDPOINTS=1.2.3.4:40000,5.6.7.8:40000
```

## 宿主机 Socket 代理模式

当宿主机已安装并运行 Tailscale 时，容器可以复用宿主机的 tailscaled 实例，无需在容器内启动 tailscaled。

### 使用方法

在 `volumes` 中挂载宿主机的 tailscaled socket 目录：

```yaml
volumes:
  - /var/run/tailscale:/var/run/tailscale:ro
```

挂载后，容器会自动检测并切换为 Socket 代理模式：
- 跳过容器内的 tailscaled 启动
- 跳过 TUN 设备和 sysctl 配置
- derper 直接通过宿主机 socket 验证客户端
- 忽略 `TAILSCALE_AUTH_KEY`（宿主机已认证）

> **注意**：
> - 挂载**目录**而非文件，避免 tailscaled 重启后 inode 变化
> - Socket 模式时 Exit Node 和 Peer Relay 功能由宿主机管理
> - derper 和宿主机 tailscaled 版本不一致时会输出警告（不阻止启动）

### 安全工作模式（可选）

Socket 代理模式下，容器只需运行 derper，可以替换 `privileged: true` 为最小化权限：

```yaml
# privileged: true  # 不再需要
cap_add:
  - NET_BIND_SERVICE
devices:
  - /dev/net/tun:/dev/net/tun  # 不再需要，可移除
```
