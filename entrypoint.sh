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
RELAY_SERVER_PORT=${RELAY_SERVER_PORT:-}


# Validate required configuration
if [ -z "${DERP_ADDR}" ]; then
    log_err "DERP_IP or DERP_HOSTNAME must be set. Exiting."
    exit 1
fi


# --- Detect socket proxy mode ---
SOCKET_MODE=false
if [ -S /var/run/tailscale/tailscaled.sock ]; then
    REAL_PATH=$(readlink -f /var/run/tailscale 2>/dev/null || echo "/var/run/tailscale")
    if grep -qF " ${REAL_PATH} " /proc/mounts 2>/dev/null; then
        SOCKET_MODE=true
        log_info "Detected host tailscale socket mount - running in socket proxy mode"
        log_info "Skipping container tailscaled, using host tailscaled at /var/run/tailscale/tailscaled.sock"
    fi
fi


echo -e "
${GREEN}==========================================================${RESET}
${GREEN}   Tailscale DERP Server + Exit Node                      ${RESET}
${GREEN}==========================================================${RESET}"


log_info "Target Address  (DERP_ADDR): ${GREEN}${DERP_ADDR}${RESET}"
log_info "Hostname         (Hostname): ${GREEN}${FINAL_HOSTNAME}${RESET}"
log_info "HTTPS Port      (DERP_PORT): ${GREEN}${DERP_PORT}${RESET}"
log_info "STUN  Port      (STUN_PORT): ${GREEN}${STUN_PORT}${RESET}"

if [ "${SOCKET_MODE}" != "true" ]; then
    log_info "P2P   Port (TAILSCALE_PORT): ${GREEN}${TAILSCALE_UDP_PORT}${RESET}"
    log_info "Relay Port (RELAY_SERVER_PORT): ${GREEN}${RELAY_SERVER_PORT:-not set}${RESET}"
fi

if [ "${SOCKET_MODE}" = "true" ]; then
    log_info "Socket proxy mode active - DERP server will use host tailscaled for client verification"
fi


if [ "$SOCKET_MODE" != "true" ]; then
    log_info "Configuring system network parameters..."


    cat > /etc/sysctl.d/99-tailscale.conf <<EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
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
        ENABLE_EXIT_NODE=${ENABLE_EXIT_NODE:-true}
        if [ "${ENABLE_EXIT_NODE}" = "true" ]; then
            log_info "Auth Key detected, logging in to Tailscale and registering Exit Node..."
        else
            log_info "Auth Key detected, logging in to Tailscale..."
        fi
        
        UP_ARGS=(
            --reset
            --authkey="${TAILSCALE_AUTH_KEY}"
            --hostname="${FINAL_HOSTNAME}"
            --accept-routes
            --accept-dns=false
        )
        if [ "${ENABLE_EXIT_NODE}" = "true" ]; then
            UP_ARGS+=(--advertise-exit-node)
            log_info "Exit Node mode enabled"
        else
            log_info "Exit Node mode disabled (ENABLE_EXIT_NODE=false)"
        fi
        tailscale up "${UP_ARGS[@]}"


        log_info "Waiting for network connection..."
        for i in {1..20}; do
            if tailscale --socket=/var/run/tailscale/tailscaled.sock status --json | grep -q "BackendState.*Running"; then
                if [ "${ENABLE_EXIT_NODE}" = "true" ]; then
                    log_success "Tailscale login successful! Exit Node functionality is ready."
                else
                    log_success "Tailscale login successful!"
                fi
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
        
        # --- Peer Relay Configuration ---
        if [ -n "${RELAY_SERVER_PORT}" ]; then
            log_info "Configuring Peer Relay on UDP port ${RELAY_SERVER_PORT}..."
            
            if [ "${RELAY_SERVER_PORT}" = "${TAILSCALE_UDP_PORT}" ]; then
                log_warn "RELAY_SERVER_PORT (${RELAY_SERVER_PORT}) conflicts with TAILSCALE_PORT (${TAILSCALE_UDP_PORT}), skipping peer relay"
            else
                if tailscale --socket=/var/run/tailscale/tailscaled.sock set --relay-server-port="${RELAY_SERVER_PORT}"; then
                    log_success "Peer Relay enabled on UDP port ${RELAY_SERVER_PORT}"
                    if [ -n "${RELAY_STATIC_ENDPOINTS}" ]; then
                        if tailscale --socket=/var/run/tailscale/tailscaled.sock set --relay-server-static-endpoints="${RELAY_STATIC_ENDPOINTS}"; then
                            log_success "Peer Relay static endpoints: ${RELAY_STATIC_ENDPOINTS}"
                        else
                            log_warn "Failed to set relay-server-static-endpoints"
                        fi
                    fi
                else
                    log_warn "Failed to set relay-server-port (tailscaled may be too old, needs >= 1.86)"
                fi
            fi
        else
            log_info "Peer Relay not configured (RELAY_SERVER_PORT not set)"
        fi
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
fi


# --- Version compatibility check ---
log_info "Checking version compatibility..."
if [ "${SOCKET_MODE}" = "true" ]; then
    # Socket mode: compare derper version vs host tailscaled version
    DERP_VERSION=$(derper --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
    HOST_TS_VERSION=$(tailscale --socket=/var/run/tailscale/tailscaled.sock version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
    if [ -n "${DERP_VERSION}" ] && [ -n "${HOST_TS_VERSION}" ] && [ "${DERP_VERSION}" != "${HOST_TS_VERSION}" ]; then
        log_warn "Version mismatch: derper (${DERP_VERSION}) vs host tailscaled (${HOST_TS_VERSION})"
        log_warn "--verify-clients may not work correctly. Recommend using same version."
    else
        log_success "Version check passed (derper: ${DERP_VERSION:-?}, tailscaled: ${HOST_TS_VERSION:-?})"
    fi
else
    # Full mode: compare derper version vs container tailscale version
    DERP_VERSION=$(derper --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
    CT_TS_VERSION=$(tailscale version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
    if [ -n "${DERP_VERSION}" ] && [ -n "${CT_TS_VERSION}" ] && [ "${DERP_VERSION}" != "${CT_TS_VERSION}" ]; then
        log_warn "Version mismatch: derper (${DERP_VERSION}) vs container tailscaled (${CT_TS_VERSION})"
        log_warn "--verify-clients may not work correctly."
    else
        log_success "Version check passed (derper: ${DERP_VERSION:-?}, tailscaled: ${CT_TS_VERSION:-?})"
    fi
fi


DERP_SOCKET_ARG=""
if [ "${SOCKET_MODE}" = "true" ]; then
    DERP_SOCKET_ARG="--socket=/var/run/tailscale/tailscaled.sock"
fi

echo -e "\n${GREEN}>>> Starting Derper service... <<<${RESET}"


exec derper \
    --hostname="${DERP_ADDR}" \
    --certmode=manual \
    --certdir=/app/certs \
    --a=":${DERP_PORT}" \
    --http-port=-1 \
    --stun-port="${STUN_PORT}" \
    --verify-clients \
    ${DERP_SOCKET_ARG} \
    --stun
