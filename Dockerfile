FROM golang:alpine AS builder


# ENV GOPROXY=https://goproxy.cn,direct

RUN apk add --no-cache git
RUN go install tailscale.com/cmd/derper@latest

FROM alpine:edge

# RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories

RUN apk update && apk add --no-cache \
    bash \
    ca-certificates \
    iptables \
    ip6tables \
    iproute2 \
    tailscale \
    curl

COPY --from=builder /go/bin/derper /usr/local/bin/derper

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

RUN mkdir -p /var/lib/tailscale /var/run/tailscale /app/certs

ENV DERP_PORT=443 \
    STUN_PORT=3478 \
    TAILSCALE_PORT=41641 \
    ENABLE_EXIT_NODE=true

LABEL org.opencontainers.image.title="tailscale-derp-ip" \
      org.opencontainers.image.source="https://github.com/milkyfox/tailscale-derp-ip" \
      org.opencontainers.image.description="Tailscale DERP Server + Exit Node Docker Image" \
      org.opencontainers.image.version="1.0.0" \
      org.opencontainers.image.licenses="MIT"

EXPOSE 443/tcp 3478/udp 41641/udp
HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=60s \
    CMD curl -kf https://localhost:${DERP_PORT}/generate_204 || exit 1
CMD ["/entrypoint.sh"]
