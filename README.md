# Tailscale DERP Server + Exit Node

部署 Tailscale DERP 和 Exit Node 的 Docker 镜像。

## 功能特性

- 部署 Tailscale DERP server
- 支持 Exit Node

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
    volumes:
      - ./data/state:/var/lib/tailscale
      - ./data/certs:/app/certs
      - /dev/net/tun:/dev/net/tun
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
