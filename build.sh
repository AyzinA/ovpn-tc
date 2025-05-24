#!/bin/bash

set -e
set -a
source .env
set +a

MARKER_FILE="/etc/.openvpn_tc_docker_setup_done"

if [ ! -f "$MARKER_FILE" ]; then
    echo "[+] First-time setup: Installing required packages and Docker..."

    apt update && apt upgrade -y
    apt install -y \
        dnsmasq \
        tcpdump \
        htop \
        vim \
        ncdu \
        curl \
        wget \
        net-tools \
        ca-certificates

    echo "[+] Adding Docker's official GPG key..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    echo "[+] Adding Docker repository..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update
    apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    touch "$MARKER_FILE"
    echo "[✓] Docker and required packages installed."
else
    echo "[i] Docker and system dependencies already installed. Skipping setup..."
fi

echo "[+] Building Docker containers..."
docker compose -f docker-compose.yml build
echo "[✓] Docker containers built successfully."

echo "[+] Attempting to start OpenVPN container without VPN config..."
docker compose -f docker-compose.yml up -d openvpn_client || true

echo "[i] If the VPN config is missing, the container will stop and be removed."
sleep 2

echo "[+] Checking logs for VPN cert error..."
if docker logs "${CONTAINER_NAME}" 2>&1 | grep -q "ERROR: VPN CA cert missing!"; then
    echo "[!] Detected missing VPN CA certificate — this is expected in this validation step."
    
    echo "[i] Stopping and removing container..."
    docker stop "${CONTAINER_NAME}" || true
    docker rm "${CONTAINER_NAME}" || true
    
    if [ -d "$VPN_CONFIG_PATH" ]; then
        rm -rf "$VPN_CONFIG_PATH"
    fi

    echo "[✓] You may now continue to the next script (start.sh) to complete the setup."
    echo "[→] Make sure the ethernet interfaces are connected to the correct WAN and LAN networks."
    exit 0
else
    echo "[!] VPN config appears to exist. This validation should run without a VPN config."
    
    echo "[!] Please remove the file:"
    echo "    -> ${VPN_CONFIG_PATH}"
    echo "[i] Then re-run this script to validate the missing config case properly."

    echo "[i] Stopping and removing container..."
    docker stop "${CONTAINER_NAME}" || true
    docker rm "${CONTAINER_NAME}" || true

    if [ -d "$VPN_CONFIG_PATH" ]; then
        rm -rf "$VPN_CONFIG_PATH"
    fi

    echo "[✗] Exiting because VPN config was unexpectedly found."
    exit 1
fi