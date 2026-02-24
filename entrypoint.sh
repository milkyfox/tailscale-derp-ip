#!/bin/bash
set -e


# --- Define color variables ---
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;36m'
RED='\033[1;31m'
RESET='\033[0m'


# --- Logging functions ---
log_info() { echo -e "${BLUE}[INFO] $1${RESET}"; }
log_success() { echo -e "${GREEN}[SUCCESS] $1${RESET}"; }
log_warn() { echo -e "${YELLOW}[WARN] $1${RESET}"; }
log_err() { echo -e "${RED}[ERROR] $1${RESET}"; }


# --- Get environment variables ---
DERP_ADDR=${DERP_IP:-$DERP_HOSTNAME}
AUTO_HOSTNAME="derp-${DERP_ADDR}"
FINAL_HOSTNAME=${TAILSCALE_HOSTNAME:-$AUTO_HOSTNAME}


DERP_PORT=${DERP_PORT:-443}
STUN_PORT=${STUN_PORT:-3478}
TAILSCALE_UDP_PORT=${TAILSCALE_PORT:-41641}


echo -e "
${GREEN}==========================================================${RESET}
${GREEN}   Tailscale DERP Server + Exit Node                      ${RESET}
${GREEN}==========================================================${RESET}"


log_info "Target Address  (DERP_ADDR): ${GREEN}${DERP_ADDR}${RESET}"
log_info "Hostname         (Hostname): ${GREEN}${FINAL_HOSTNAME}${RESET}"
log_info "HTTPS Port      (DERP_PORT): ${GREEN}${DERP_PORT}${RESET}"
log_info "STUN  Port      (STUN_PORT): ${GREEN}${STUN_PORT}${RESET}"
log_info "P2P   Port (TAILSCALE_PORT): ${GREEN}${TAILSCALE_UDP_PORT}${RESET}"


log_info "Configuring system network parameters..."


echo 'net.ipv4.ip_forward = 1' | tee -a /etc/sysctl.d/99-tailscale.conf > /dev/null
echo 'net.ipv6.conf.all.forwarding = 1' | tee -a /etc/sysctl.d/99-tailscale.conf > /dev/null
if sysctl -p /etc/sysctl.d/99-tailscale.conf > /dev/null 2>&1; then
    log_success "Kernel IP forwarding enabled"
else
    log_warn "Unable to modify sysctl parameters, hoping the host has already enabled IP forwarding."
fi


if [ ! -d /dev/net ]; then mkdir -p /dev/net; fi
if [ ! -c /dev/net/tun ]; then
    mknod /dev/net/tun c 10 200
    log_success "TUN device created"
fi


rm -f /var/run/tailscale/tailscaled.sock


log_info "Starting tailscaled background daemon..."


tailscaled \
    --state=/var/lib/tailscale/tailscaled.state \
    --socket=/var/run/tailscale/tailscaled.sock \
    --port=${TAILSCALE_UDP_PORT} \
    --no-logs-no-support &


TAILSCALED_PID=$!


log_info "Waiting for tailscaled socket to be created..."
for i in {1..30}; do
    if [ -S /var/run/tailscale/tailscaled.sock ]; then
        log_success "Tailscaled daemon is ready!"
        break
    fi
    if [ $i -eq 30 ]; then
        log_err "Tailscaled startup timed out, please check the logs."
        exit 1
    fi
    sleep 1
done


if [ -n "${TAILSCALE_AUTH_KEY}" ]; then
    log_info "Auth Key detected, logging in to Tailscale and registering Exit Node..."
    
    tailscale up \
        --reset \
        --authkey="${TAILSCALE_AUTH_KEY}" \
        --hostname="${FINAL_HOSTNAME}" \
        --advertise-exit-node \
        --accept-routes


    log_info "Waiting for network connection..."
    for i in {1..20}; do
        if tailscale --socket=/var/run/tailscale/tailscaled.sock status --json | grep -q "BackendState.*Running"; then
            log_success "Tailscale login successful! Exit Node functionality is ready."
            break
        fi


        if [ $i -eq 5 ]; then
             log_warn "Status check not yet passed, current status (debug):"
             tailscale --socket=/var/run/tailscale/tailscaled.sock status --json | grep "BackendState" || echo "Unable to get status"
        fi


        if [ $i -eq 20 ]; then
            log_warn "Tailscale login is responding slowly, but will continue trying to start Derper..."
        fi
        sleep 1
    done
else
    echo -e "
${YELLOW}##############################################################${RESET}
${YELLOW}#                 WARNING: Auth Key not provided             #${RESET}
${YELLOW}##############################################################${RESET}
${YELLOW}# 1. Exit Node functionality will not be available.          #${RESET}
${YELLOW}# 2. Client verification (--verify-clients) will not work.   #${RESET}
${YELLOW}##############################################################${RESET}
"
    log_info "Skipping Tailscale login step..."
fi


echo -e "\n${GREEN}>>> Starting Derper service... <<<${RESET}"


exec derper \
    --hostname="${DERP_ADDR}" \
    --certmode=manual \
    --certdir=/app/certs \
    --a=":${DERP_PORT}" \
    --http-port=-1 \
    --stun-port=${STUN_PORT} \
    --verify-clients \
    --stun