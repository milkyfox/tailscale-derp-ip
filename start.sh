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

    DETECTED_IP=$(echo "$LOGS" | grep -oE '"HostName":"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | tail -n 1)

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


if [ -z "$FOUND_IP" ]; then
    FOUND_IP=$(grep 'DERP_IP=' docker-compose.yml | cut -d= -f2 | tr -d ' ' | tr -d '"' | tr -d "'")
fi

DERP_PORT=$(grep 'DERP_PORT=' docker-compose.yml | cut -d= -f2 | tr -d ' ' || echo 443)
STUN_PORT=$(grep 'STUN_PORT=' docker-compose.yml | cut -d= -f2 | tr -d ' ' || echo 3478)

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
    echo -e "${BLUE}Tip: Please keep InsecureForTests: true even if CertName is filled.${RESET}"

else
    echo -e "${RED}Failed to automatically extract CertName from logs.${RESET}"
    echo -e "${YELLOW}Please manually run the following command to check log content:${RESET}"
    echo "docker compose logs --tail=50"
fi
