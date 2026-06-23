#!/bin/bash
set -e

# --- Color definitions ---
GREEN='\033[1;32m'
BLUE='\033[1;36m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
RESET='\033[0m'

log_info()   { echo -e "${BLUE}[INFO]${RESET} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${RESET} $1"; }
log_warn()   { echo -e "${YELLOW}[WARN]${RESET} $1"; }
log_err()    { echo -e "${RED}[ERROR]${RESET} $1"; }

# --- Defaults ---
ARCH=""
TAR_FILE=""

# --- Help ---
show_help() {
    cat <<EOF
用法: ./load-image.sh [选项] [tar文件路径]

选项:
  --arch <arch>   指定架构 (amd64|arm64)，默认自动检测
  --help          显示此帮助

参数:
  tar文件路径     可选，指定要加载的 tar 文件
                  未指定时默认从 dist/ 目录查找: dist/tailscale-derp-<arch>.tar

说明:
  加载导出的 Docker 镜像 tar 文件，并打标签为 tailscale-derp:latest。
  自动检测当前机器架构。

示例:
  ./load-image.sh                                # 自动检测架构，从 dist/ 加载
  ./load-image.sh --arch amd64                   # 指定架构
  ./load-image.sh ~/img/tailscale-derp-amd64.tar # 指定 tar 文件
  ./load-image.sh --arch arm64 ~/img/my.tar      # 同时指定架构和文件
EOF
    exit 0
}

# --- Parameter parsing ---
while [[ $# -gt 0 ]]; do
    case $1 in
        --arch)
            if [[ -z "${2:-}" || "$2" == -* ]]; then
                log_err "--arch 需要参数 (amd64|arm64)"
                exit 1
            fi
            ARCH="$2"
            shift 2
            ;;
        --help)
            show_help
            ;;
        -*) log_err "未知选项: $1"; exit 1 ;;
        *) TAR_FILE="$1"; shift ;;
    esac
done

# --- Auto-detect arch if not specified ---
if [ -z "$ARCH" ]; then
    case "$(uname -m)" in
        x86_64)  ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        *)
            log_err "无法识别的架构: $(uname -m)，请使用 --arch 手动指定"
            exit 1
            ;;
    esac
    log_info "检测到架构: ${ARCH}"
fi

# --- Validate arch ---
case "$ARCH" in
    amd64|arm64) ;;
    *)
        log_err "不支持的架构: ${ARCH}（仅支持 amd64、arm64）"
        exit 1
        ;;
esac

# --- Determine tar file ---
if [ -z "$TAR_FILE" ]; then
    TAR_FILE="dist/tailscale-derp-${ARCH}.tar"
fi

# --- Pre-flight checks ---
if ! command -v docker &>/dev/null; then
    log_err "docker 未安装，请先安装 Docker"
    exit 1
fi

if ! timeout 5 docker info &>/dev/null; then
    log_err "Docker 守护进程未运行或未响应"
    exit 1
fi

if [ ! -f "$TAR_FILE" ]; then
    log_err "文件不存在: ${TAR_FILE}"
    echo ""
    echo "请先运行 ./build-export.sh 导出镜像。"
    exit 1
fi

# --- Load image ---
log_info "加载镜像: ${TAR_FILE}"
docker load -i "$TAR_FILE"

# --- Tag for docker-compose compatibility ---
log_info "打标签: tailscale-derp:latest-${ARCH} → tailscale-derp:latest"
docker tag "tailscale-derp:latest-${ARCH}" "tailscale-derp:latest"

# --- Final output ---
echo ""
log_success "加载完成！"
echo ""
echo "现在可以使用 docker compose up -d 启动服务"
echo ""
docker images tailscale-derp --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
