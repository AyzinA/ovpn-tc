#!/bin/bash

set -e
set -a
source .env
set +a

echo "[+] Starting Docker container as a systemd service..."

# Start container(s) in detached mode
if [ "$ENABLE_TC" = "true" ]; then
    docker compose -f /opt/openvpn-tc/docker-compose.yml up -d
else
    docker compose -f /opt/openvpn-tc/docker-compose.yml up -d openvpn_client
fi

sleep 2

# --- VPN Config Check ---
echo "[+] Checking logs for VPN cert error..."
if docker logs "${CONTAINER_NAME}" 2>&1 | grep -q "ERROR: VPN CA cert missing!"; then
    echo "[!] Detected missing VPN CA certificate. Stopping container..."
    docker stop "${CONTAINER_NAME}"
    docker rm "${CONTAINER_NAME}"
    echo "[✗] Cannot continue without a valid VPN configuration file."
    exit 1
fi

# --- Continue Setup ---
echo "[✓] No VPN cert error detected. Continuing setup..."

# Routing adjustments inside container
echo "[+] Adjusting container routing..."
docker exec "${CONTAINER_NAME}" sh -c "ip route del default || true"
docker exec "${CONTAINER_NAME}" sh -c "ip route add default via ${WAN_GATEWAY} dev eth1"

# Wait for tun0 interface
docker exec "${CONTAINER_NAME}" sh -c "
while [[ ! -d /sys/class/net/tun0 ]]; do
    echo 'Waiting for tun0 to come up in ${CONTAINER_NAME} container...'
    sleep 1
done"

# Add NAT rule for tun0
echo "[+] Adding iptables POSTROUTING MASQUERADE rule..."
docker exec "${CONTAINER_NAME}" sh -c "iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE"

# Save iptables rules
echo "[+] Saving iptables rules to host..."
mkdir -p /opt/openvpn-tc/iptables
docker exec "${CONTAINER_NAME}" iptables-save > /opt/openvpn-tc/iptables/${CONTAINER_NAME}_rules.v4

# Start dnsmasq inside container
echo "[+] Starting dnsmasq inside the container..."
docker exec "${CONTAINER_NAME}" sh -c "dnsmasq"

echo "[✓] Setup complete. iptables rules saved."

# Keep foreground process for systemd to track
if [ "$ENABLE_TC" = "true" ]; then
    exec docker compose -f /opt/openvpn-tc/docker-compose.yml logs -f
else
    exec docker compose -f /opt/openvpn-tc/docker-compose.yml logs -f openvpn_client
fi
