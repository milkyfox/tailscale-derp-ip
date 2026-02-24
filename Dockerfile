FROM golang:alpine AS builder


# ENV GOPROXY=https://goproxy.cn,direct

RUN apk add --no-cache git
RUN go install tailscale.com/cmd/derper@main

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
    STUN_PORT=3478

EXPOSE 443 3478/udp
CMD ["/entrypoint.sh"]
