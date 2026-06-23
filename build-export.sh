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
ARCHS="amd64 arm64"
TAG="latest"
IMAGE_NAME="ghcr.io/milkyfox/tailscale-derp-ip"
LOCAL_MODE=false

# --- Help ---
show_help() {
    cat <<EOF
用法: ./build-export.sh [选项]

选项:
  --arch <arch>   只拉取指定架构 (amd64|arm64)，默认两个都拉
  --tag <tag>     拉取的镜像标签，默认 latest
  --local         本地编译模式：docker build 后导出，只编译当前架构
  --help          显示此帮助

说明:
  从 ghcr.io 拉取 GitHub Actions 已构建的多架构镜像，导出为 tar 文件。
  国内用户可直接 docker load 使用，无需本地编译。
  使用 --local 可在本地 docker build 编译后导出（不需要网络）。
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
            ARCHS="$2"
            shift 2
            ;;
        --tag)
            if [[ -z "${2:-}" || "$2" == -* ]]; then
                log_err "--tag 需要参数"
                exit 1
            fi
            TAG="$2"
            shift 2
            ;;
        --local)
            LOCAL_MODE=true
            shift
            ;;
        --help)
            show_help
            ;;
        *)
            echo -e "${RED}[ERROR]${RESET} 未知选项: $1"
            exit 1
            ;;
    esac
done

# --- Detect local arch ---
detect_arch() {
    case "$(uname -m)" in
        x86_64)  echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) log_err "无法识别的架构: $(uname -m)"; exit 1 ;;
    esac
}

# --- Validate arch values ---
for arch in $ARCHS; do
    case $arch in
        amd64|arm64) ;;
        *)
            log_err "不支持的架构: $arch（仅支持 amd64、arm64）"
            exit 1
            ;;
    esac
done

# --- Pre-flight checks ---
if ! command -v docker &>/dev/null; then
    log_err "docker 未安装，请先安装 Docker"
    exit 1
fi

if ! timeout 5 docker info &>/dev/null; then
    log_err "Docker 守护进程未运行或未响应"
    exit 1
fi

# --- Create output directory ---
mkdir -p dist

# --- Export for each architecture ---
if [ "$LOCAL_MODE" = "true" ]; then
    ARCH=$(detect_arch)
    log_info "本地编译 ${ARCH} 架构镜像..."
    docker build -t "tailscale-derp:latest-${ARCH}" .
    log_info "导出 ${ARCH} tar 包..."
    docker save "tailscale-derp:latest-${ARCH}" -o "dist/tailscale-derp-${ARCH}.tar"
    log_success "完成: dist/tailscale-derp-${ARCH}.tar"
    echo ""
    echo "将 tar 文件传输到目标机器后，运行："
    echo "  ./load-image.sh dist/tailscale-derp-${ARCH}.tar"
    echo "  bash start.sh"
else
    for arch in $ARCHS; do
        log_info "拉取 ${arch} 镜像..."
        docker pull --platform "linux/${arch}" "${IMAGE_NAME}:${TAG}"

        docker tag "${IMAGE_NAME}:${TAG}" "tailscale-derp:latest-${arch}"

        log_info "导出 ${arch} tar 包..."
        docker save "tailscale-derp:latest-${arch}" -o "dist/tailscale-derp-${arch}.tar"

        log_success "完成: dist/tailscale-derp-${arch}.tar"
    done
fi

# --- Final output ---
echo ""
log_success "导出完成！文件列表："
ls -lh dist/tailscale-derp-*.tar 2>/dev/null || echo "  （无文件导出）"

if [ "$LOCAL_MODE" != "true" ]; then
    echo ""
    echo "将 tar 文件传输到目标机器后，运行："
    for arch in $ARCHS; do
        echo "  ./load-image.sh dist/tailscale-derp-${arch}.tar"
    done
    echo "  bash start.sh"
fi
