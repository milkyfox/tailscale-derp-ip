#!/bin/bash


# --- Color definitions ---
GREEN='\033[1;32m'
BLUE='\033[1;36m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
RESET='\033[0m'

echo -e "${BLUE}>>> Starting Derper container...${RESET}"

# 1. Start container
docker compose up -d

if [ $? -ne 0 ]; then
    echo -e "${RED}Startup failed, please check docker-compose.yml syntax or Docker installation.${RESET}"
    exit 1
fi

echo -e "${BLUE}>>> Container started successfully, scanning logs to get CertName...${RESET}"
echo -e "${BLUE}>>> (Polling logs, waiting up to 30 seconds)${RESET}"

# 2. Loop to check logs

MAX_RETRIES=30
COUNT=0
FOUND_CERT=""
FOUND_IP=""


while [ $COUNT -lt $MAX_RETRIES ]; do
    LOGS=$(docker compose logs --tail=200 2>&1)
    RAW_HASH=$(echo "$LOGS" | grep -oE 'sha256-raw:[a-f0-9]+' | tail -n 1)

    DETECTED_IP=$(echo "$LOGS" | grep -oP '"hostName":"\K[^"]+' | tail -1)
    DETECTED_DERP_PORT=$(echo "$LOGS" | grep -oP 'serving on :\K[0-9]+' | tail -1)
    DETECTED_STUN_PORT=$(echo "$LOGS" | grep -oP 'STUN server listening on[^:]*:\K[0-9]+' | tail -1)
    DETECTED_RELAY_PORT=$(echo "$LOGS" | grep -oP 'Peer Relay enabled on UDP port \K[0-9]+' | tail -1)

    if [ -n "$RAW_HASH" ]; then
        FOUND_CERT="$RAW_HASH"
        if [ -n "$DETECTED_IP" ]; then
            FOUND_IP="$DETECTED_IP"
        fi
        break
    fi
    
    sleep 1
    ((COUNT++))
    echo -n "."
done


echo "" 


DERP_PORT="${DETECTED_DERP_PORT:-443}"
STUN_PORT="${DETECTED_STUN_PORT:-3478}"
RELAY_SERVER_PORT="${DETECTED_RELAY_PORT:-}"

if [ -n "$FOUND_CERT" ]; then
    echo -e "${GREEN}===========================================${RESET}"
    echo -e "${GREEN}   Derper started successfully             ${RESET}"
    echo -e "${GREEN}===========================================${RESET}"
    echo -e "Detected IP          (HostName):    ${YELLOW}${FOUND_IP}${RESET}"
    echo -e "Detected Fingerprint (CertName):    ${YELLOW}${FOUND_CERT}${RESET}"
    echo ""
    echo -e "${BLUE}Please copy the following JSON into the derpMap of Tailscale ACL:${RESET}"
    echo -e "${YELLOW}"
    echo "{"
    echo "  \"RegionCode\": \"custom-derp\","
    echo "  \"Name\": \"custom-node-vps\","
    echo "  \"RegionID\": 900,"
    echo "  \"HostName\": \"${FOUND_IP}\","
    echo "  \"CertName\": \"${FOUND_CERT}\","
    echo "  \"IPv4\": \"${FOUND_IP}\","
    echo "  \"DERPPort\": ${DERP_PORT},"
    echo "  \"STUNPort\": ${STUN_PORT},"
    echo "  \"InsecureForTests\": true"
    echo "}"
    echo -e "${RESET}"
    echo -e "${BLUE}Tip: If CertName is correctly set, InsecureForTests can be set to false.${RESET}"

else
    echo -e "${RED}Failed to automatically extract CertName from logs.${RESET}"
    echo -e "${YELLOW}Please manually run the following command to check log content:${RESET}"
    echo "docker compose logs --tail=50"
fi

if [ -n "$RELAY_SERVER_PORT" ]; then
    echo ""
    echo -e "${GREEN}===========================================${RESET}"
    echo -e "${GREEN}   Peer Relay Configuration                 ${RESET}"
    echo -e "${GREEN}===========================================${RESET}"
    echo -e "Peer Relay Port:     ${YELLOW}${RELAY_SERVER_PORT}${RESET}"
    echo ""
    echo -e "${BLUE}Please add the following JSON to the grants section of Tailscale ACL:${RESET}"
    echo -e "${YELLOW}"
    echo "{"
    echo "  \"grants\": [{"
    echo "    \"src\": [\"tag:relay-clients\"],"
    echo "    \"dst\": [\"tag:relay\"],"
    echo "    \"app\": {\"tailscale.com/cap/relay\": [{}]}"
    echo "  }]"
    echo "}"
    echo -e "${RESET}"
    echo -e "${BLUE}Notes:${RESET}"
    echo -e "${BLUE}- Peer relay node should have tag:relay${RESET}"
    echo -e "${BLUE}- Client nodes should have tag:relay-clients${RESET}"
    echo -e "${BLUE}- All devices require Tailscale >= 1.86${RESET}"
fi
